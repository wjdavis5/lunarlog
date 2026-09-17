-- Coverage for the Issue #526 retry-robustness schema additions:
-- public.notification_outbox_deliveries (per-device delivery tracking),
-- public.release_notification_outbox_claim() (the atomic claim-release
-- RPC), and public.sweep_notification_outbox()'s now-bounded retries
-- (20260913020000_notification_outbox_retry_tracking.sql). The Edge
-- Function side of this fix (push-dispatch/index.ts's per-device tracking,
-- claimBatch's `.is("sent_at", null)`, and _shared/push.ts's
-- endpoint-vs-token-404 distinction) is covered by `deno test`, not here.
begin;
select plan(15);

select tests.create_supabase_user('guardian_a');
select tests.authenticate_as('guardian_a');

insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(501), 'Rowan', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

-- A device row and an outbox row to attach deliveries/releases to. Inserted
-- as service_role so this file doesn't need a full guardian/preferences
-- setup just to get one outbox row to work with.
select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);

insert into public.push_devices (id, user_id, token, platform)
values ('00000000-0000-0000-0000-000000000501'::uuid, tests.get_supabase_uid('guardian_a'), 'token-501', 'ios');

insert into public.notification_outbox (id, profile_id, recipient_user_id, kind, claimed_at)
values (
  '00000000-0000-0000-0000-000000000601'::uuid,
  tests.ulid(501),
  tests.get_supabase_uid('guardian_a'),
  'logged',
  now()
);

-- ---------------------------------------------------------------------------
-- notification_outbox_deliveries: shape, RLS, and cascade behavior.
-- ---------------------------------------------------------------------------

select tests.rls_forced('public', 'notification_outbox_deliveries');

insert into public.notification_outbox_deliveries (outbox_id, device_id)
values ('00000000-0000-0000-0000-000000000601'::uuid, '00000000-0000-0000-0000-000000000501'::uuid);

select is(
  (select count(*) from public.notification_outbox_deliveries
    where outbox_id = '00000000-0000-0000-0000-000000000601'::uuid),
  1::bigint,
  'service_role can record a delivery row'
);

-- Re-recording the same (outbox_id, device_id) pair is exactly what
-- push-dispatch's own upsert does on a retried send; the primary key makes
-- that idempotent rather than a duplicate row.
insert into public.notification_outbox_deliveries (outbox_id, device_id, sent_at)
values ('00000000-0000-0000-0000-000000000601'::uuid, '00000000-0000-0000-0000-000000000501'::uuid, now())
on conflict (outbox_id, device_id) do update set sent_at = excluded.sent_at;

select is(
  (select count(*) from public.notification_outbox_deliveries
    where outbox_id = '00000000-0000-0000-0000-000000000601'::uuid),
  1::bigint,
  'the (outbox_id, device_id) primary key makes a re-recorded delivery idempotent, not a duplicate row'
);

select tests.authenticate_as('guardian_a');
select throws_ok(
  $$select count(*) from public.notification_outbox_deliveries$$,
  '42501', null,
  'authenticated has no grant at all on notification_outbox_deliveries, even for their own device''s rows'
);

select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);

-- Deleting the outbox row cascades its deliveries.
delete from public.notification_outbox where id = '00000000-0000-0000-0000-000000000601'::uuid;
select is(
  (select count(*) from public.notification_outbox_deliveries
    where device_id = '00000000-0000-0000-0000-000000000501'::uuid),
  0::bigint,
  'deleting the outbox row cascades its notification_outbox_deliveries rows'
);

-- Deleting the device row also cascades.
insert into public.notification_outbox (id, profile_id, recipient_user_id, kind, claimed_at)
values (
  '00000000-0000-0000-0000-000000000602'::uuid,
  tests.ulid(501),
  tests.get_supabase_uid('guardian_a'),
  'logged',
  now()
);
insert into public.notification_outbox_deliveries (outbox_id, device_id)
values ('00000000-0000-0000-0000-000000000602'::uuid, '00000000-0000-0000-0000-000000000501'::uuid);

