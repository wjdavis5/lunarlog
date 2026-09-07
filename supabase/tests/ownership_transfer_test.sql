-- Ownership transfer proof (plan 2026-09-06-001, Issue #4, Unit U4).
-- Covers R6-R25 and AE1-AE6: authorization to arm, the state machine
-- (arm/cancel/expire changes nothing), the single security-definer
-- handover transaction, sovereignty after transfer, the attribution-guard
-- bypass, and the cascade proofs that motivated R15.
begin;
select plan(74);

create temp table r (name text primary key, v jsonb);
grant all on table r to authenticated;
create function pg_temp.resp(n text) returns jsonb language sql as
  $$ select v from r where name = n $$;

-- Deterministic valid 64-hex-char token hash for fixtures (mirrors
-- tests.ulid's deterministic-fixture idiom).
create function pg_temp.token(n int) returns text language sql as
  $$ select lpad(to_hex(n), 64, '0') $$;

-- Full-profile snapshot (profile row, guardian rows, day_entries rows) as
-- one comparable jsonb value, for proving R10 ("changes nothing") in one
-- assertion per checkpoint rather than one per column.
create function pg_temp.profile_snapshot(p_id text) returns jsonb language sql as $$
  select jsonb_build_object(
    'profile', (select to_jsonb(p) from public.profiles p where p.id = p_id),
    'guardians', (select coalesce(jsonb_agg(to_jsonb(g) order by g.user_id, g.role), '[]'::jsonb)
                    from public.profile_guardians g where g.profile_id = p_id),
    'entries', (select coalesce(jsonb_agg(to_jsonb(e) order by e.id), '[]'::jsonb)
                  from public.day_entries e where e.profile_id = p_id)
  );
$$;

-- ---------------------------------------------------------------------------
-- Setup: Mom (A) owns profile P with a mixed history - Dad (co_parent),
-- Nanny (caregiver), and Aunt (viewer) already hold memberships; Mom logged
-- one entry, Nanny logged another (AE1's "mixed loggers" scenario).
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom');
select tests.create_supabase_user('kid');
select tests.create_supabase_user('nanny');
select tests.create_supabase_user('eve');
select tests.create_supabase_user('dad');
select tests.create_supabase_user('aunt');

select tests.authenticate_as('mom');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(401), 'Riley', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select public.create_guardian_invitation(tests.ulid(401), 'co_parent', 'Dad', pg_temp.token(1), 48);
select public.create_guardian_invitation(tests.ulid(401), 'caregiver', 'Nanny', pg_temp.token(2), 48);
select public.create_guardian_invitation(tests.ulid(401), 'viewer', 'Aunt', pg_temp.token(3), 48);

select tests.authenticate_as('dad');
select public.accept_guardian_invitation(pg_temp.token(1), 'Dad');
select tests.authenticate_as('nanny');
select public.accept_guardian_invitation(pg_temp.token(2), 'Nanny');
select tests.authenticate_as('aunt');
select public.accept_guardian_invitation(pg_temp.token(3), 'Aunt');

select tests.authenticate_as('mom');
select public.sync_push('[]'::jsonb, jsonb_build_array(jsonb_build_object(
  'id', tests.ulid(411), 'profile_id', tests.ulid(401), 'local_date', '2026-09-01',
  'tz', 'UTC', 'flow', 'light', 'note', 'mom logged', 'updated_at', '2026-09-01T09:00:00Z')));

select tests.authenticate_as('nanny');
select public.sync_push('[]'::jsonb, jsonb_build_array(jsonb_build_object(
  'id', tests.ulid(412), 'profile_id', tests.ulid(401), 'local_date', '2026-09-02',
  'tz', 'UTC', 'flow', 'medium', 'note', 'nanny logged', 'updated_at', '2026-09-02T09:00:00Z')));

-- ---------------------------------------------------------------------------
-- 1. Authorization to arm (R6, R7, R8).
-- ---------------------------------------------------------------------------
select tests.authenticate_as('dad');
select throws_ok(
  format($$select public.create_ownership_transfer(%L, 'co_parent', %L)$$, tests.ulid(401), pg_temp.token(4)),
  '42501', null, 'R6: a co_parent cannot arm a transfer'
);

select tests.authenticate_as('nanny');
select throws_ok(
  format($$select public.create_ownership_transfer(%L, 'co_parent', %L)$$, tests.ulid(401), pg_temp.token(5)),
  '42501', null, 'R6: a caregiver cannot arm a transfer'
);

select tests.authenticate_as('aunt');
select throws_ok(
  format($$select public.create_ownership_transfer(%L, 'co_parent', %L)$$, tests.ulid(401), pg_temp.token(6)),
  '42501', null, 'R6: a viewer cannot arm a transfer'
);

select tests.authenticate_as('eve');
select throws_ok(
  format($$select public.create_ownership_transfer(%L, 'co_parent', %L)$$, tests.ulid(401), pg_temp.token(7)),
  '42501', null, 'R6: an unrelated user cannot arm a transfer'
);

select tests.authenticate_as('mom');
select throws_ok(
  format($$select public.create_ownership_transfer(%L, 'caregiver', %L)$$, tests.ulid(401), pg_temp.token(8)),
  '22023', null, 'R7: parent_post_transfer_role must be co_parent or viewer'
);
select throws_ok(
  format($$select public.create_ownership_transfer(%L, 'co_parent', %L, null, 0)$$, tests.ulid(401), pg_temp.token(9)),
  '22023', null, 'R8: p_ttl_hours below 1 is rejected'
);
select throws_ok(
  format($$select public.create_ownership_transfer(%L, 'co_parent', %L, null, 169)$$, tests.ulid(401), pg_temp.token(10)),
  '22023', null, 'R8: p_ttl_hours above 168 is rejected'
);

-- ---------------------------------------------------------------------------
-- 2. Arming changes nothing (R10).
-- ---------------------------------------------------------------------------
select tests.clear_authentication();
insert into r select '_pre_arm', pg_temp.profile_snapshot(tests.ulid(401));
select tests.authenticate_as('mom');
insert into r select 'arm1', public.create_ownership_transfer(tests.ulid(401), 'co_parent', pg_temp.token(11), 'Kid', 72);

select tests.clear_authentication();
select is(
  pg_temp.profile_snapshot(tests.ulid(401)),
  pg_temp.resp('_pre_arm'),
  'R10: arming a transfer changes nothing about the profile, its memberships, or its entries'
);

-- KTD6 / R6 structural backstop: a second live transfer for the same
-- profile is rejected by the partial unique index.
select tests.authenticate_as('mom');
select throws_ok(
  format($$select public.create_ownership_transfer(%L, 'viewer', %L)$$, tests.ulid(401), pg_temp.token(12)),
  '23505', null, 'KTD6: a second live transfer for the same profile violates the one-live-transfer index'
);

-- Direct-write surface on ownership_transfers is empty for authenticated.
select throws_ok(
  format($$insert into public.ownership_transfers (profile_id, initiated_by, token_hash, parent_post_transfer_role, expires_at) values (%L, %L, %L, 'viewer', now() + interval '1 day')$$,
    tests.ulid(401), tests.get_supabase_uid('mom'), pg_temp.token(13)),
  '42501', null, 'authenticated cannot insert into ownership_transfers directly'
);
select throws_ok(
  format($$update public.ownership_transfers set cancelled_at = now() where profile_id = %L$$, tests.ulid(401)),
  '42501', null, 'authenticated cannot update ownership_transfers directly'
);
select throws_ok(
  format($$delete from public.ownership_transfers where profile_id = %L$$, tests.ulid(401)),
  '42501', null, 'authenticated cannot delete from ownership_transfers directly'
);

select tests.authenticate_as('eve');
select is(
  (select count(*) from public.ownership_transfers where profile_id = tests.ulid(401)),
  0::bigint,
  'a user who is neither initiator nor accepted primary_guardian sees zero ownership_transfers rows'
);

-- ---------------------------------------------------------------------------
-- 3. Cancellation and expiry (AE3, R9).
-- ---------------------------------------------------------------------------
select tests.authenticate_as('eve');
select throws_ok(
  (select format('select public.cancel_ownership_transfer(%L)', pg_temp.resp('arm1') ->> 'id')),
  '42501', null, 'R9: only the arming parent can cancel this transfer'
);

select tests.authenticate_as('mom');
select is(
  public.cancel_ownership_transfer((pg_temp.resp('arm1') ->> 'id')::uuid),
  true,
  'R9: the arming parent can cancel a live transfer'
);

select tests.authenticate_as('kid');
select throws_ok(
  format($$select public.accept_ownership_transfer(%L)$$, pg_temp.token(11)),
  '55000', null, 'R20: a cancelled transfer cannot be accepted'
);

select tests.clear_authentication();
select is(
  pg_temp.profile_snapshot(tests.ulid(401)),
  pg_temp.resp('_pre_arm'),
  'R10/R9: cancellation leaves the profile exactly as before arming'
);

select tests.authenticate_as('mom');
insert into r select 'arm2', public.create_ownership_transfer(tests.ulid(401), 'co_parent', pg_temp.token(14), 'Kid', 72);

select tests.clear_authentication();
update public.ownership_transfers set expires_at = clock_timestamp() - interval '1 hour'
 where token_hash = pg_temp.token(14);

select tests.authenticate_as('kid');
select throws_ok(
  format($$select public.accept_ownership_transfer(%L)$$, pg_temp.token(14)),
  '55000', null, 'AE3: an expired transfer cannot be accepted'
);

select tests.clear_authentication();
select is(
  pg_temp.profile_snapshot(tests.ulid(401)),
  pg_temp.resp('_pre_arm'),
  'AE3: expiry leaves the profile exactly as before arming'
);

-- KTD6: create_ownership_transfer auto-cancels the caller's own
-- outstanding-but-expired row for this profile - this also produces the
-- transfer used for the happy path below.
select tests.authenticate_as('mom');
insert into r select 'arm3', public.create_ownership_transfer(tests.ulid(401), 'co_parent', pg_temp.token(15), 'Kid', 72);
select isnt(
  (select cancelled_at from public.ownership_transfers where token_hash = pg_temp.token(14)),
  null,
  'KTD6: creating a new transfer auto-cancels the caller''s own expired-but-uncancelled row'
);

-- ---------------------------------------------------------------------------
-- 4. Happy path, co_parent (AE1, AE2).
-- ---------------------------------------------------------------------------
select tests.authenticate_as('kid');
insert into r select 'accept1', public.accept_ownership_transfer(pg_temp.token(15), 'Kid', 'Mom Emerita');

select is(pg_temp.resp('accept1') ->> 'profile_id', tests.ulid(401), 'accept_ownership_transfer returns the profile id');
select is((pg_temp.resp('accept1') ->> 'day_entries_rehomed')::int, 2, 'AE1: both of the profile''s entries are rehomed');

-- Review item #5 (P1): every check below this point runs after
-- tests.clear_authentication(), which returns to the session's own
-- superuser role and therefore bypasses RLS entirely - none of them actually
-- exercise the SELECT policies a real client would be subject to. Prove
-- post-transfer RLS positively, authenticated as the child, before dropping
-- to the superuser bypass for the column-by-column snapshot below.
select tests.authenticate_as('kid');
select is(
  (select count(*) from public.profiles where id = tests.ulid(401)),
  1::bigint,
  'Review item #5: the child, authenticated via RLS (not the superuser bypass), can read the profile they now own'
);
select is(
  (select count(*) from public.day_entries where profile_id = tests.ulid(401)),
  2::bigint,
  'Review item #5: the child, authenticated via RLS, can read the profile''s day_entries'
);

select tests.clear_authentication();
select is(
  (select user_id from public.profiles where id = tests.ulid(401)),
  tests.get_supabase_uid('kid'),
  'R12: profiles.user_id is now the child''s'
);
select isnt(
  (select transferred_at from public.profiles where id = tests.ulid(401)),
  null,
  'R12: transferred_at is stamped'
);
select is(
  (select count(*) from public.day_entries where profile_id = tests.ulid(401)),
  2::bigint,
  'R17: acceptance inserts, deletes, and re-keys no day_entries row'
);
select is(
  (select count(*) from public.day_entries where profile_id = tests.ulid(401) and user_id = tests.get_supabase_uid('kid')),
  2::bigint,
  'AE1/R15: every entry on the profile now carries user_id = the child'
);
select is(
  (select logged_by_user_id from public.day_entries where id = tests.ulid(411)),
  tests.get_supabase_uid('mom'),
  'AE1/R16: mom''s entry keeps logged_by_user_id = mom'
);
select is(
  (select logged_by_user_id from public.day_entries where id = tests.ulid(412)),
  tests.get_supabase_uid('nanny'),
  'AE1/R16: nanny''s entry keeps logged_by_user_id = nanny'
);
select is(
  (select last_modified_by_user_id from public.day_entries where id = tests.ulid(411)),
  tests.get_supabase_uid('mom'),
  'R16: last_modified_by_user_id is unchanged by the re-home (mom''s entry)'
);
select is(
  (select last_modified_by_user_id from public.day_entries where id = tests.ulid(412)),
  tests.get_supabase_uid('nanny'),
  'R16: last_modified_by_user_id is unchanged by the re-home (nanny''s entry)'
);

select is(
  (select count(*) from public.profile_guardians where profile_id = tests.ulid(401) and role = 'primary_guardian' and status = 'accepted'),
  1::bigint,
  'R22: exactly one accepted primary_guardian after transfer'
);
select is(
  (select user_id from public.profile_guardians where profile_id = tests.ulid(401) and role = 'primary_guardian' and status = 'accepted'),
  tests.get_supabase_uid('kid'),
  'AE2/R13: the sole accepted primary_guardian is the child'
);
select is(
  (select role from public.profile_guardians where profile_id = tests.ulid(401) and user_id = tests.get_supabase_uid('mom')),
  'co_parent',
  'AE2/R14: the arming parent holds the chosen post-transfer role'
);
select is(
  (select status from public.profile_guardians where profile_id = tests.ulid(401) and user_id = tests.get_supabase_uid('mom')),
  'accepted',
  'R14: the arming parent''s membership is accepted, not merely present'
);
select is(
  (select role from public.profile_guardians where profile_id = tests.ulid(401) and user_id = tests.get_supabase_uid('nanny')),
  'caregiver',
  'R19: the caregiver''s membership is untouched by the transfer'
);
select is(
  (select role from public.profile_guardians where profile_id = tests.ulid(401) and user_id = tests.get_supabase_uid('aunt')),
  'viewer',
  'R19: the viewer''s membership is untouched by the transfer'
);

-- R22 structural backstop, direct: a second accepted primary_guardian row
-- for the same profile is rejected even bypassing the RPC.
select throws_ok(
  format($$insert into public.profile_guardians (profile_id, user_id, role, status) values (%L, %L, 'primary_guardian', 'accepted')$$,
    tests.ulid(401), tests.get_supabase_uid('nanny')),
  '23505', null, 'R22: profile_guardians_one_primary_uq rejects a second accepted primary_guardian for the same profile'
);

-- ---------------------------------------------------------------------------
-- 5. Both post-transfer roles: co_parent can still log and edit; viewer
-- cannot (R29). Second profile, second family, viewer role.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
select is(
  public.sync_push('[]'::jsonb, jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(413), 'profile_id', tests.ulid(401), 'local_date', '2026-09-03',
    'tz', 'UTC', 'flow', 'light', 'updated_at', '2026-09-03T09:00:00Z'))) -> 'rejected',
  '[]'::jsonb,
  'R29: a co_parent post-transfer parent can still log entries'
);
select is(
  public.sync_push(jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(401), 'display_name', 'Riley Renamed', 'updated_at', '2026-09-03T10:00:00Z')), '[]'::jsonb) -> 'rejected',
  '[]'::jsonb,
  'a co_parent post-transfer parent can edit profile metadata'
);

