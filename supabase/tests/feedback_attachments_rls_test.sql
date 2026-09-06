-- RLS tests for the feedback-attachments Storage bucket (Issue #6, Unit U2).
-- Runs only when the local stack carries the storage schema; the migration
-- itself is guarded to no-op when it does not (see its header comment).
--
-- The plan's "A deletes their own object" edge case is not run here: this
-- stack's storage schema enforces `storage.protect_delete()`, which raises
-- on every direct SQL DELETE against storage.objects regardless of role or
-- RLS ("Direct deletion from storage tables is not allowed. Use the
-- Storage API instead.") — observed running this suite locally. The
-- `feedback_attachments_delete` policy's `using` clause is identical in
-- shape to `_select`/`_insert` above (bucket_id plus the owning-uid folder
-- check), both of which are proven runnable here.
begin;
select plan(4);

select tests.create_supabase_user('fb_attach_a');
select tests.create_supabase_user('fb_attach_b');

-- ---------------------------------------------------------------------------
-- 1. Happy path: A inserts and can select an object under their own folder
-- ---------------------------------------------------------------------------
select tests.authenticate_as('fb_attach_a');

insert into storage.objects (bucket_id, name, owner)
values (
  'feedback-attachments',
  tests.get_supabase_uid('fb_attach_a')::text || '/t1/shot.png',
  tests.get_supabase_uid('fb_attach_a')
);

select is(
  (select count(*) from storage.objects
    where bucket_id = 'feedback-attachments'
      and name = tests.get_supabase_uid('fb_attach_a')::text || '/t1/shot.png'),
  1::bigint,
  'A can insert and select an object under their own uid folder'
);

-- ---------------------------------------------------------------------------
-- 2. Covers AE6: B cannot see A's object
-- ---------------------------------------------------------------------------
select tests.authenticate_as('fb_attach_b');

select is(
  (select count(*) from storage.objects
    where bucket_id = 'feedback-attachments'
      and name = tests.get_supabase_uid('fb_attach_a')::text || '/t1/shot.png'),
  0::bigint,
  'AE6: B selecting A''s object gets no row'
);

-- ---------------------------------------------------------------------------
-- 3. Error path: A cannot insert an object under B's folder
-- ---------------------------------------------------------------------------
select tests.authenticate_as('fb_attach_a');

select throws_ok(
  format(
    $$insert into storage.objects (bucket_id, name, owner)
      values ('feedback-attachments', %L, %L)$$,
    tests.get_supabase_uid('fb_attach_b')::text || '/t1/shot.png',
    tests.get_supabase_uid('fb_attach_a')
  ),
  '42501', null, 'A cannot insert an object under B''s uid folder'
);

-- ---------------------------------------------------------------------------
-- 4. Error path: A cannot insert into a different bucket. A second real
--    bucket is created (bypassing RLS) so the rejection below is provably
--    the policy's bucket_id check, not a foreign-key failure on a
--    nonexistent bucket.
-- ---------------------------------------------------------------------------
select tests.clear_authentication();

insert into storage.buckets (id, name, public)
values ('fb-attach-other-bucket-test', 'fb-attach-other-bucket-test', false)
on conflict (id) do nothing;

select tests.authenticate_as('fb_attach_a');

select throws_ok(
  format(
    $$insert into storage.objects (bucket_id, name, owner)
      values ('fb-attach-other-bucket-test', %L, %L)$$,
    tests.get_supabase_uid('fb_attach_a')::text || '/t1/shot.png',
    tests.get_supabase_uid('fb_attach_a')
  ),
  '42501', null, 'A cannot insert an object into a bucket other than feedback-attachments'
);

select * from finish();
rollback;
