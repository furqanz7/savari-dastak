-- PostgREST requires normal SQL table privileges in addition to RLS.
-- Keep anonymous clients blocked, but restore table access for signed-in
-- users so existing RLS policies can authorize row-level operations.

grant usage on schema public to authenticated;

grant select, insert, update, delete on table
  public.driver_locations,
  public.driver_onboarding,
  public.driver_wallet_transactions,
  public.payment_methods,
  public.profiles,
  public.ride_history,
  public.rides,
  public.user_onboarding,
  public.users
to authenticated;

revoke select, insert, update, delete on table
  public.driver_locations,
  public.driver_onboarding,
  public.driver_wallet_transactions,
  public.payment_methods,
  public.profiles,
  public.ride_history,
  public.rides,
  public.user_onboarding,
  public.users
from anon;
