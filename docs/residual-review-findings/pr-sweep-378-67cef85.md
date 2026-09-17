# Residual Review Findings — PR #378 sweep head 67cef85

Source run: ce-code-review run 20260913-232029-c6a9d150 (10 reviewers: correctness, security, data-migration, testing, adversarial, api-contract, project-standards, performance, maintainability, learnings) over PR #378's diff vs main@30f6e12, inside the 2026-09-14 PR-merge sweep (plan: docs/plans/2026-09-13-001-ops-open-pr-review-merge-sweep-plan.md).

Findings APPLIED on the branch before merge (commit 67cef85): the clear-propagation repair (empty document `{}` as the only wire-expressible clear), the real viewer/caregiver role-rung pgTAP coverage, the isMinor widget tests, and the sweep-authored doc/comment corrections (db.dart bullet placement + v13 comment, migration-header provenance chain, AGENTS.md de-splice, stale not-in-enum premises graduated, DaySheet late-final comment, row_codec Map-branch collapse, profile.dart double-call revert + #296 citation).

## Filed (GitHub Issues)

- P3 — tracking_preferences missing from both export paths (diverges from the #255 precedent) — [#648](https://github.com/wjdavis5/lunarlog/issues/648) (reviewers: security anchor-100, data-migration anchor-75)
- P2 — Mirror the tracking-preferences CHECK client-side and bound document size — [#649](https://github.com/wjdavis5/lunarlog/issues/649) (reviewers: adversarial anchor-75, security anchor-50)
- P3 — Widget-test the trackingPreferences/isMinor forwarding chain through the real shells — [#650](https://github.com/wjdavis5/lunarlog/issues/650) (reviewer: testing anchor-75)
- (plan DoD) — ci: add a single name-stable rollup check so job renames stop orphaning open PRs — [#651](https://github.com/wjdavis5/lunarlog/issues/651)
- (plan DoD) — AGENTS.md's schema-history paragraph is a guaranteed merge-conflict generator (and currently stale) — [#652](https://github.com/wjdavis5/lunarlog/issues/652)

## Not filed (informational, recorded here)

- Whole-document LWW between concurrently curating co-guardians: the loser's curation is silently replaced (no per-category merge, unlike day_entries tags) — matches profiles-row semantics; revisit only if curation conflicts become user-visible. (adversarial, residual)
- `DaySheet._categoriesInOrder` is resolved once per sheet open; a co-guardian sync landing while the sheet is open applies on the next open. Comment now says so; test characterization deferred. (correctness/maintainability, residual)
- The server-side explicit-null clear branch (pgTAP `clear_prefs`) is honored but no longer exercised by this client (which clears via `{}`) — kept as the wire contract for other clients. (api-contract, residual)
- `is_valid_tracking_preferences` lacks `set search_path = ''` (only pg_catalog built-ins referenced; the search_path lint class is already tracked under issue #194). (security, residual)
- A server-rejected shape-invalid document would wedge the profile row's sync until reconcile — unreachable from any current writer (picker UI is #234); #649 owns the pre-#234 fix. (adversarial, residual)
- docs/solutions has no learning covering this diff's concepts; the closest in-repo anchors are the sync_push re-emission chain's own headers and AGENTS.md Migration Flow items 6–8. (learnings: no matches)

## Settled-conflict findings

None — no finding conflicted with a `session-settled:` KTD.
