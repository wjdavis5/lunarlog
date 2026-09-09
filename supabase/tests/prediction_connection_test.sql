-- Coverage for Issue #151: the prediction-only connection --
-- schema shape (RLS, policies, column-scoped grants, the one-connection
-- cap index, both triggers), the create/accept/revoke RPC lifecycle
-- (primary-guardian-only arming, Pregnancy-mode refusal at create AND
-- accept, the issue #373 minor-profile refusal at create AND accept
-- (section 6b - the fixture profiles are adults so the rest of the suite
-- still exercises the happy paths), stale-code refusal, guardian-reciprocal refusal, the
-- one-directional pair rule, the one-active-connection cap, terminal
-- idempotency), the projection boundary (derived-only payload validation,
-- recipient read path, guardian preview, enumeration-safe null), the
-- residual-access guarantees (revocation deletes the snapshot in the same
-- transaction; a guardian revocation kills the connection too; Realtime
-- publication revert), and the recipient's total isolation from raw data
-- (no profile_guardians row, no day_entries/profiles visibility, no
-- direct write on either new table, token_hash unreadable).
-- Fixture style: ownership_transfer_test.sql /
-- guardian_invitation_revocation_test.sql.
begin;
select plan(102);

-- One captured RPC result per name (the ownership_transfer_test.sql pattern):
-- an RPC that both returns a value and mutates state must be called once.
create temp table r (name text primary key, v jsonb);
grant all on table r to authenticated;

select tests.create_supabase_user('mom');
select tests.create_supabase_user('dad');
select tests.create_supabase_user('sitter');
select tests.create_supabase_user('doctor');
select tests.create_supabase_user('stranger');
select tests.create_supabase_user('nanny');

-- Deterministic 64-char hex "hashes" (the plaintext never exists
-- server-side), exactly like ownership_transfer_test.sql's pg_temp.token.
create function pg_temp.token(n int) returns text language sql as
  $$ select lpad(to_hex(n), 64, '0') $$;

-- Owner-context helpers: resolve a connection row by its hash without
-- routing the hash through an authenticated grant (same plumbing as
-- tests.invitation_id_by_hash).
create function pg_temp.conn_state(p_hash text) returns jsonb
language sql security definer set search_path = ''
as $$
  select jsonb_build_object(
    'accepted_at', accepted_at,
    'revoked_at', revoked_at,
    'recipient', recipient_user_id)
    from public.prediction_connections where token_hash = p_hash
$$;

create function pg_temp.conn_revoked(p_hash text) returns boolean
language sql security definer set search_path = ''
as $$ select revoked_at is not null from public.prediction_connections where token_hash = p_hash $$;

create function pg_temp.proj_count() returns bigint
language sql security definer set search_path = ''
as $$ select count(*) from public.prediction_projections $$;


