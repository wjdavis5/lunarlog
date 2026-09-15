# ZCode coordinator state (zcode-orch)

Migrated 2026-09-15 from the flat claude-orch state (see PROCESS.md for why).

## In progress (branch prefix grandfathered claude-orch/ where noted)
| issue | branch | worktree | PR | status |
|---|---|---|---|---|
| 42 | claude-orch/42-sync-batching (gf) | .worktrees/claude-orch/42-sync-batching | — | coding |
| 130 | claude-orch/130-same-date-merge-notice (gf) | .worktrees/claude-orch/130-same-date-merge-notice | — | coding |
| 174 | claude-orch/174-fcm-presentation (gf) | .worktrees/claude-orch/174-fcm-presentation | — | coding |
| 241 | claude-orch/241-profile-card (gf) | .worktrees/claude-orch/241-profile-card | — | coding |
| 460 | claude-orch/460-l10n-guard (gf) | .worktrees/claude-orch/460-l10n-guard | — | coding |
| 121 | claude-orch/121-simulator-lifecycle (gf) | .worktrees/claude-orch/121-simulator-lifecycle | — | coding |
| 215 | claude-orch/215-gate-exclusions (gf) | .worktrees/claude-orch/215-gate-exclusions | 734 | in CI (watcher armed) |
| 185 | claude-orch/185-migration-safety (gf) | — | 721 | HELD for operator: SUPABASE_PITR_CONFIRMED (issue #723) |

(gf) = grandfathered claude-orch prefix from the pre-migration dispatch; PR label carries ownership.

## Queued (dispatch with full zcode-orch/ markers)
- On #130's PR merge: #257 (P0 custom-tag registry) → #181 → #170 (all three re-emit sync_push; serialized).
- #226 (settings restructure) after PR #734 merges.
- #184 (per-reminder custom text) after #174 lands.
- #102 after #42 lands. #121 caveat: CI-as-verification loop.

## Done (this session, pre-migration id; details in ../log.md)
#710 (#713), #583 (#717), #400 (#719), #175 (#720), #137 (#727), #99 (#728), #693 (#731), #165 (#732), sibling rescue #268+#271 (#714); state syncs #711 #715 #716 #722 #729.
