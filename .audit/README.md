# Decision trail — PM run 2026-10-10

`pm-2026-10-10.tsv` is the decision log for the 2026-10-10 product-manager run
(review, future plan, issue filing, and the implementation units that shipped).
One row per decision, tab-separated:

| Column | Meaning |
|---|---|
| `ts` | UTC timestamp |
| `phase` | what kind of decision (review, plan, file, fix, merge, note, ...) |
| `decision` | what was decided or done |
| `why` | the reason, including the alternative it beat |
| `evidence` | what was checked or measured |
| `result` | the outcome, with issue/PR numbers |

The run's artifacts on `main`: `docs/product/2026-10-10-product-review.md`,
`docs/product/2026-10-10-future-plan.md` (with its Outcomes section), and the
issues it filed (#1791-#1797, #1811). This branch exists so the trail survives
the removal of the run's worktree.