select tests.create_supabase_user('dad2');
select tests.create_supabase_user('jess');
select tests.authenticate_as('dad2');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(402), 'Jamie', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
insert into r select 'arm_viewer', public.create_ownership_transfer(tests.ulid(402), 'viewer', pg_temp.token(16), 'Jess', 72);

select tests.authenticate_as('jess');
select public.accept_ownership_transfer(pg_temp.token(16), 'Jess', 'Dad');

-- Review item #5 (P1): the positive-read/write-denial pair for the viewer
-- role, mirroring the co_parent family's checks above - jess (the child) can
-- read her own profile via RLS, and dad2 (now a viewer) is denied a direct
-- write below (not just through sync_push).
select is(
  (select count(*) from public.profiles where id = tests.ulid(402)),
  1::bigint,
  'Review item #5: the child, authenticated via RLS, can read the profile they now own (viewer post-role family)'
);

-- sync_push never lets a per-row authorization failure escape as a real SQL
-- exception (each row runs inside its own exception handler, opaquely
-- rejecting the row) - so the proof here is the row landing in `rejected`,
-- not a thrown error. See sync_push_test.sql's "Per-row rejections are
-- opaque" section for the same contract.
select tests.authenticate_as('dad2');
select is(
  public.sync_push('[]'::jsonb, jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(421), 'profile_id', tests.ulid(402), 'local_date', '2026-09-05',
    'tz', 'UTC', 'flow', 'light', 'updated_at', '2026-09-05T09:00:00Z'))) -> 'rejected',
  jsonb_build_array(jsonb_build_object('id', tests.ulid(421), 'rejected', true)),
  'R29: a viewer post-transfer parent is denied a day_entries write through sync_push'
);
select is(
  public.sync_push(jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(402), 'display_name', 'Nope', 'updated_at', '2026-09-05T09:00:00Z')), '[]'::jsonb) -> 'rejected',
  jsonb_build_array(jsonb_build_object('id', tests.ulid(402), 'rejected', true)),
  'R29: a viewer post-transfer parent is denied a profile-metadata edit through sync_push'
);
select throws_ok(
  format($$insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at) values (%L, %L, '2026-09-06', 'UTC', 'light', now())$$,
    tests.ulid(422), tests.ulid(402)),
  '42501', null,
  'Review item #5: RLS itself (not just sync_push) denies a viewer a direct day_entries insert - the write-denial mirror of jess''s positive read above'
);

