-- Remove the temporary flat-fee override. V1 restaurant pricing must use the
-- canonical distance/rate-card model once that calculation is wired into the
-- restaurant order command; it must never silently substitute a flat charge.
drop trigger if exists order_price_snapshots_apply_v1_fees on dastak_v1.order_price_snapshots;
drop function if exists dastak_v1.apply_v1_order_fees();
