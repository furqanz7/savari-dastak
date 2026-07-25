-- PostgreSQL requires UPDATE privilege for SELECT ... FOR UPDATE row locks.
-- The append-only trigger still rejects every actual update or delete.
grant update (id) on table private.merchant_order_refund_decisions
  to service_role;
