-- Coverage for Issue #636, LLA-056 (P2): authenticated outsiders can query
-- arbitrary known family relationships via is_profile_guardian(),
-- is_guardian_with_roles(), and owns_feedback_ticket() - three SECURITY
-- DEFINER helpers that bypass RLS and, before this fix, answered truthfully
-- about ANY (profile_id/ticket_id, user_id) pair a caller supplied, not
-- only pairs involving the caller. EXECUTE stays granted to `authenticated`
-- throughout (revoking it would break every RLS policy that calls these
-- helpers directly - see this migration's own comment), so the fix is in
-- the helpers' own logic: each now refuses to answer for any p_user_id
-- other than the caller's own auth.uid().
begin;
select plan(15);

select tests.create_supabase_user('mom_l056');
select tests.create_supabase_user('dad_l056');
select tests.create_supabase_user('eve_l056');

create function pg_temp.token(n int) returns text language sql as
  $$ select lpad(to_hex(n), 64, '0') $$;

select tests.authenticate_as('mom_l056');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(961), 'Riley', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
select public.create_guardian_invitation(tests.ulid(961), 'co_parent', 'Dad', pg_temp.token(111), 48);
select tests.authenticate_as('dad_l056');
select public.accept_guardian_invitation(pg_temp.token(111), 'Dad');

insert into public.feedback_tickets (user_id, reply_email, category, message, device_info)
values (tests.get_supabase_uid('dad_l056'), 'dad@example.com', 'bug', 'a ticket only dad owns', '{}'::jsonb);

-- ---------------------------------------------------------------------------
-- 1-3. Grant posture is unchanged: authenticated still holds EXECUTE
-- (required for RLS - see the migration's own header), anon/public still
-- do not (unchanged since 20260908121000).
-- ---------------------------------------------------------------------------
select ok(
  has_function_privilege('authenticated', 'public.is_profile_guardian(text, uuid)', 'execute'),
  'authenticated still holds EXECUTE on is_profile_guardian (RLS needs it)'
);
select ok(
  not has_function_privilege('anon', 'public.is_profile_guardian(text, uuid)', 'execute'),
  'anon still holds no EXECUTE on is_profile_guardian'
);
select ok(
  not has_function_privilege('public', 'public.is_profile_guardian(text, uuid)', 'execute'),
  'public still holds no EXECUTE on is_profile_guardian'
);

-- ---------------------------------------------------------------------------
-- 4-6. Self-check still works: every real RLS/internal call site passes
-- auth.uid() as p_user_id, and this must keep answering truthfully for it.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('dad_l056');
select is(
  public.is_profile_guardian(tests.ulid(961), tests.get_supabase_uid('dad_l056')),
  true,
  'is_profile_guardian still answers truthfully about the CALLING user'
);
select is(
  public.is_guardian_with_roles(tests.ulid(961), tests.get_supabase_uid('dad_l056'), array['co_parent']),
  true,
  'is_guardian_with_roles still answers truthfully about the CALLING user'
);
select is(
  public.owns_feedback_ticket(
    (select id from public.feedback_tickets where message = 'a ticket only dad owns'),
    tests.get_supabase_uid('dad_l056')
  ),
  true,
  'owns_feedback_ticket still answers truthfully about the CALLING user'
);

-- ---------------------------------------------------------------------------
-- 7-11. The outsider oracle is closed: eve, a stranger with no relationship
-- to profile P or dad's ticket, learns nothing by naming dad's real ids -
-- every call refuses to answer for a p_user_id other than eve's own.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('eve_l056');
select is(
  public.is_profile_guardian(tests.ulid(961), tests.get_supabase_uid('dad_l056')),
  false,
  'LLA-056: an outsider cannot learn whether dad guards profile P via is_profile_guardian'
);
select is(
  public.is_guardian_with_roles(tests.ulid(961), tests.get_supabase_uid('dad_l056'), array['co_parent']),
  false,
  'LLA-056: an outsider cannot learn dad''s role on profile P via is_guardian_with_roles'
);
select is(
  public.is_guardian_with_roles(tests.ulid(961), tests.get_supabase_uid('mom_l056'), array['primary_guardian']),
  false,
  'LLA-056: an outsider cannot learn mom is the primary guardian either'
);
select is(
  public.owns_feedback_ticket(
    (select id from public.feedback_tickets where message = 'a ticket only dad owns'),
    tests.get_supabase_uid('dad_l056')
  ),
  false,
  'LLA-056: an outsider cannot learn dad owns a given feedback ticket'
);
-- Checking herself still answers correctly (false, since eve genuinely has
-- no relationship) - proves the fix didn't just make everything false.
select is(
  public.is_profile_guardian(tests.ulid(961), tests.get_supabase_uid('eve_l056')),
  false,
  'eve checking her own (nonexistent) relationship still gets a real answer'
);

-- ---------------------------------------------------------------------------
-- 12-13. RLS built on these helpers keeps working end to end for the
-- legitimate self-check shape (a real read through the policy, not a
-- direct RPC call) - proves the fix didn't collaterally break RLS.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('dad_l056');
select is(
  (select count(*) from public.profile_guardians where profile_id = tests.ulid(961))::int,
  2,
  'dad (an accepted guardian) can still read profile_guardians rows for his own profile via RLS'
);
select tests.authenticate_as('eve_l056');
select is(
  (select count(*) from public.profile_guardians where profile_id = tests.ulid(961))::int,
  0,
  'eve (an outsider) still sees zero profile_guardians rows for P via RLS'
);

-- ---------------------------------------------------------------------------
-- 14-15. accept_ownership_transfer's own authority check (Issue #618/
-- LLA-054, which stopped routing through is_guardian_with_roles for the
-- initiator) still behaves correctly for both a genuine primary guardian
-- and a non-primary-guardian arming attempt, proving Part 1 (this file)
-- and Part 2's accept_ownership_transfer rewrite compose correctly.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom_l056');
select is(
  (select public.create_ownership_transfer(tests.ulid(961), 'co_parent', pg_temp.token(112)) ->> 'profile_id'),
  tests.ulid(961),
  'the genuine primary guardian can still arm a transfer'
);
select tests.authenticate_as('dad_l056');
select throws_ok(
  format($$select public.create_ownership_transfer(%L, 'viewer', %L)$$, tests.ulid(961), pg_temp.token(113)),
  '42501', null,
  'a co_parent still cannot arm a transfer (R6, via the caller-locked check)'
);

select * from finish();
rollback;
