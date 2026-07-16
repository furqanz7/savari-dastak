alter policy accounts_select_self on public.accounts
using (id = (select auth.uid()));
