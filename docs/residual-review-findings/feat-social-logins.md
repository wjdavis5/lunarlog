# Residual review findings: feat/social-logins

Source: `ce-code-review` run `20260903-064735-750509f4` on branch `feat/social-logins` (head `1d3fbbf`), plan `docs/plans/2026-09-03-001-feat-social-logins-plan.md`. Findings #1 (literal backslash-n in six workflow build steps) and #2 (`reauthenticate()` swallowing a lifecycle departure) were applied in commit `1d3fbbf`; the items below were validated by the independent validator but were single-reviewer at confidence 75 or a product decision, so they are tracked rather than applied.

## Residual Review Findings

- P1 `lib/data/auth/supabase_auth_service.dart:206` Stale network link failure survives a successful retry, misreported to the user -- https://github.com/wjdavis5/lunarlog/issues/24
- P2 `lib/data/auth/supabase_auth_service.dart:585` Create-account magic link is an account-existence oracle once sign-ups close (product decision: the plan's KTD3 chose the invitation-only copy deliberately; the HTTP API is the same oracle to anyone with the publishable key) -- https://github.com/wjdavis5/lunarlog/issues/25
- P2 `lib/data/auth/supabase_auth_service.dart:585` Swallowed `otp_disabled` turns a malformed email into a false "email sent" that persists -- https://github.com/wjdavis5/lunarlog/issues/26

Dropped by the independent validator: an unbounded silent Google access-token read (no evidence it can stall, and the project uses no timeouts on any auth call; a hardening preference).

Soft-bucket items (not filed): add-method tiles render during `passwordRecovery` and then fail after the credential prompt (P3, confidence 50); the credential prompt's own `inactive` report versus `reauthenticate()` **was settled in the field on 2026-09-03 and it was wrong** — the prompt reports `inactive` itself, so `reauthenticate()` cancelled every add-a-method attempt and `unlock()` discarded every granted credential, leaving the app unopenable (issue #65, fixed by `docs/plans/2026-09-03-003-fix-gate-discards-granted-unlock-plan.md`); a 429 on `verifyOTP` shows the "code not accepted" copy; alternating a magic-link request and a password reset invalidates the earlier email's link; testing gaps around `PluginGoogleSignInClient` (untestable by design), the interrupted re-auth on a gated platform (now covered by the applied fix), and workflow shell validation.

Not run: the cross-model adversarial pass (repository content must not leave this machine; the in-process adversarial reviewer ran instead), browser tests (no approved driver on this machine), the iOS build (no macOS here; CI covers the unsigned build), and the device checklist in `docs/ops/supabase-go-live.md`.
