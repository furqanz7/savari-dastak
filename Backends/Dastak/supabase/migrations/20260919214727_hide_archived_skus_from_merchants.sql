-- Archived canonical SKUs must not remain in a merchant's selectable catalogue.
-- Merchant selections are current storefront state, not order history; remove them
-- when Admin archives the source SKU so the merchant projection cannot resurface it.
create or replace function dastak_v1.clear_merchant_selections_for_archived_sku()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'INACTIVE' and old.status is distinct from new.status then
    delete from dastak_v1.merchant_sku_selections
     where sku_id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists skus_hide_archived_from_merchants on dastak_v1.skus;
create trigger skus_hide_archived_from_merchants
after update of status on dastak_v1.skus
for each row execute function dastak_v1.clear_merchant_selections_for_archived_sku();

delete from dastak_v1.merchant_sku_selections selection
 where not exists (
   select 1 from dastak_v1.skus sku
    where sku.id = selection.sku_id and sku.status = 'ACTIVE'
 );