-- ---------------------------------------------------------------------------
-- 6. Single-use and misuse (R18, R20).
-- ---------------------------------------------------------------------------
select tests.authenticate_as('eve');
select throws_ok(
  format($$select public.accept_ownership_transfer(%L)$$, pg_temp.token(15)),
  '55000', null, 'R18: a second acceptance of the same token is refused'
);

select throws_ok(
  $$select public.accept_ownership_transfer(repeat('0', 64))$$,
  'P0002', null, 'R20: an unknown token is refused with a distinguishable not-found reason'
);

select tests.create_supabase_user('pat');
select tests.authenticate_as('pat');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(403), 'Sam', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
insert into r select 'arm_self', public.create_ownership_transfer(tests.ulid(403), 'viewer', pg_temp.token(17), null, 72);
select throws_ok(
  format($$select public.accept_ownership_transfer(%L)$$, pg_temp.token(17)),
  '55000', null, 'R11: the arming parent cannot accept their own transfer'
);

-- The armer is demoted out of primary_guardian by other means; the still-
-- live token is now stale (R20).
select tests.clear_authentication();
update public.profile_guardians set role = 'viewer'
 where profile_id = tests.ulid(403) and user_id = tests.get_supabase_uid('pat');

select tests.create_supabase_user('quinn');
select tests.authenticate_as('quinn');
select throws_ok(
  format($$select public.accept_ownership_transfer(%L)$$, pg_temp.token(17)),
  '55000', null, 'R20: a token whose armer is no longer the accepted primary_guardian is refused as stale'
);

