create table if not exists public.dastak_device_tokens (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.accounts(id) on delete cascade,
  device_token text not null,
  platform text not null check (platform in ('ios', 'web')),
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (device_token)
);

alter table public.dastak_device_tokens enable row level security;

create index if not exists dastak_device_tokens_account_idx
  on public.dastak_device_tokens (account_id);

revoke all on public.dastak_device_tokens from anon, authenticated;
