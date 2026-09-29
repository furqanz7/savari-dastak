-- Inactive taxonomy types are omitted from the customer navigation. DRAFT is
-- intentionally visible and is rendered by the customer UI as Coming soon.
update dastak_v1.category_types
   set status = 'DRAFT',
       updated_at = now(),
       version = version + 1
 where slug = 'fresh-produce'
   and status = 'INACTIVE';