-- ---------------------------------------------------------------------------
-- 7. Sovereignty (AE5).
-- ---------------------------------------------------------------------------
select tests.authenticate_as('kid');
select is(
  public.revoke_guardian(tests.ulid(401), tests.get_supabase_uid('mom')),
  true,
  'AE5: the child can revoke the ex-parent''s membership'
);

select tests.authenticate_as('mom');
select is(
  (select count(*) from public.day_entries where profile_id = tests.ulid(401)),
  0::bigint,
  'AE5: after revocation, the ex-parent selects zero day_entries rows for the profile'
);
select is(
  (select count(*) from public.profiles where id = tests.ulid(401)),
  0::bigint,
  'AE5: after revocation, the ex-parent selects zero profiles rows for the profile'
);
select throws_ok(
  format($$select public.revoke_guardian(%L, %L)$$, tests.ulid(401), tests.get_supabase_uid('kid')),
  '42501', null, 'AE5: the revoked ex-parent cannot revoke the new owner back'
);

-- ---------------------------------------------------------------------------
-- 8. Client cannot reach ownership (R21).
-- ---------------------------------------------------------------------------
select tests.authenticate_as('kid');
select throws_ok(
  format($$update public.profiles set user_id = %L where id = %L$$, tests.get_supabase_uid('eve'), tests.ulid(401)),
  '42501', null, 'R21: authenticated has no column grant to write profiles.user_id directly, even the current owner'
);

