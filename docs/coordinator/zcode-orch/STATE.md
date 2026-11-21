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

2026-09-22: flash-session wave merged #967 #981 #983 #989 #990 #1007 #1059 #1063 (+parallel #1046 won #1022). In progress: none. Queue: see log.

## 2026-11-08 session (triage + one implementation)
- Resolved: #1927 (closed; macOS capacity, main proven green at b38ef09c), #1930 via PR #1931 (merged 4b775c31), dependabot #1928 (merged b38ef09c).
- With the owner: #1929 (needs-human-review — approve migrate run 38065716532 before it auto-fails ~2026-11-09 15:57Z; ~11 commits of migrations pending since 2026-10-05).
- Backlog: no claimable issues remain (needs-human-review / decision-gated / deferred #161 only).

## 2026-11-20 session
- Merged: #1935 (3b0ac032), #1933 with pin-guard lockstep 191c7f36 (3e8b41fa), #1934 via PR #1937 (5579bd7c).
- Filed #1936 (stale claim on #551, owner to answer release-or-keep).
- With the owner: #1929 (migrations frozen since 2026-10-05 — dispatch + two approvals, or ask a coordinator to collapse the gates), #1936, and the standing needs-human-review set.
- Eligible queue: empty (deferred #161 only). Flash-model subagent dispatch still broken host-side (reasoning-tier selection); general-purpose + coordinator review used instead.

## 2026-11-20 device-test session (evening)
- Device pass on the owner's Pixel 8 Pro: everything green except #600 (deep link no-op) — see log.md for the full matrix.
- #1939 filed → PR #1940 merged (69aea39b): settings launch moved to a first-party platform channel. Full button-path verification needs a lock-less device/emulator (owner's phone has a screen lock); action resolution + startup + channel wiring are proven.
- Device left with the merged-main non-QA debug build, fresh data, gate engaged.
