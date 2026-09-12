-- Migration: 20260913021000_account_deletion_progress.sql
-- Issue #527 (P1): delete-account burns the one-time Apple authorization
-- code before deleteUser -- a deleteUser failure used to strand the account
-- permanently. The Edge Function's steps were: (3) require an Apple code for
-- an Apple-linked account, (6) revoke it, (8) delete the auth.users row. If
-- step 8 failed, the documented retry ("call again with a fresh code") ran
-- steps 3/6 again -- but the grant was already revoked in the failed
-- attempt, so exchanging a *fresh* code at Apple would still be pointless
-- (the account is already revoked server-side; Apple has no way to know
-- that from this end without asking it), and forcing the client to obtain
-- and submit another one-time code purely to no-op-revoke an
-- already-revoked grant is needless friction on what should be a pure
-- retry of one already-fixable step (auth.admin.deleteUser).
--
-- Fix: a durable, server-side marker recorded the instant Apple revocation
-- actually succeeds, checked before steps 3/6 run again. Once set, a retry
-- skips straight to auth.admin.deleteUser -- the only step that could have
-- failed and left the account stranded.
--
-- This table is written directly by the delete-account Edge Function's
-- service-role client (mirroring push-dispatch's/feedback-notify's plain
-- service-role table writes elsewhere in this schema) rather than through a
-- SECURITY DEFINER RPC -- there is no authenticated-facing operation here at
-- all, so no RLS-bypassing wrapper is needed the way rehome_stray_day_entries
-- needed one to be safely callable with an explicit subject.

create table public.account_deletion_progress (
  user_id uuid primary key
    references auth.users (id) on delete cascade,
  apple_revoked_at timestamptz,
  created_at timestamptz not null default now()
);

comment on table public.account_deletion_progress is
  'Durable bookkeeping for in-app account deletion (Issue #527): '
  'apple_revoked_at is stamped by the delete-account Edge Function the '
  'instant it confirms Apple has revoked the caller''s Sign in with Apple '
  'grant, immediately before the function''s own irreversible '
  'auth.admin.deleteUser call. A retry after a deleteUser failure checks '
  'this row first and, when apple_revoked_at is already set, skips both the '
  'Apple-authorization-code precondition and the revocation call entirely -- '
  'going straight back to auth.admin.deleteUser -- rather than requiring a '
  'fresh one-time code to no-op-revoke a grant that is already gone. Row '
  'lifetime is exactly one deletion attempt: it cascades away with the '
  '`auth.users` row on eventual success, and a never-retried failed attempt '
  'is harmless leftover state (the marker only ever narrows what a future '
  'retry does, never widens it). No authenticated policy exists at all -- '
  'this is server-side bookkeeping only, written and read exclusively by '
  'the delete-account Edge Function''s service-role client, which carries '
  'BYPASSRLS.';

alter table public.account_deletion_progress enable row level security;
alter table public.account_deletion_progress force row level security;

-- Deliberately no policies and no grants for authenticated/anon, mirroring
-- notification_outbox's precedent: RLS with zero policies denies every row
-- to every role it applies to. service_role carries BYPASSRLS and reaches
-- this table regardless.
revoke all on table public.account_deletion_progress from public, anon, authenticated;