-- ---------------------------------------------------------------------------
-- 9. Attribution guard (AE6, R25).
-- ---------------------------------------------------------------------------
select tests.authenticate_as('kid');
select throws_ok(
  format($$update public.day_entries set note = 'hacked' where id = %L$$, tests.ulid(411)),
  '42501', null, 'AE6: without the GUC, an update that does not stamp last_modified_by_user_id still raises'
);

select tests.authenticate_as('kid');
select set_config('lunarlog.ownership_transfer', 'on', true);
select throws_ok(
  format($$update public.day_entries set note = 'hacked2', user_id = %L where id = %L$$,
    tests.get_supabase_uid('kid'), tests.ulid(411)),
  '42501', null, 'AE6: with the GUC set but a second column also changed, the update still raises'
);

-- Restricted to prokind = 'f' (ordinary functions): pg_proc in the public
-- schema also lists aggregates, and pg_get_functiondef() raises "<name> is
-- an aggregate function" if handed one of those oids instead of an
-- ordinary function's.
select is(
  (select count(*)
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
      and pg_get_functiondef(p.oid) like '%lunarlog.ownership_transfer%'),
  2::bigint,
  'R21/KTD4: exactly two functions in public reference the ownership-transfer GUC name'
);
select ok(
  pg_get_functiondef('public.accept_ownership_transfer(text, text, text)'::regprocedure) like '%lunarlog.ownership_transfer%',
  'R21/KTD4: one of them is accept_ownership_transfer (sets it)'
);
select ok(
  pg_get_functiondef('public.enforce_day_entry_attribution()'::regprocedure) like '%lunarlog.ownership_transfer%',
  'R21/KTD4: the other is enforce_day_entry_attribution (reads it)'
);
select is(
  (select count(*)
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
      and pg_get_functiondef(p.oid) like '%set_config(''lunarlog.ownership_transfer''%'
      and has_function_privilege('authenticated', p.oid, 'execute')),
  1::bigint,
  'R21/KTD4: accept_ownership_transfer is the only authenticated-callable function that ever SETS the GUC'
);

