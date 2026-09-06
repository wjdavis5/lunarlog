-- Migration: 20260905130000_feedback_attachments_bucket.sql
-- Implements Issue #6 (U2): the private feedback-attachments Storage bucket
-- and its per-user object policies.
--
-- Guarded by to_regclass('storage.buckets')/('storage.objects'): the
-- db-only local stack this repo runs for pgTAP
-- (`supabase start -x ... storage-api ...`, per AGENTS.md "Migration Flow")
-- may not carry the storage schema at all. Everything here runs inside a
-- single DO block using dynamic SQL so the whole unit becomes a no-op
-- locally rather than failing db reset, while still applying normally
-- against Supabase Cloud (production), where the storage schema always
-- exists. See docs/ops/supabase-go-live.md for the manual dashboard
-- fallback if this guard ever fires there.

do $$
begin
  if to_regclass('storage.buckets') is null or to_regclass('storage.objects') is null then
    raise notice 'feedback_attachments_bucket: storage schema not present, skipping (see docs/ops/supabase-go-live.md)';
    return;
  end if;

  execute $sql$
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values (
      'feedback-attachments',
      'feedback-attachments',
      false,
      5242880,
      array['image/png', 'image/jpeg', 'image/webp']
    )
    on conflict (id) do nothing
  $sql$;

  -- Path convention: <uid>/<ticket_id>/<uuid>.<ext>, so (storage.foldername
  -- (name))[1] is the owning user's uid for every object in this bucket.
  execute $sql$
    create policy "feedback_attachments_select" on storage.objects
      for select to authenticated
      using (
        bucket_id = 'feedback-attachments'
        and (storage.foldername(name))[1] = (select auth.uid())::text
      )
  $sql$;

  execute $sql$
    create policy "feedback_attachments_insert" on storage.objects
      for insert to authenticated
      with check (
        bucket_id = 'feedback-attachments'
        and (storage.foldername(name))[1] = (select auth.uid())::text
      )
  $sql$;

  execute $sql$
    create policy "feedback_attachments_delete" on storage.objects
      for delete to authenticated
      using (
        bucket_id = 'feedback-attachments'
        and (storage.foldername(name))[1] = (select auth.uid())::text
      )
  $sql$;

  -- Deliberately absent: no update policy. An attachment is uploaded once at
  -- submission time and never edited in place; replacing it means deleting
  -- and re-uploading, which the two policies above already cover.
end;
$$;
