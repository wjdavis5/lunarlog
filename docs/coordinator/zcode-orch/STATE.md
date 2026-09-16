# ZCode coordinator state (zcode-orch)

Migrated 2026-09-15 from the flat claude-orch state (see PROCESS.md for why).

## In progress (branch prefix grandfathered claude-orch/ where noted)
| issue | branch | worktree | PR | status |
|---|---|---|---|---|
| 241 | claude-orch/241-profile-card (gf) | .worktrees/claude-orch/241-profile-card | — | coding (long runner, 2 quota kills survived, committed partial work on branch) |
| 257 (P0) | zcode-orch/257-custom-tags | .worktrees/zcode-orch/257-custom-tags | — | coding (dispatched after #130 landed; brief anchored on #130's table pattern) |
| 185 | claude-orch/185-migration-safety (gf) | — | 721 | HELD for operator: SUPABASE_PITR_CONFIRMED (issue #723; variable verified unset) |

(gf) = grandfathered claude-orch prefix from the pre-migration dispatch; PR label carries ownership.

## Queued (full zcode-orch markers)
- After #257 lands: #181 (derived sync_push allowlists) → #170 (day_entry_history) — same sync_push serialization.
- Nothing else claimable: remaining opens are needs-human-review (#18 #19 #21 #22 #29 #52 #104 #117 #295 #450 #451 #464 #467 + ours #723 #724 #725 #730 #736), taste-gated (#164 #258 #262), import-epic (parallel session), health-sync/modes blocked on adapters/modes, device/console items.

## Done (this session; details in ../log.md and log.md)
#710 (#713), #583 (#717), #400 (#719), #175 (#720), #137 (#727), #99 (#728), #693 (#731), #165 (#732), sibling rescue #268+#271 (#714), #215 (#734), #121 (#740), #460 (#741), #42 (#742), #130 (#743, post-integration), #174 (#744), #226 (#745, post-ratchet-fix), #102 (#746), #184 (#747); syncs #711 #715 #716 #722 #729 #737 (identity migration).