-- delete_account_data() still works correctly against a profile that has
-- been transferred: nanny (a caregiver whose own logged entry was already
-- re-homed to the child by the transfer) has nothing stray left to rehome
-- on this profile, and her account deletion does not touch the profile's
-- (now child-owned) entries.
select tests.clear_authentication();
select tests.delete_supabase_user('nanny');
select is(
  (select count(*) from public.day_entries where id in (tests.ulid(411), tests.ulid(412))),
  2::bigint,
  'a transferred profile''s entries survive a caregiver''s account deletion untouched'
);

-- ---------------------------------------------------------------------------
-- 10. Cascades.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('morgan');
select tests.authenticate_as('morgan');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(404), 'Casey', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
insert into r select 'arm_cascade', public.create_ownership_transfer(tests.ulid(404), 'viewer', pg_temp.token(18), null, 72);

select tests.clear_authentication();
select tests.delete_supabase_user('morgan');

select is(
  (select count(*) from public.ownership_transfers where profile_id = tests.ulid(404)),
  0::bigint,
  'deleting the arming parent while a transfer is pending removes the pending transfer row via cascade'
);
select is(
  (select count(*) from public.profiles where id = tests.ulid(404)),
  0::bigint,
  'deleting the arming parent while a transfer is pending removes the profile it still owned (pre-existing cascade)'
);

