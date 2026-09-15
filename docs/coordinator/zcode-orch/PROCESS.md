# Coordinator process — lunarlog — `zcode-orch`

ZCode's coordinator process. All rules are inherited verbatim from the flat
[`../PROCESS.md`](../PROCESS.md) (the original claude-orch text) with one
substitution: **this coordinator's id is `zcode-orch`** — markers are the
label `owner:zcode-orch` on issues, the label plus branch prefix
`zcode-orch/` on PRs, and the worktree path prefix
`.worktrees/zcode-orch/`.

Migration note (2026-09-15): the ZCode session operated under the
grandfathered `claude-orch` id for its first waves (a live Claude Code
session shares that id; sharing markers across engines is unsound). Work
dispatched before the migration keeps its `claude-orch/*` branch prefix
(grandfathered per the README's transition-note pattern) but its issues and
PRs carry `owner:zcode-orch` — the label is the marker while a grandfathered
prefix is in play. Everything dispatched after 2026-09-15T14:00Z uses
`zcode-orch/` end to end. Historical rows in the flat `../STATE.md` and
`../log.md` up to the migration point remain there as the record of the
claude-orch-era work; this directory is the going-forward state.
