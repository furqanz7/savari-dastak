-- Access paths used by catalogue snapshots, Admin keyset pagination and the
-- command-center counts. These are additive and preserve all RPC contracts.
create index if not exists skus_admin_keyset_idx
  on dastak_v1.skus (lower(canonical_name), id);

create index if not exists skus_subcategory_status_keyset_idx
  on dastak_v1.skus (subcategory_id, status, lower(canonical_name), id);

create index if not exists merchant_sku_selections_branch_state_sku_idx
  on dastak_v1.merchant_sku_selections (branch_id, state, sku_id);

create index if not exists sku_images_sku_role_status_idx
  on dastak_v1.sku_images (sku_id, role, status);

create index if not exists merchant_applications_status_idx
  on private.merchant_applications (status);

create index if not exists delivery_partner_applications_status_idx
  on private.delivery_partner_applications (status);

create index if not exists account_personas_persona_state_idx
  on private.account_personas (persona, state);

create index if not exists delivery_partner_availability_status_until_idx
  on private.delivery_partner_availability (status, available_until);

create index if not exists orders_status_delivered_at_idx
  on dastak_v1.orders (status, delivered_at);

create index if not exists fulfilments_status_idx
  on dastak_v1.fulfilments (status);

create index if not exists delivery_missions_status_escalation_idx
  on dastak_v1.delivery_missions (status, escalation_state);

create index if not exists operational_pause_controls_active_idx
  on dastak_v1.operational_pause_controls (active)
  where active;

create index if not exists category_types_sort_idx
  on dastak_v1.category_types (sort_order, name, id);

create index if not exists categories_type_sort_idx
  on dastak_v1.categories (category_type_id, sort_order, name, id);

create index if not exists subcategories_category_sort_idx
  on dastak_v1.subcategories (category_id, sort_order, name, id);
