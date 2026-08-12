-- A reviewer may later be deleted. Keep the reviewed outcome and timestamp,
-- while allowing the reviewer identity to be anonymised by the account FK.
alter table private.delivery_partner_applications
  drop constraint delivery_partner_applications_check;
alter table private.delivery_partner_applications
  add constraint delivery_partner_applications_check
  check (
    (status = 'pending'
      and reviewed_at is null
      and reviewed_by is null
      and review_reason is null)
    or
    (status = 'approved'
      and reviewed_at is not null)
    or
    (status = 'rejected'
      and reviewed_at is not null
      and review_reason is not null)
  );

alter table private.merchant_applications
  drop constraint merchant_applications_check;
alter table private.merchant_applications
  add constraint merchant_applications_check
  check (
    (status = 'pending'
      and reviewed_at is null
      and reviewed_by is null)
    or
    (status in ('approved', 'rejected')
      and reviewed_at is not null)
  );

alter table private.controlled_store_compliance
  drop constraint controlled_store_compliance_check1;
alter table private.controlled_store_compliance
  add constraint controlled_store_compliance_check1
  check (
    (status = 'pending'
      and reviewed_at is null
      and reviewed_by is null)
    or
    (status <> 'pending'
      and reviewed_at is not null)
  );
