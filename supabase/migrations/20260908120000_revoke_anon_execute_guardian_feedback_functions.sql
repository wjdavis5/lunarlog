-- Migration: 20260908120000_revoke_anon_execute_guardian_feedback_functions.sql
-- Issue #158 (P1): four SECURITY DEFINER functions were granted EXECUTE to
-- authenticated in 20260904010000_multi_guardian_schema.sql (lines 394-395)
-- and 20260906130000_feedback_tickets.sql (line 181) without the matching
-- `revoke execute ... from public, anon` that every other SECURITY DEFINER
-- function in this schema carries (see enforce_day_entry_attribution() at
-- 20260904010000_multi_guardian_schema.sql:392). Because these run with the
-- function owner's privileges and bypass RLS, an unauthenticated caller
-- holding only the publishable key could ask is_profile_guardian()/
-- is_guardian_with_roles() "is user X an accepted guardian of profile Y" and
-- get a definitive answer - an unauthenticated family-membership oracle
-- about a household that may include a minor. owns_feedback_ticket() is the
-- same shape for feedback tickets. on_profile_created_add_guardian() is a
-- trigger function that errors when invoked directly outside its trigger
-- context, so it is lower-value noise, but nothing about its intended use
-- requires public/anon reachability either. Confirmed live against
-- dleexnnevuuddcgcpztq by the Supabase security advisor
-- (anon_security_definer_function_executable) on 2026-09-08.
--
-- The `grant execute ... to authenticated` lines stay untouched: the RLS
-- policies on profiles, day_entries, profile_guardians, and the feedback
-- tables call these functions directly and need authenticated to retain
-- EXECUTE.

revoke execute on function public.is_profile_guardian(text, uuid) from public, anon;
revoke execute on function public.is_guardian_with_roles(text, uuid, text[]) from public, anon;
revoke execute on function public.owns_feedback_ticket(uuid, uuid) from public, anon;
revoke execute on function public.on_profile_created_add_guardian() from public, anon;
