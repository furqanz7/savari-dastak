-- Merchant help is separate from order/refund authority. Public access is by
-- a 256-bit recovery capability hashed at the Edge; no direct table/RPC access.
create table private.merchant_support_tickets (
  id uuid primary key,
  token_hash text not null check (token_hash ~ '^[a-f0-9]{64}$'),
  category text not null check (category in ('ACCESS','ORDERS','STORE','EARNINGS','PRIVACY','OTHER')),
  subject text not null check (char_length(subject) between 5 and 100),
  initial_digest bytea not null,
  status text not null default 'OPEN' check (status in ('OPEN','WAITING_ON_MERCHANT','RESOLVED')),
  version integer not null default 1,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);
create index merchant_support_created_idx on private.merchant_support_tickets(created_at desc,id desc);
create index merchant_support_inbox_idx on private.merchant_support_tickets(status,updated_at desc,id desc);
create table private.merchant_support_messages (
  id uuid primary key,
  ticket_id uuid not null references private.merchant_support_tickets(id),
  side text not null check (side in ('MERCHANT','SUPPORT')),
  body text not null check (char_length(body) between 5 and 2000),
  status_after text not null,
  request_digest bytea not null,
  actor_id uuid,
  created_at timestamptz not null default clock_timestamp()
);
create index merchant_support_thread_idx on private.merchant_support_messages(ticket_id,created_at,id);
alter table private.merchant_support_tickets enable row level security;
alter table private.merchant_support_messages enable row level security;
revoke all on private.merchant_support_tickets, private.merchant_support_messages from public,anon,authenticated,service_role;

create function private.merchant_support_snapshot(p_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id',t.id,'category',t.category,'subject',t.subject,
    'status',t.status,'version',t.version,'createdAt',t.created_at,'updatedAt',t.updated_at,
    'messages',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'side',m.side,
      'body',m.body,'createdAt',m.created_at,'status',m.status_after) order by m.created_at,m.id)
      from private.merchant_support_messages m where m.ticket_id=t.id),'[]'::jsonb))
  from private.merchant_support_tickets t where t.id=p_id;
$$;
revoke all on function private.merchant_support_snapshot(uuid) from public,anon,authenticated,service_role;