delete from public.push_devices where id = '00000000-0000-0000-0000-000000000501'::uuid;
select is(
  (select count(*) from public.notification_outbox_deliveries
    where outbox_id = '00000000-0000-0000-0000-000000000602'::uuid),
  0::bigint,
  'deleting the device row cascades its notification_outbox_deliveries rows'
);

-- ---------------------------------------------------------------------------
-- release_notification_outbox_claim: the atomic optimistic-lock RPC.
-- ---------------------------------------------------------------------------

insert into public.push_devices (id, user_id, token, platform)
values ('00000000-0000-0000-0000-000000000502'::uuid, tests.get_supabase_uid('guardian_a'), 'token-502', 'ios');

insert into public.notification_outbox (id, profile_id, recipient_user_id, kind, claimed_at, attempts)
values (
  '00000000-0000-0000-0000-000000000603'::uuid,
  tests.ulid(501),
  tests.get_supabase_uid('guardian_a'),
  'logged',
  '2026-09-13T00:00:00Z'::timestamptz,
  2
);

-- A stale claimed_at token (not the one the row is actually claimed with)
-- must not match - the RPC's own optimistic-lock semantics.
select public.release_notification_outbox_claim(
  '00000000-0000-0000-0000-000000000603'::uuid,
  '2020-01-01T00:00:00Z'::timestamptz,
  'network_error'
);
select is(
  (select claimed_at from public.notification_outbox where id = '00000000-0000-0000-0000-000000000603'::uuid),
  '2026-09-13T00:00:00Z'::timestamptz,
  'release_notification_outbox_claim is a no-op when p_claimed_at does not match the row''s current claimed_at'
);
select is(
  (select attempts from public.notification_outbox where id = '00000000-0000-0000-0000-000000000603'::uuid),
  2,
  'a mismatched claimed_at token must not increment attempts'
);

-- The real claimed_at token releases the claim and increments attempts
-- exactly once.
select public.release_notification_outbox_claim(
  '00000000-0000-0000-0000-000000000603'::uuid,
  '2026-09-13T00:00:00Z'::timestamptz,
  'network_error'
);
select is(
  (select claimed_at from public.notification_outbox where id = '00000000-0000-0000-0000-000000000603'::uuid),
  null,
  'release_notification_outbox_claim clears claimed_at when p_claimed_at matches'
);
select is(
  (select attempts from public.notification_outbox where id = '00000000-0000-0000-0000-000000000603'::uuid),
  3,
  'release_notification_outbox_claim increments attempts by exactly one'
);
select is(
  (select last_error_kind from public.notification_outbox where id = '00000000-0000-0000-0000-000000000603'::uuid),
  'network_error',
  'release_notification_outbox_claim stamps last_error_kind'
);

select tests.authenticate_as('guardian_a');
select throws_ok(
  $$select public.release_notification_outbox_claim(
      '00000000-0000-0000-0000-000000000603'::uuid, now(), 'network_error')$$,
  '42501', null,
  'authenticated has no execute grant on release_notification_outbox_claim'
);

select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);

-- ---------------------------------------------------------------------------
-- sweep_notification_outbox: now bounds retries too (Issue #526 fix (c)).
-- ---------------------------------------------------------------------------

insert into public.notification_outbox (id, profile_id, recipient_user_id, kind, claimed_at, attempts)
values (
  '00000000-0000-0000-0000-000000000604'::uuid,
  tests.ulid(501),
  tests.get_supabase_uid('guardian_a'),
  'logged',
  now() - interval '20 minutes',
  1
);

select public.sweep_notification_outbox();

select is(
  (select claimed_at from public.notification_outbox where id = '00000000-0000-0000-0000-000000000604'::uuid),
  null,
  'sweep_notification_outbox still releases a claim stuck over 15 minutes'
);
select is(
  (select attempts from public.notification_outbox where id = '00000000-0000-0000-0000-000000000604'::uuid),
  2,
  '#526 (c): sweep_notification_outbox now increments attempts on every claim it releases'
);
select is(
  (select last_error_kind from public.notification_outbox where id = '00000000-0000-0000-0000-000000000604'::uuid),
  'stuck_claim_swept',
  '#526 (c): sweep_notification_outbox stamps a distinct last_error_kind so a swept claim is diagnosable'
);

rollback;
