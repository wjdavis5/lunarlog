# Residual review findings: feat/supabase-auth-cloud-sync

Source: `ce-code-review` run `20260902-233322-fa6a8ebc` on branch `feat/supabase-auth-cloud-sync` (head `1f98caf`), plan `docs/plans/2026-09-02-001-feat-supabase-auth-cloud-sync-plan.md`. Findings #1, #2, #3, #4, #7, #17 were applied in commit `1f98caf`; the items below were validated or reviewer-anchored at 75 by a single reviewer and are tracked rather than applied.

## Residual Review Findings

- P1 `lib/ui/account/sign_in_screen.dart:240` Apple Sign-In button should use the HIG-compliant SignInWithAppleButton -- https://github.com/wjdavis5/lunarlog/issues/9 — **closed** by the social-logins PR (branch `feat/social-logins`, plan `docs/plans/2026-09-03-001-feat-social-logins-plan.md`, U4/KTD6: `SignInWithAppleButton`, Apple first on iOS).
- P2 `lib/data/auth/supabase_auth_service.dart:145` Cold start from an auth link blocks the first frame on the network -- https://github.com/wjdavis5/lunarlog/issues/10
- P2 `lib/data/sync/supabase_sync_engine.dart:553` Server-rejected sync rows stay pinned for the whole app session -- https://github.com/wjdavis5/lunarlog/issues/11
- P2 `lib/data/sync/supabase_sync_transport.dart:124` Expired token while offline maps to an auth error and stops backoff -- https://github.com/wjdavis5/lunarlog/issues/12
- P2 `supabase/migrations/20260903014211_sync_push.sql:313` sync_push per-row catch can mistake a transient deadlock for a permanent rejection -- https://github.com/wjdavis5/lunarlog/issues/13
- P2 `supabase/migrations/20260903014211_sync_push.sql:38` Concurrent pushes create server_version gaps the incremental pull skips -- https://github.com/wjdavis5/lunarlog/issues/14
- P3 `lib/ui/account/account_section.dart:189` A failed "Sign out everywhere" drops the session but keeps device data -- https://github.com/wjdavis5/lunarlog/issues/15

Dropped by the independent validator: the Sentry init guard (the SDK already swallows native init failures) and the missing Xcode file reference for `Runner.entitlements` (navigator-only).

Soft-bucket items (not filed): testing gaps for the `SyncTransportRejectedError` push path and the Apple full-name update failure; maintainability notes on the `DeviceResetCallback` typedef living in the composition root and the session predicate duplicated across three UI files.

Not verified in this environment: iOS build and archive (no macOS), Supabase MCP `get_advisors` and `db push --dry-run` against the cloud project, the Sentry smoke test, and the provisioning-profile regeneration for the Sign in with Apple capability (see `docs/ops/supabase-go-live.md`).