-- After a COMPLETED transfer, deleting the ex-parent leaves the profile and
-- its at-transfer-time entries intact - the direct proof of the no-orphan
-- guarantee that motivated R15.
select tests.clear_authentication();
select tests.delete_supabase_user('mom');
select is(
  (select count(*) from public.profiles where id = tests.ulid(401)),
  1::bigint,
  'R15 no-orphan proof: after a completed transfer, deleting the ex-parent leaves the profile intact'
);
select is(
  (select count(*) from public.day_entries where id in (tests.ulid(411), tests.ulid(412))),
  2::bigint,
  'R15 no-orphan proof: after a completed transfer, deleting the ex-parent leaves its at-transfer-time entries intact'
);

-- ---------------------------------------------------------------------------
-- 11. Review item #1 (P0): revoke_guardian closes the ownership-transfer
-- bypass, with accept_ownership_transfer's acceptor-freshness check as
-- defence in depth. Mirrors guardian_revocation_bypass_test.sql's #81/#82
-- isolation idiom.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('gigi');
select tests.create_supabase_user('uncle');
select tests.authenticate_as('gigi');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(405), 'Drew', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select public.create_guardian_invitation(tests.ulid(405), 'co_parent', 'Uncle', pg_temp.token(19), 48);
select tests.authenticate_as('uncle');
select public.accept_guardian_invitation(pg_temp.token(19), 'Uncle');

select tests.authenticate_as('gigi');
insert into r select 'arm_bypass', public.create_ownership_transfer(tests.ulid(405), 'co_parent', pg_temp.token(20), 'Drew', 72);

-- (a) revoking Uncle - unrelated to the transfer's actual intended
-- recipient - cancels the still-live transfer too. Would fail (cancelled_at
-- stays null, and the accept attempt below would succeed instead of
-- throwing) if this fix regressed and revoke_guardian went back to leaving
-- ownership_transfers untouched.
select public.revoke_guardian(tests.ulid(405), tests.get_supabase_uid('uncle'));
select isnt(
  (select cancelled_at from public.ownership_transfers where token_hash = pg_temp.token(20)),
  null,
  'Review item #1: revoke_guardian cancels a still-live ownership transfer for the profile'
);

