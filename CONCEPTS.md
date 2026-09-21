# Concepts

Shared domain vocabulary for this project — entities, named processes, and status concepts with project-specific meaning. Seeded with core domain vocabulary, then accretes as ce-compound and ce-compound-refresh process learnings; direct edits are fine. Glossary only, not a spec or catch-all.

## Coordinator

An unattended agent loop that owns GitHub issues end to end: picking by priority, claiming, dispatching implementation, reviewing, and merging. Each coordinator has a short id and touches only issues, pull requests, and checkouts carrying its own ownership markers — never another coordinator's, no matter how stale or trivial they look.

Several coordinators share this repo concurrently, so ownership is decided by markers on GitHub, not by what any coordinator's local state files say.

## Coder

The implementation subagent a coordinator dispatches for exactly one issue. It works inside that issue's dedicated isolated checkout and returns a pull request; it never works in the shared main checkout and never takes on a second issue in the same checkout.

## Claim

A coordinator's public taking of an issue, recorded as labels on the issue itself. The labels are the sole source of ownership truth; a coordinator's own state files are only a bookkeeping cache of its actions and never determine what belongs to whom.

## Teen mode and the "late" framing

Teen care mode never uses "late" framing. A teenager's cycles are still settling, so a few days either way is normal, and "late" can read as a failure when nothing is wrong. A teen profile therefore always shows a quiet overdue line ("No new period logged yet — a few days either way is normal.") with a single "log it when it comes" action; the error-styled late resolver never renders. This holds at every confidence tier, not just while a profile is new.

The irregular-cycles framing is a separate axis. That switch (default on for a teen until its cycles reach high confidence) controls whether estimates are hedged as ranges, whether the tier caption shows, and whether the fertile-window estimate appears. It is not what keeps "late" away from a teen — teen mode does that on its own.

