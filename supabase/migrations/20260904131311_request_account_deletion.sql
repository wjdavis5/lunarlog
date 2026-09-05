-- request_account_deletion: the privileged account-deletion cascade (U1; R14).
--
-- Contract
--   request_account_deletion() returns void
--
--   Deletes every server row the caller owns (day_entries, profiles,
--   settings) and then the caller's auth.users row, which cascades any
--   remainder through the `on delete cascade` foreign keys. Requires an
--   authenticated session; without one the whole call raises
--   (insufficient_privilege) and removes nothing.
--
--   Why security definer: the client SDK cannot delete auth users and RLS
--   (forced) bars touching another owner's rows, so the cascade runs with
--   the function owner's privileges. The function is a deliberate,
--   reviewed exception to the security-invoker-only precedent (see
--   sync_push): it is locked down three ways — `set search_path = ''`,
--   EXECUTE revoked from public and anon (authenticated only), and an
--   explicit `auth.uid()` null check that raises before any delete. The
--   only rows it can ever touch are the caller's own (`user_id = uid`),
--   plus the caller's own auth.users row.

create or replace function public.request_account_deletion()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'request_account_deletion requires an authenticated user'
      using errcode = 'insufficient_privilege';
  end if;

  delete from public.day_entries where user_id = v_uid;
  delete from public.profiles where user_id = v_uid;
  delete from public.settings where user_id = v_uid;
  delete from auth.users where id = v_uid;
end;
$$;

comment on function public.request_account_deletion() is
  'Account deletion cascade (U1; R14): removes the caller''s day_entries, profiles, and settings rows, then the caller''s auth.users row. Authenticated only.';

revoke execute on function public.request_account_deletion() from public, anon;
grant execute on function public.request_account_deletion() to authenticated;
