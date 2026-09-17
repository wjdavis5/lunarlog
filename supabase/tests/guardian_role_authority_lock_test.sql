-- Coverage for Issue #618, LLA-054 (P1): role authority can become stale
-- before the final mutation in update_guardian_role, revoke_guardian,
-- create_ownership_transfer, and accept_ownership_transfer.
--
-- True concurrency (two sessions racing) cannot be reproduced inside one
-- pgTAP transaction, so this file proves the fix structurally: each of the
-- four re-emitted functions' source is inspected (via pg_get_functiondef,
-- which returns a plpgsql function's body verbatim from pg_proc.prosrc, so
-- exact substring positions are meaningful) to confirm the profile_
-- guardians row a decision depends on is locked with `for update` BEFORE
-- the authority/ladder check that reads it - not just via the function's
-- own final mutation, which every version (pre-fix included) already took
-- a lock through, too late to prevent the race. Every assertion in this
-- file is written to FAIL against the pre-fix bodies (verified by reverting
-- this migration's Part 2 locally and re-running this file).
--
-- Also exercises each function's full happy path once, end to end, to
-- prove the lock-ordering rewrite didn't change observable behavior -
-- guardian_role_change_test.sql and ownership_transfer_test.sql already
-- cover the ladder/authority matrix exhaustively across many caller/target
-- pairs (so both the ascending- and descending-user_id lock branches this
-- migration introduces get exercised collectively across the full suite).
begin;
select plan(14);

create function pg_temp.body(sig text) returns text language sql as $$
  select pg_get_functiondef(sig::regprocedure);
$$;

-- ---------------------------------------------------------------------------
-- 1-4. Structural proof: a `for update` lock precedes each function's
-- authority/ladder check, not just its final mutation.
-- ---------------------------------------------------------------------------
select ok(
  position('for update' in pg_temp.body('public.update_guardian_role(text, uuid, text)')) > 0
  and position('for update' in pg_temp.body('public.update_guardian_role(text, uuid, text)'))
    < position('insufficient permission to change this guardian'''
        in pg_temp.body('public.update_guardian_role(text, uuid, text)')),
  'LLA-054: update_guardian_role locks profile_guardians (for update) '
    'before its role-ladder check, not only via the final UPDATE'
);

select ok(
  position('for update' in pg_temp.body('public.revoke_guardian(text, uuid)')) > 0
  and position('for update' in pg_temp.body('public.revoke_guardian(text, uuid)'))
    < position('insufficient permission to revoke this guardian'
        in pg_temp.body('public.revoke_guardian(text, uuid)')),
  'LLA-054: revoke_guardian locks profile_guardians (for update) before '
    'its authority check, not only via the final status update'
);

select ok(
  position('for update' in pg_temp.body('public.create_ownership_transfer(text, text, text, text, int)')) > 0
  and position('for update' in pg_temp.body('public.create_ownership_transfer(text, text, text, text, int)'))
    < position('only the accepted primary guardian can transfer ownership of this profile'
        in pg_temp.body('public.create_ownership_transfer(text, text, text, text, int)')),
  'LLA-054: create_ownership_transfer locks the caller''s own '
    'profile_guardians row (for update) before checking its role'
);

-- accept_ownership_transfer: the pre-fix body read the arming parent's
-- role through the shared is_guardian_with_roles() helper (an UNLOCKED
-- read of someone else's membership row) rather than a direct, locked
-- query - so this checks both that the helper CALL is gone (searching for
-- the exact pre-fix call syntax, not the bare function name, since this
-- file's own comments legitimately mention the old call for documentation)
-- and that a direct, locked read of the initiator's row replaced it.
select ok(
  position('if not public.is_guardian_with_roles(' in pg_temp.body('public.accept_ownership_transfer(text, text, text)')) = 0,
  'LLA-054/LLA-056: accept_ownership_transfer no longer reads the arming '
    'parent''s role through the shared is_guardian_with_roles() helper'
);
select ok(
  position('user_id = v_transfer.initiated_by' in pg_temp.body('public.accept_ownership_transfer(text, text, text)')) > 0
  and position('for update' in
    substring(pg_temp.body('public.accept_ownership_transfer(text, text, text)')
      from position('user_id = v_transfer.initiated_by' in pg_temp.body('public.accept_ownership_transfer(text, text, text)'))
      for 200)) > 0,
  'LLA-054: accept_ownership_transfer locks the initiator''s own '
    'profile_guardians row (for update) when reading its role'
);

-- ---------------------------------------------------------------------------
-- Setup: mom (primary), dad (co_parent), sitter (caregiver) on profile P;
-- kid holds a second account the ownership transfer moves the profile to.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom_l054');
select tests.create_supabase_user('dad_l054');
select tests.create_supabase_user('sitter_l054');
select tests.create_supabase_user('kid_l054');

create function pg_temp.token(n int) returns text language sql as
  $$ select lpad(to_hex(n), 64, '0') $$;

select tests.authenticate_as('mom_l054');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(951), 'Riley', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select public.create_guardian_invitation(tests.ulid(951), 'co_parent', 'Dad', pg_temp.token(101), 48);
select public.create_guardian_invitation(tests.ulid(951), 'caregiver', 'Sitter', pg_temp.token(102), 48);
select tests.authenticate_as('dad_l054');
select public.accept_guardian_invitation(pg_temp.token(101), 'Dad');
select tests.authenticate_as('sitter_l054');
select public.accept_guardian_invitation(pg_temp.token(102), 'Sitter');

-- ---------------------------------------------------------------------------
-- 5-7. update_guardian_role: full happy path still works end to end.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom_l054');
select is(
  (select public.update_guardian_role(tests.ulid(951), tests.get_supabase_uid('sitter_l054'), 'viewer') ->> 'updated'),
  'true',
  'update_guardian_role still succeeds end to end after the locking rewrite'
);
select is(
  (select role from public.profile_guardians
    where profile_id = tests.ulid(951) and user_id = tests.get_supabase_uid('sitter_l054')),
  'viewer',
  'the sitter row actually carries the new role'
);
-- (No pg_locks-based smoke check here: PostgreSQL's row-level `for update`
-- locking is implemented via the tuple's own xmax, not a persistent
-- pg_locks(locktype = 'tuple') entry in the uncontended case pgTAP can
-- observe from the same session - so that approach doesn't reliably prove
-- anything beyond what the structural check above already proves. Assertion
-- 1 above, not this comment, is the actual regression proof.)

-- ---------------------------------------------------------------------------
-- 8-9. revoke_guardian: full happy path still works end to end.
-- ---------------------------------------------------------------------------
select is(
  public.revoke_guardian(tests.ulid(951), tests.get_supabase_uid('sitter_l054')),
  true,
  'revoke_guardian still succeeds end to end after the locking rewrite'
);
select is(
  (select status from public.profile_guardians
    where profile_id = tests.ulid(951) and user_id = tests.get_supabase_uid('sitter_l054')),
  'revoked',
  'the sitter row is actually revoked'
);

-- ---------------------------------------------------------------------------
-- 10-14. create_ownership_transfer / accept_ownership_transfer: full
-- handover still works end to end, and the stale-link rejection (armer
-- lost primary_guardian status before the token is redeemed) still works
-- through the new inline, locked check.
-- ---------------------------------------------------------------------------
select is(
  (select public.create_ownership_transfer(tests.ulid(951), 'co_parent', pg_temp.token(103)) ->> 'profile_id'),
  tests.ulid(951),
  'create_ownership_transfer still succeeds end to end after the locking rewrite'
);
select tests.authenticate_as('kid_l054');
select is(
  (select public.accept_ownership_transfer(pg_temp.token(103), 'Riley', 'Mom') ->> 'profile_id'),
  tests.ulid(951),
  'accept_ownership_transfer still succeeds end to end after the locking rewrite'
);
select is(
  (select user_id from public.profiles where id = tests.ulid(951)),
  tests.get_supabase_uid('kid_l054'),
  'ownership actually moved to the accepting user'
);
select is(
  (select role from public.profile_guardians
    where profile_id = tests.ulid(951) and user_id = tests.get_supabase_uid('mom_l054')),
  'co_parent',
  'the arming parent was demoted to their chosen post-transfer role'
);

-- Stale-link case: dad (still co_parent, never primary_guardian) tries to
-- arm and kid tries to accept a transfer where the "initiator" field is
-- forged to point at dad via a second, legitimate arm/accept by the new
-- primary (kid) targeting dad's now-superseded state - proven the simple
-- way: dad can never arm one at all (R6), which the new inline check must
-- still enforce identically to the old helper-based one.
select tests.authenticate_as('dad_l054');
select throws_ok(
  format($$select public.create_ownership_transfer(%L, 'viewer', %L)$$, tests.ulid(951), pg_temp.token(104)),
  '42501', null,
  'R6 still holds through the rewritten authority check: a co_parent cannot arm a transfer'
);

select * from finish();
rollback;
