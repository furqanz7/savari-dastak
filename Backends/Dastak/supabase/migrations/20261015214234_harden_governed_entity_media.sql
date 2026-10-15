-- Private metadata stays reachable only through the audited media commands.
-- RLS adds default-deny defense in depth without granting direct client access.
set local lock_timeout='5s';
set local statement_timeout='30s';
alter table dastak_v1.governed_entity_media enable row level security;
create index governed_entity_media_created_by_idx
  on dastak_v1.governed_entity_media(created_by);
