# ZCode coordinator state (zcode-orch)

Migrated 2026-09-15 from the flat claude-orch state (see PROCESS.md for why).

## In progress (branch prefix grandfathered claude-orch/ where noted)
| issue | branch | worktree | PR | status |
|---|---|---|---|---|
| 185 | claude-orch/185-migration-safety (gf) | — | 721 | HELD for operator: SUPABASE_PITR_CONFIRMED (issue #723; variable verified unset) — merge immediately when armed |

(gf) = grandfathered claude-orch prefix from the pre-migration dispatch; PR label carries ownership.

## QUEUE COMPLETE 2026-09-21 — every claimable issue has been through the loop (see Done). Remaining opens: needs-human-review set, taste-gated (#164 #258 #262 #765 #808), needs-agent-review decisions (#845 #849 #850 #851 #852 #855 #895 #898 #957 #959), claude-sonnet set, parallel-session (#841 #956), adapter-blocked (#665 #781 #799). PR #721 HELD for #723 (PITR).

## Queued (full zcode-orch markers)
- QUEUE COMPLETE 2026-09-16: nothing else claimable: remaining opens are needs-human-review (#18 #19 #21 #22 #29 #52 #104 #117 #295 #450 #451 #464 #467 + ours #723 #724 #725 #730 #736), taste-gated (#164 #258 #262), import-epic (parallel session), health-sync/modes blocked on adapters/modes, device/console items.

## Done (this session; details in ../log.md and log.md)
#710 (#713), #583 (#717), #400 (#719), #175 (#720), #137 (#727), #99 (#728), #693 (#731), #165 (#732), sibling rescue #268+#271 (#714), #215 (#734), #121 (#740), #460 (#741), #42 (#742), #130 (#743, post-integration), #174 (#744), #226 (#745, post-ratchet-fix), #102 (#746), #184 (#747), #241 (#749), #257 P0 (#750), #181 (#751), #170 (#752); syncs #711 #715 #716 #722 #729 #737 (identity migration).