-- ---------------------------------------------------------------------------
-- Setup: Profile P1 = Mom's, with accepted co_parent (dad), caregiver
-- (sitter), viewer (doctor); the profiles-insert trigger backfills Mom as
-- accepted primary_guardian. Profile P2 = stranger's own. One day entry on
-- P1: the raw row the recipient must never see.
-- ---------------------------------------------------------------------------
-- Both fixture profiles are ADULTS (issue #373): a minor's profile can no
-- longer be shared at all, so a minor fixture would refuse every create
-- below. Section 6b flips the flag on and off to prove that gate.
select tests.authenticate_as('mom');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(901), 'Riley', false, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select public.create_guardian_invitation(
  tests.ulid(901), 'co_parent', 'Dad', pg_temp.token(101), 48);
select public.create_guardian_invitation(
  tests.ulid(901), 'caregiver', 'Sitter', pg_temp.token(102), 48);
select public.create_guardian_invitation(
  tests.ulid(901), 'viewer', 'Doctor', pg_temp.token(103), 48);

select tests.authenticate_as('dad');
select public.accept_guardian_invitation(pg_temp.token(101), 'Dad');
select tests.authenticate_as('sitter');
select public.accept_guardian_invitation(pg_temp.token(102), 'Sitter');
select tests.authenticate_as('doctor');
select public.accept_guardian_invitation(pg_temp.token(103), 'Doctor');

select tests.authenticate_as('stranger');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(902), 'Other Adult', false, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select tests.authenticate_as('mom');
insert into public.day_entries
  (id, user_id, profile_id, local_date, tz, flow, tags, note, updated_at)
values (
  tests.ulid(905),
  tests.get_supabase_uid('mom'), tests.ulid(901), '2026-09-01', 'America/New_York',
  'medium', '["cramps"]'::jsonb, 'a private note',
  '2026-09-01T00:00:00Z');

-- ---------------------------------------------------------------------------
-- 1. Schema shape: RLS, policies, grants, indexes, triggers.
-- ---------------------------------------------------------------------------
select tests.rls_enabled('public', 'prediction_connections');
select tests.rls_forced('public', 'prediction_connections');
select tests.rls_enabled('public', 'prediction_projections');
select tests.rls_forced('public', 'prediction_projections');

select is(
  (select count(*)::integer from pg_policies
    where schemaname = 'public' and tablename = 'prediction_connections'),
  1, 'prediction_connections carries exactly one policy (select)');
select is(
  (select count(*)::integer from pg_policies
    where schemaname = 'public' and tablename = 'prediction_connections'
      and cmd <> 'SELECT'),
  0, 'prediction_connections has no INSERT/UPDATE/DELETE policy');
select is(
  (select count(*)::integer from pg_policies
    where schemaname = 'public' and tablename = 'prediction_projections'),
  0, 'prediction_projections carries no policy at all (notification_outbox posture)');

select is(
  (select has_table_privilege('authenticated', 'public.prediction_connections', 'SELECT')),
  false, 'authenticated holds no table-wide SELECT (token_hash column-excluded, #114/#242 pattern)');
select is(
  (select has_column_privilege('authenticated', 'public.prediction_connections', 'token_hash', 'SELECT')),
  false, 'token_hash is unreadable by authenticated');
select is(
  (select has_column_privilege('authenticated', 'public.prediction_connections', 'id', 'SELECT')),
  true, 'non-secret columns remain readable by authenticated');
select is(
  (select has_table_privilege('authenticated', 'public.prediction_connections', 'INSERT')),
  false, 'authenticated holds no INSERT grant (all mutation via SECURITY DEFINER RPCs)');
select is(
  (select has_table_privilege('authenticated', 'public.prediction_connections', 'UPDATE')),
  false, 'authenticated holds no UPDATE grant');
select is(
  (select has_table_privilege('authenticated', 'public.prediction_connections', 'DELETE')),
  false, 'authenticated holds no DELETE grant');
select is(
  (select has_table_privilege('anon', 'public.prediction_connections', 'SELECT')),
  false, 'anon holds nothing on prediction_connections');
select is(
  (select has_table_privilege('authenticated', 'public.prediction_projections', 'SELECT')),
  false, 'authenticated holds no SELECT on prediction_projections (RPC-only reads)');
select is(
  (select has_table_privilege('anon', 'public.prediction_projections', 'SELECT')),
  false, 'anon holds nothing on prediction_projections');

select is(
  (select count(*)::integer from pg_indexes
    where schemaname = 'public' and tablename = 'prediction_connections'
      and indexname = 'prediction_connections_one_live_uq'),
  1, 'the one-connection cap index exists');
select is(
  (select count(*)::integer from pg_trigger t
     join pg_class c on c.oid = t.tgrelid
    where c.relname = 'prediction_connections'
      and t.tgname = 'prediction_connections_projection_gc_trg'),
  1, 'the projection GC trigger is wired to prediction_connections');
select is(
  (select count(*)::integer from pg_trigger t
     join pg_class c on c.oid = t.tgrelid
    where c.relname = 'prediction_projections'
      and t.tgname = 'prediction_projections_payload_guard'),
  1, 'the payload allowlist guard is wired to prediction_projections');

-- ---------------------------------------------------------------------------
-- 2. create_prediction_connection: authorization and the cap.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
select ok(
  public.create_prediction_connection(tests.ulid(901), pg_temp.token(201), 'Partner', 72)
    ->> 'profile_id' = tests.ulid(901),
  'the primary guardian can arm a prediction-only invite');
select is(
  pg_temp.conn_state(pg_temp.token(201)) ->> 'accepted_at',
  null, 'the armed invite is pending (not accepted)');

select tests.authenticate_as('dad');
select throws_ok(
  format($$select public.create_prediction_connection(%L, %L, null, 72)$$,
    tests.ulid(901), pg_temp.token(202)),
  '42501', 'only the accepted primary guardian can share predictions for this profile',
  'a co_parent cannot arm a prediction-only invite');
select tests.authenticate_as('nanny');
select throws_ok(
  format($$select public.create_prediction_connection(%L, %L, null, 72)$$,
    tests.ulid(901), pg_temp.token(203)),
  '42501', 'only the accepted primary guardian can share predictions for this profile',
  'a non-guardian cannot arm a prediction-only invite');

select tests.authenticate_as('mom');
select throws_ok(
  format($$select public.create_prediction_connection(%L, 'not-a-hash', null, 72)$$,
    tests.ulid(901)),
  '22023', 'token_hash must be a 64-character hex string',
  'create refuses a non-hex token hash');
select throws_ok(
  format($$select public.create_prediction_connection(%L, %L, null, 0)$$,
    tests.ulid(901), pg_temp.token(204)),
  '22023', 'p_ttl_hours must be between 1 and 168',
  'create refuses a TTL below 1 hour');
select throws_ok(
  format($$select public.create_prediction_connection(%L, %L, null, 169)$$,
    tests.ulid(901), pg_temp.token(205)),
  '22023', 'p_ttl_hours must be between 1 and 168',
  'create refuses a TTL above 168 hours');

select throws_ok(
  format($$select public.create_prediction_connection(%L, %L, null, 72)$$,
    tests.ulid(901), pg_temp.token(206)),
  '23505', 'this profile already has a prediction-only connection or pending invite',
  'a second live invite while one is pending is refused server-side (the cap)');

select tests.authenticate_as('nanny');
select is(
  (select count(*) from public.prediction_connections
    where profile_id = tests.ulid(901)),
  0::bigint, 'a pending invite is invisible to unrelated accounts');

-- ---------------------------------------------------------------------------
-- 3. Publishing before acceptance stores nothing.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
select public.upsert_prediction_projection(
  tests.ulid(901),
  '{"generated_at":"2026-09-07","period_days":["2026-09-10"]}'::jsonb);
select is(
  pg_temp.proj_count(),
  0::bigint, 'a publish with no active connection stores nothing');

-- ---------------------------------------------------------------------------
-- 4. accept_prediction_connection: guards and the happy path.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('nanny');
select throws_ok(
  format($$select public.accept_prediction_connection(%L)$$, pg_temp.token(999)),
  'P0002', 'prediction connection not found',
  'an unknown hash is refused with the not-found message');
select throws_ok(
  'select public.accept_prediction_connection(''not-a-hash'')',
  '22023', 'token_hash must be a 64-character hex string',
  'accept refuses a non-hex token hash');

select tests.authenticate_as('mom');
select throws_ok(
  format($$select public.accept_prediction_connection(%L)$$, pg_temp.token(201)),
  '55000', 'the sharer cannot accept their own prediction connection',
  'the sharer cannot accept their own invite');

-- An expired invite cannot be redeemed, and lapsing does not wedge the
-- seat: the next create cancels it (cancel-then-create).
select tests.clear_authentication();
update public.prediction_connections
   set expires_at = clock_timestamp() - interval '1 hour'
 where token_hash = pg_temp.token(201);

select tests.authenticate_as('nanny');
select throws_ok(
  format($$select public.accept_prediction_connection(%L)$$, pg_temp.token(201)),
  '55000', 'prediction connection has expired',
  'an expired invite cannot be accepted');

select tests.authenticate_as('mom');
select ok(
  public.create_prediction_connection(tests.ulid(901), pg_temp.token(207), 'Partner', 72)
    is not null,
  'an outstanding-but-expired invite does not wedge re-arming');
select is(
  pg_temp.conn_revoked(pg_temp.token(201)),
  true, 'the expired invite was cancelled by the re-arm');

select tests.authenticate_as('sitter');
select throws_ok(
  format($$select public.accept_prediction_connection(%L)$$, pg_temp.token(207)),
  '55000', 'you are already a guardian of this profile',
  'an accepted guardian cannot redeem a prediction-only invite');

select tests.authenticate_as('stranger');
insert into r select 'accept1', public.accept_prediction_connection(pg_temp.token(207));
select is(
  (select v ->> 'profile_id' from r where name = 'accept1'),
  tests.ulid(901),
  'the recipient can redeem the invite');
select is(
  (select v ->> 'profile_name' from r where name = 'accept1'),
  'Riley',
  'acceptance returns the profile display name for the recipient UI');
select throws_ok(
  format($$select public.accept_prediction_connection(%L)$$, pg_temp.token(207)),
  '55000', 'prediction connection was already accepted',
  'the invite is single-use');
select is(
  pg_temp.conn_state(pg_temp.token(207)) ->> 'recipient',
  tests.get_supabase_uid('stranger')::text,
  'the accepted connection names its recipient');

-- THE boundary (issue #151 AC): the recipient is not a guardian and got no
-- membership row of any kind.
select is(
  (select count(*) from public.profile_guardians
    where profile_id = tests.ulid(901)
      and user_id = tests.get_supabase_uid('stranger')),
  0::bigint, 'the recipient holds no profile_guardians row');
select is(
  public.is_profile_guardian(tests.ulid(901), tests.get_supabase_uid('stranger')),
  false, 'is_profile_guardian is false for the recipient');

-- The active connection blocks any further invite (the cap, enforced
-- server-side while ACTIVE -- not only while pending).
select tests.authenticate_as('mom');
select throws_ok(
  format($$select public.create_prediction_connection(%L, %L, null, 72)$$,
    tests.ulid(901), pg_temp.token(208)),
  '23505', 'this profile already has a prediction-only connection or pending invite',
  'a second invite while a connection is active is refused (the cap)');

-- One-directional: the recipient cannot simultaneously share back to the
-- sharer ("a source of one back").
select tests.authenticate_as('stranger');
insert into r select 'p2_arm', public.create_prediction_connection(tests.ulid(902), pg_temp.token(210), 'Mom', 72);
select ok(
  (select v is not null from r where name = 'p2_arm'),
  'the recipient can arm their own share of their own profile');
select tests.authenticate_as('mom');
select throws_ok(
  format($$select public.accept_prediction_connection(%L)$$, pg_temp.token(210)),
  '55000', 'cannot share and view predictions with the same person at the same time',
  'mom cannot accept a share back from her own recipient (one-directional)');

-- The recipient sees exactly their own live connection and nothing else.
select tests.authenticate_as('stranger');
select is(
  (select count(*) from public.prediction_connections
    where profile_id = tests.ulid(901)),
  1::bigint, 'the recipient sees exactly their one live connection');

-- No direct-write surface for a forged acceptance.
select tests.authenticate_as('nanny');
select throws_ok(
  format($$insert into public.prediction_connections
    (profile_id, owner_user_id, token_hash, expires_at)
    values (%L, %L, %L, now() + interval '1 day')$$,
    tests.ulid(901), tests.get_supabase_uid('mom'), pg_temp.token(211)),
  '42501', null,
  'authenticated cannot insert into prediction_connections (no forged acceptances)');
select throws_ok(
  format($$update public.prediction_connections set accepted_at = now()
    where profile_id = %L$$, tests.ulid(901)),
  '42501', null,
  'authenticated cannot update prediction_connections directly');
select throws_ok(
  format($$delete from public.prediction_connections where profile_id = %L$$,
    tests.ulid(901)),
  '42501', null,
  'authenticated cannot delete from prediction_connections directly');
select throws_ok(
  format($$insert into public.prediction_projections
    (profile_id, projection, published_by)
    values (%L, '{"generated_at":"2026-09-07"}'::jsonb, %L)$$,
    tests.ulid(901), tests.get_supabase_uid('mom')),
  '42501', null,
  'authenticated cannot write prediction_projections directly (RPC-only)');

-- The token hash is not even usable as a WHERE-clause comparison oracle.
select tests.authenticate_as('mom');
select throws_ok(
  format($$select count(*) from public.prediction_connections
    where token_hash = %L$$, pg_temp.token(207)),
  '42501', null,
  'token_hash cannot be referenced by an authenticated query at all');

-- ---------------------------------------------------------------------------
-- 5. The projection boundary: derived-only payload, recipient read path.
-- ---------------------------------------------------------------------------
select public.upsert_prediction_projection(
  tests.ulid(901),
  jsonb_build_object(
    'generated_at', '2026-09-07',
    'period_days', jsonb_build_array('2026-09-09', '2026-09-10'),
    'fertile_days', jsonb_build_array('2026-09-21', '2026-09-22'),
    'ovulation_days', jsonb_build_array('2026-09-22'),
    'pms_days', jsonb_build_array('2026-09-02', '2026-09-03')));
select is(
  pg_temp.proj_count(),
  1::bigint, 'the sharer''s publish stores exactly one snapshot row');

-- Payload validation: nothing but derived-phase keys and date strings.
select throws_ok(
  format($$select public.upsert_prediction_projection(%L,
    '{"generated_at":"2026-09-07","note":"sneaky"}'::jsonb)$$, tests.ulid(901)),
  '22023', 'projection key note is not a derived-phase field',
  'a free-text key cannot ride along in the projection');
select throws_ok(
  format($$select public.upsert_prediction_projection(%L,
    '{"generated_at":"not-a-date"}'::jsonb)$$, tests.ulid(901)),
  '22023', null,
  'generated_at must be an ISO date');
select throws_ok(
  format($$select public.upsert_prediction_projection(%L,
    jsonb_build_object('generated_at', '2026-09-07', 'period_days',
      (select jsonb_agg((date '2026-01-01' + d)::text)
         from generate_series(1, 101) d)))$$, tests.ulid(901)),
  '22023', 'projection.period_days may hold at most 100 dates',
  'a projection date array is bounded at 100');
select throws_ok(
  format($$select public.upsert_prediction_projection(%L,
    '{"generated_at":"2026-09-07","period_days":["2026-09-09",42]}'::jsonb)$$,
    tests.ulid(901)),
  '22023', null,
  'projection arrays hold only ISO date strings');

select is(
  public.get_prediction_projection(tests.ulid(901)),
  '{"generated_at":"2026-09-07","period_days":["2026-09-09","2026-09-10"],"fertile_days":["2026-09-21","2026-09-22"],"ovulation_days":["2026-09-22"],"pms_days":["2026-09-02","2026-09-03"]}'::jsonb,
  'the recipient reads back exactly the derived phases (the RPC return shape is the AC''s inspection surface)');

select tests.authenticate_as('dad');
select is(
  public.get_prediction_projection(tests.ulid(901)) ->> 'generated_at',
  '2026-09-07',
  'a co_parent guardian can read the projection (gains nothing new -- full raw access already)');
select tests.authenticate_as('doctor');
select is(
  public.get_prediction_projection(tests.ulid(901)) ->> 'generated_at',
  '2026-09-07',
  'a viewer guardian can read the projection (same reason)');
select throws_ok(
  format($$select public.upsert_prediction_projection(%L,
    '{"generated_at":"2026-09-07"}'::jsonb)$$, tests.ulid(901)),
  '42501', 'only an accepted guardian of this profile can publish its prediction projection',
  'a viewer is outside the publish ladder (mirror of upsert_reminder_window)');

select tests.authenticate_as('nanny');
select is(
  public.get_prediction_projection(tests.ulid(901)),
  null, 'an unrelated account gets null (enumeration-safe)');
select is(
  public.get_prediction_projection('01ARZ3NDEKTSV4RRFFQ69G5ZZZZZZZZ'),
  null, 'a nonexistent profile is indistinguishable from an unshared one');
select throws_ok(
  format($$select public.upsert_prediction_projection(%L,
    '{"generated_at":"2026-09-07"}'::jsonb)$$, tests.ulid(902)),
  '42501', 'only an accepted guardian of this profile can publish its prediction projection',
  'a non-guardian cannot publish for a profile they do not guard');

select tests.authenticate_as('sitter');
select throws_ok(
  format($$select public.upsert_prediction_projection(%L,
    '{"generated_at":"2026-09-07"}'::jsonb)$$, tests.ulid(902)),
  '42501', 'only an accepted guardian of this profile can publish its prediction projection',
  'a caregiver on P1 cannot publish for P2');

-- Raw-data isolation: the recipient session sees no entries, no profile.
select tests.authenticate_as('stranger');
select is(
  (select count(*) from public.day_entries where profile_id = tests.ulid(901)),
  0::bigint, 'the recipient session sees zero day_entries rows for the shared profile');
select is(
  (select count(*) from public.profiles where id = tests.ulid(901)),
  0::bigint, 'the recipient session cannot even read the shared profile row');

-- ---------------------------------------------------------------------------
-- 6. revoke_prediction_connection: authority, terminality, no residue.
-- ---------------------------------------------------------------------------
select tests.clear_authentication();
insert into r select 'conn_207_id',
  jsonb_build_object('id',
    (select id::text from public.prediction_connections
      where profile_id = tests.ulid(901)
        and recipient_user_id = tests.get_supabase_uid('stranger')));
select tests.authenticate_as('dad');
select throws_ok(
  format($$select public.revoke_prediction_connection(%L::uuid)$$,
    (select v ->> 'id' from r where name = 'conn_207_id')),
  '42501', 'only the sharer or the current primary guardian can revoke this connection',
  'a co_parent cannot revoke the connection');
select tests.authenticate_as('nanny');
select throws_ok(
  format($$select public.revoke_prediction_connection(%L::uuid)$$,
    (select v ->> 'id' from r where name = 'conn_207_id')),
  '42501', 'only the sharer or the current primary guardian can revoke this connection',
  'an unrelated account cannot revoke the connection');

select tests.authenticate_as('mom');
select is(
  public.revoke_prediction_connection(
    (select id from public.prediction_connections
      where profile_id = tests.ulid(901)
        and recipient_user_id = tests.get_supabase_uid('stranger'))),
  true, 'the sharer can revoke the connection');
select is(
  pg_temp.conn_revoked(pg_temp.token(207)),
  true, 'revocation is stamped on the row');
select is(
  pg_temp.proj_count(),
  0::bigint, 'revocation deleted the snapshot (the GC trigger, same transaction)');
select is(
  public.get_prediction_projection(tests.ulid(901)),
  null, 'the recipient''s next fetch already returns null (no residual access)');
select tests.authenticate_as('stranger');
select is(
  public.get_prediction_projection(tests.ulid(901)),
  null, 'the revoked recipient''s fetch returns null');
select is(
  (select count(*) from public.prediction_connections
    where profile_id = tests.ulid(901)),
  0::bigint, 'the revoked connection is no longer visible to the recipient');

select tests.authenticate_as('mom');
select is(
  public.revoke_prediction_connection(
    (select id from public.prediction_connections
      where profile_id = tests.ulid(901)
        and recipient_user_id = tests.get_supabase_uid('stranger'))),
  true, 'revocation is idempotent on an already-revoked connection');

-- ---------------------------------------------------------------------------
-- 6b. Minor profiles (issue #373): refused at create AND at accept --
--     PRIVACY.md section 5's "minor profiles are never shared". The flag
--     is flipped in owner context, the way section 7 flips the life-stage
--     mode, because is_minor is client-writable (sync_push, direct column
--     grant) and so can change between arming a code and its redemption.
--     P1 has no live connection on entry and none on exit.
-- ---------------------------------------------------------------------------
select tests.clear_authentication();
update public.profiles set is_minor = true where id = tests.ulid(901);

select tests.authenticate_as('mom');
select throws_ok(
  format($$select public.create_prediction_connection(%L, %L, null, 72)$$,
    tests.ulid(901), pg_temp.token(291)),
  '55000', 'prediction-only sharing is unavailable for a minor''s profile',
  'creating is refused for a minor''s profile');

select tests.clear_authentication();
update public.profiles set is_minor = false where id = tests.ulid(901);
select tests.authenticate_as('mom');
select ok(
  public.create_prediction_connection(tests.ulid(901), pg_temp.token(291), 'Partner', 72)
    is not null,
  'clearing the minor flag re-opens creation');

-- The flag can change between arming and redemption: accept re-checks.
select tests.clear_authentication();
update public.profiles set is_minor = true where id = tests.ulid(901);
select tests.authenticate_as('stranger');
select throws_ok(
  format($$select public.accept_prediction_connection(%L)$$, pg_temp.token(291)),
  '55000', 'prediction-only sharing is unavailable for a minor''s profile',
  'accepting is refused once the profile is marked a minor');

select tests.clear_authentication();
update public.profiles set is_minor = false where id = tests.ulid(901);
select tests.authenticate_as('stranger');
insert into r select 'accept_minor_lifted', public.accept_prediction_connection(pg_temp.token(291));
select is(
  (select v ->> 'profile_id' from r where name = 'accept_minor_lifted'),
  tests.ulid(901),
  'the same, not-yet-consumed code redeems once the minor flag is cleared');

-- Reset: leave P1 with no live connection, as section 7 expects.
select tests.authenticate_as('mom');
select is(
  public.revoke_prediction_connection(
    (select id from public.prediction_connections
      where profile_id = tests.ulid(901)
        and recipient_user_id = tests.get_supabase_uid('stranger')
        and revoked_at is null)),
  true, 'the section-6b connection is revoked to reset the fixture');

-- ---------------------------------------------------------------------------
-- 7. Pregnancy mode: refused at create AND at accept (life-stage mode,
--    not #131's care mode).
-- ---------------------------------------------------------------------------
select tests.clear_authentication();
insert into public.profile_modes (profile_id, mode, updated_at)
values (tests.ulid(901), 'pregnancy', '2026-09-07T00:00:00Z');

select tests.authenticate_as('mom');
select throws_ok(
  format($$select public.create_prediction_connection(%L, %L, null, 72)$$,
    tests.ulid(901), pg_temp.token(301)),
  '55000', 'prediction-only sharing is unavailable while this profile is in Pregnancy mode',
  'creating is refused while the profile is in Pregnancy mode');

update public.profile_modes set mode = 'tracking' where profile_id = tests.ulid(901);
select ok(
  public.create_prediction_connection(tests.ulid(901), pg_temp.token(301), 'Partner', 72)
    is not null,
  'leaving Pregnancy mode re-opens creation');

-- The mode can change between arming and redemption: accept re-checks.
select tests.clear_authentication();
update public.profile_modes set mode = 'pregnancy' where profile_id = tests.ulid(901);
select tests.authenticate_as('stranger');
select throws_ok(
  format($$select public.accept_prediction_connection(%L)$$, pg_temp.token(301)),
  '55000', 'prediction-only sharing is unavailable while this profile is in Pregnancy mode',
  'accepting is refused while the profile is in Pregnancy mode');

select tests.clear_authentication();
update public.profile_modes set mode = 'tracking' where profile_id = tests.ulid(901);
select tests.authenticate_as('stranger');
insert into r select 'accept_pregnancy_lifted', public.accept_prediction_connection(pg_temp.token(301));
select is(
  (select v ->> 'profile_id' from r where name = 'accept_pregnancy_lifted'),
  tests.ulid(901),
  'the same, not-yet-consumed code redeems once Pregnancy mode is left');

-- ---------------------------------------------------------------------------
-- 8. Stale codes and guardian revocation close the door too.
-- ---------------------------------------------------------------------------
-- Stale-code guard: if the sharer loses the primary seat between arming
-- and redemption, the code refuses.
select tests.clear_authentication();
update public.prediction_connections set revoked_at = clock_timestamp()
 where profile_id = tests.ulid(901);
select tests.authenticate_as('mom');
select ok(
  public.create_prediction_connection(tests.ulid(901), pg_temp.token(401), 'Partner', 72)
    is not null,
  'a fresh invite arms after the revocation');
select tests.clear_authentication();
update public.profile_guardians set role = 'co_parent'
 where profile_id = tests.ulid(901) and user_id = tests.get_supabase_uid('mom');
select tests.authenticate_as('stranger');
select throws_ok(
  format($$select public.accept_prediction_connection(%L)$$, pg_temp.token(401)),
  '55000', 'the sharer is no longer the primary guardian of this profile; the code is stale',
  'a code armed by a former primary guardian refuses to redeem');
select tests.clear_authentication();
update public.profile_guardians set role = 'primary_guardian'
 where profile_id = tests.ulid(901) and user_id = tests.get_supabase_uid('mom');
select tests.authenticate_as('mom');
select is(
  public.revoke_prediction_connection(
    (select id from public.prediction_connections
      where profile_id = tests.ulid(901)
        and recipient_user_id is null
        and revoked_at is null)),
  true, 'the unused stale code is cleaned up');

-- A guardian revocation on the profile revokes the live connection too
-- (#81 precedent: close every door) and deletes the snapshot in the same
-- transaction.
select tests.authenticate_as('mom');
select ok(
  public.create_prediction_connection(tests.ulid(901), pg_temp.token(402), 'Partner', 72)
    is not null,
  'a fresh invite arms for the guardian-revocation test');
select tests.authenticate_as('stranger');
insert into r select 'accept_402', public.accept_prediction_connection(pg_temp.token(402));
select is(
  (select v ->> 'profile_id' from r where name = 'accept_402'),
  tests.ulid(901),
  'the fresh connection activates');
select tests.authenticate_as('mom');
select public.upsert_prediction_projection(
  tests.ulid(901),
  '{"generated_at":"2026-09-07","period_days":["2026-09-09"]}'::jsonb);
select is(
  pg_temp.proj_count(),
  1::bigint, 'the snapshot is published for the active connection');
select is(
  public.revoke_guardian(tests.ulid(901), tests.get_supabase_uid('sitter')),
  true, 'revoke_guardian still works (unregressed)');
select is(
  pg_temp.conn_revoked(pg_temp.token(402)),
  true, 'a guardian revocation revoked the profile''s live prediction connection');
select is(
  pg_temp.proj_count(),
  0::bigint, 'and deleted the snapshot in the same transaction');
select tests.authenticate_as('stranger');
select is(
  public.get_prediction_projection(tests.ulid(901)),
  null, 'the guardian-revoked recipient has no residual access');

-- ---------------------------------------------------------------------------
-- 9. Realtime: reconcile_realtime_publication reverts a Studio toggle on
--    the new tables (they must never cross the websocket).
-- ---------------------------------------------------------------------------
select tests.clear_authentication();
alter publication supabase_realtime add table public.prediction_connections;
alter publication supabase_realtime add table public.prediction_projections;
select lives_ok(
  'select public.reconcile_realtime_publication()',
  'reconcile_realtime_publication() runs with the prediction tables toggled on');
select is(
  (select count(*)::integer from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename in ('prediction_connections', 'prediction_projections')),
  0, 'the reconcile guard dropped both prediction tables from the publication');
select is(
  (select attnames from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'sync_signals'),
  '{profile_id,updated_at}'::name[],
  'sync_signals stays the only published table, unchanged two-column shape');

-- ---------------------------------------------------------------------------
-- 10. Everything requires a session.
-- ---------------------------------------------------------------------------
select tests.clear_authentication();
select throws_ok(
  format($$select public.create_prediction_connection(%L, %L, null, 72)$$,
    tests.ulid(901), pg_temp.token(501)),
  '42501', 'authentication required',
  'create requires a session');
select throws_ok(
  format($$select public.accept_prediction_connection(%L)$$, pg_temp.token(502)),
  '42501', 'authentication required',
  'accept requires a session');
select throws_ok(
  format($$select public.revoke_prediction_connection('00000000-0000-0000-0000-000000000000'::uuid)$$),
  '42501', 'authentication required',
  'revoke requires a session');
select throws_ok(
  format($$select public.upsert_prediction_projection(%L, '{"generated_at":"2026-09-07"}'::jsonb)$$,
    tests.ulid(901)),
  '42501', 'authentication required',
  'publish requires a session');
select throws_ok(
  format($$select public.get_prediction_projection(%L)$$, tests.ulid(901)),
  '42501', 'authentication required',
  'read requires a session');

rollback;