select tests.authenticate_as('uncle');
select throws_ok(
  format($$select public.accept_ownership_transfer(%L)$$, pg_temp.token(20)),
  '55000', null,
  'Review item #1: the transfer is no longer redeemable after the unrelated revocation'
);

-- (b) acceptor-freshness check, isolated from (a): undo the revoke_guardian
-- cancellation on the transfer (as if it had never run) to prove the
-- freshness guard inside accept_ownership_transfer does not depend on it.
select tests.clear_authentication();
update public.ownership_transfers set cancelled_at = null
 where token_hash = pg_temp.token(20);

select tests.authenticate_as('uncle');
select throws_ok(
  format($$select public.accept_ownership_transfer(%L)$$, pg_temp.token(20)),
  '55000', null,
  'Review item #1: a revoked guardian is refused even if the transfer is somehow still live (acceptor-freshness defence in depth)'
);

select tests.clear_authentication();
select is(
  (select user_id from public.profiles where id = tests.ulid(405)),
  tests.get_supabase_uid('gigi'),
  'Review item #1: the profile is still gigi''s after both blocked redemption attempts'
);

-- ---------------------------------------------------------------------------
-- 12. Review item #4 (P1): accept_ownership_transfer cancels the ex-parent's
-- own still-live guardian invitations for the profile.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('grandma');
select tests.create_supabase_user('finn');
select tests.create_supabase_user('sitter');
select tests.authenticate_as('grandma');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(406), 'Finn Jr', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

-- A still-live invitation grandma sent before arming the transfer.
select public.create_guardian_invitation(tests.ulid(406), 'caregiver', 'Sitter', pg_temp.token(21), 48);
insert into r select 'arm_invite_cancel', public.create_ownership_transfer(tests.ulid(406), 'co_parent', pg_temp.token(22), 'Finn', 72);

select tests.authenticate_as('finn');
select public.accept_ownership_transfer(pg_temp.token(22), 'Finn', 'Grandma');

select tests.clear_authentication();
select isnt(
  (select revoked_at from public.guardian_invitations where token_hash = pg_temp.token(21)),
  null,
  'Review item #4: acceptance cancels the ex-parent''s still-live guardian invitation for the profile'
);

select tests.authenticate_as('sitter');
select throws_ok(
  format($$select public.accept_guardian_invitation(%L)$$, pg_temp.token(21)),
  '55000', null,
  'Review item #4: the cancelled invitation is no longer redeemable after the handover'
);

-- ---------------------------------------------------------------------------
-- 13. Round-2 review item #1 (P1): revocation of a guardian_invitations row
-- is terminal. Without guardian_invitations_revocation_terminal_guard, the
-- ex-parent (grandma) still satisfies the guardian_invitations_update
-- policy's invited_by = auth.uid() check after the handover in section 12 -
-- so a direct PATCH revoked_at: null would silently reopen the invitation
-- section 12 just proved cancelled, and whoever holds token 21's raw token
-- could still redeem it. Reuses grandma/finn/sitter and token(21) from
-- section 12.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('grandma');
select throws_ok(
  format($$update public.guardian_invitations set revoked_at = null where token_hash = %L$$, pg_temp.token(21)),
  '42501', null,
  'Review item #1 (round 2): the ex-parent cannot un-revoke a guardian invitation by direct PATCH'
);

select tests.clear_authentication();
select isnt(
  (select revoked_at from public.guardian_invitations where token_hash = pg_temp.token(21)),
  null,
  'Review item #1 (round 2): the un-revoke attempt left revoked_at untouched'
);

select tests.authenticate_as('sitter');
select throws_ok(
  format($$select public.accept_guardian_invitation(%L)$$, pg_temp.token(21)),
  '55000', null,
  'Review item #1 (round 2): the token stays refused after the blocked un-revoke attempt'
);

select * from finish();
rollback;