create function private.merchant_support_command(p_actor uuid,p_input jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  op text := p_input->>'operation';
  ticket private.merchant_support_tickets%rowtype;
  prior private.merchant_support_messages%rowtype;
  tid uuid;
  rid uuid;
  body text := btrim(p_input->>'message');
  subject text := btrim(p_input->>'subject');
  category text := p_input->>'category';
  next_status text;
  request_digest bytea;
  page jsonb;
  cursor_at timestamptz;
  cursor_id uuid;
begin
  if op is null or op not in ('create','read','reply','adminList','adminRead','adminReply') then
    raise exception 'support_invalid' using errcode='22023';
  end if;
  if op like 'admin%' and (p_actor is null or dastak_v1_api.admin_role_for_actor(p_actor) is null) then
    raise exception 'support_forbidden' using errcode='42501';
  end if;
  if op='adminList' then
    if p_input->>'status' is not null and p_input->>'status' not in ('OPEN','WAITING_ON_MERCHANT','RESOLVED') then
      raise exception 'support_invalid' using errcode='22023';
    end if;
    cursor_at := (p_input->>'cursorAt')::timestamptz;
    cursor_id := (p_input->>'cursorId')::uuid;
    if (cursor_at is null) <> (cursor_id is null) then raise exception 'support_invalid'; end if;
    select coalesce(jsonb_agg(row.payload order by row.updated_at desc,row.id desc),'[]'::jsonb) into page
    from (select t.updated_at,t.id,jsonb_build_object('id',t.id,'subject',t.subject,'category',t.category,
      'status',t.status,'version',t.version,'createdAt',t.created_at,'updatedAt',t.updated_at) payload
      from private.merchant_support_tickets t
      where (p_input->>'status' is null or t.status=p_input->>'status')
        and (cursor_at is null or (t.updated_at,t.id)<(cursor_at,cursor_id))
      order by t.updated_at desc,t.id desc limit 41) row;
    return jsonb_build_object('tickets',page);
  end if;
  tid := (p_input->>'ticketId')::uuid;
  if tid is null then raise exception 'support_invalid'; end if;
  if op in ('create','read','reply') and coalesce(p_input->>'tokenHash','') !~ '^[a-f0-9]{64}$' then
    raise exception 'support_not_found' using errcode='P0002';
  end if;
  if op in ('create','reply','adminReply') then
    rid := (p_input->>'requestId')::uuid;
    if rid is null or body is null or char_length(body) not between 5 and 2000 then
      raise exception 'support_invalid' using errcode='22023';
    end if;
    request_digest := sha256(convert_to(jsonb_build_object('op',op,'ticket',tid,'message',body,
      'status',p_input->>'status','actor',p_actor,'version',p_input->>'version')::text,'UTF8'));
  end if;
  if op='create' then
    if category is null or category not in ('ACCESS','ORDERS','STORE','EARNINGS','PRIVACY','OTHER')
      or subject is null or char_length(subject) not between 5 and 100 then
      raise exception 'support_invalid' using errcode='22023';
    end if;
    request_digest := sha256(convert_to(jsonb_build_object('subject',subject,'message',body,'category',category)::text,'UTF8'));
    -- Serializes admission/idempotency across instances. Limits bound unpaid
    -- storage growth; this is not a CAPTCHA or a guarantee against denial of service.
    perform pg_advisory_xact_lock(7610021);
    select * into ticket from private.merchant_support_tickets where id=tid;
    if found then
      if ticket.token_hash<>p_input->>'tokenHash' then
        raise exception 'support_not_found' using errcode='P0002';
      end if;
      if ticket.initial_digest<>request_digest then
        raise exception 'support_conflict' using errcode='23505';
      end if;
      return private.merchant_support_snapshot(tid);
    end if;
    if (select count(*) from private.merchant_support_tickets)>=1000
      or (select count(*) from private.merchant_support_tickets where created_at>clock_timestamp()-interval '1 day')>=100
      or (select count(*) from private.merchant_support_tickets where created_at>clock_timestamp()-interval '1 hour')>=30 then
      raise exception 'support_rate_limited' using errcode='54000';
    end if;
    insert into private.merchant_support_tickets(id,token_hash,category,subject,initial_digest)
      values(tid,p_input->>'tokenHash',category,subject,request_digest);
    insert into private.merchant_support_messages(id,ticket_id,side,body,status_after,request_digest)
      values(rid,tid,'MERCHANT',body,'OPEN',request_digest);
    return private.merchant_support_snapshot(tid);
  end if;
  select * into ticket from private.merchant_support_tickets where id=tid for update;
  if not found or (op in ('read','reply') and ticket.token_hash<>p_input->>'tokenHash') then
    raise exception 'support_not_found' using errcode='P0002';
  end if;
  if op in ('read','adminRead') then return private.merchant_support_snapshot(tid); end if;
  select * into prior from private.merchant_support_messages where id=rid;
  if found then
    if prior.ticket_id<>tid or prior.request_digest<>request_digest then
      raise exception 'support_conflict' using errcode='23505';
    end if;
    return private.merchant_support_snapshot(tid);
  end if;
  if (p_input->>'version')::integer is distinct from ticket.version then
    raise exception 'support_stale' using errcode='40001';
  end if;
  if (select count(*) from private.merchant_support_messages where ticket_id=tid)>=20 then
    raise exception 'support_thread_full' using errcode='54000';
  end if;
  if op='reply' and exists(select 1 from private.merchant_support_messages
    where ticket_id=tid and side='MERCHANT' and created_at>clock_timestamp()-interval '30 seconds') then
    raise exception 'support_rate_limited' using errcode='54000';
  end if;
  next_status := case when op='reply' then 'OPEN' else p_input->>'status' end;
  if next_status is null or next_status not in ('WAITING_ON_MERCHANT','RESOLVED','OPEN') then
    raise exception 'support_invalid' using errcode='22023';
  end if;
  insert into private.merchant_support_messages(id,ticket_id,side,body,status_after,request_digest,actor_id)
    values(rid,tid,case when op='reply' then 'MERCHANT' else 'SUPPORT' end,body,next_status,request_digest,p_actor);
  update private.merchant_support_tickets set status=next_status,version=version+1,updated_at=clock_timestamp() where id=tid;
  return private.merchant_support_snapshot(tid);
end;
$$;
revoke all on function private.merchant_support_command(uuid,jsonb) from public,anon,authenticated,service_role;
create function public.merchant_support_command(p_actor uuid,p_input jsonb) returns jsonb
language sql security invoker set search_path = '' as $$
  select private.merchant_support_command(p_actor,p_input);
$$;
revoke all on function public.merchant_support_command(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.merchant_support_command(uuid,jsonb) to service_role;
grant execute on function private.merchant_support_command(uuid,jsonb) to service_role;
comment on function public.merchant_support_command(uuid,jsonb) is
  'Service-only Merchant help. Edge validates capabilities or verified Admin identity. No account, financial or order mutation authority.';
