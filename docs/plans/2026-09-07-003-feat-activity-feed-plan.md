---
title: Per-profile Activity Feed - Plan
type: feat
date: 2026-09-07
issue: wjdavis5/lunarlog#124
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-ready
product_contract_source: ce-plan-bootstrap
execution: code
---

# Per-profile Activity Feed - Plan

**Target repo:** `lunarlog` (`wjdavis5/lunarlog`). All paths are repo-relative.

---

## Goal Capsule

- **Objective:** A per-profile Activity screen — a reverse-chronological list of what changed on a shared profile, who changed it, and when — built entirely from the attribution columns the schema already stamps (`logged_by_user_id`, `last_modified_by_user_id`, `updated_at`), plus one device-local record of same-date merge discards.
- **Means:** One pure-Dart domain module (`lib/domain/activity/`), one repository over the existing storage API (`lib/data/repositories/activity_feed_repository.dart`), one screen plus a reusable entry-point button (`lib/ui/sharing/activity_feed_screen.dart`), and three small recording hooks inside `LunarLogStorage`'s existing apply paths. No schema change, no migration, no sync-model change.
- **Authority hierarchy:** GitHub issue #124 owns product intent. The coordinator brief (binding) adds: no schema/sync changes; the device-local merge-event direction for AC4; device-local unread marker; content discretion. This document's contracts own behavior and mechanism detail.
- **Stop conditions:** Stop and surface if recording a merge event can abort or roll back the sync apply that produced it; if any feed row can render a raw user uuid; if any note *text* or tag code can reach a feed row or the device-local event store.
- **Execution profile:** `code`.
- **Tail ownership:** A true append-only audit log (full revision history) is explicitly out of scope — issue #124's own design constraints say that is a schema decision for its own issue. Per-field diffs of ordinary edits (what the old flow/note was before an update) are unknowable from the current schema and are not faked.

---

## Product Contract

### Summary

A profile with two or more accepted guardians gains an **Activity** view, reachable from the profile screen's app bar and from Manage Guardians. It lists changes newest-first: entries logged, entries updated by a different guardian than the one who logged them, entries removed, same-date merge outcomes (whose `flow` or `note` was kept and whose was discarded), and guardians losing access. Each row names the actor ("you", the guardian's display name, the role label, or "a guardian" — never a uuid), shows the date the entry is *for* and when the change happened, and opens that date's day sheet on tap. Rows newer than the last time the operator opened the feed on this device are marked **New**. A single-guardian profile shows a quiet "just you for now" state instead of a feed. A `viewer` can read everything and mutate nothing.

### Honest about what is knowable

The schema records, per row, only the *latest* modifier and the *original* logger — not a revision log. The feed therefore shows **one row per day entry** (its latest state), not one row per edit:

- "Updated by Dad" is knowable when `last_modified_by_user_id` differs from `logged_by_user_id`.
- Dad editing his own entry is indistinguishable from Dad logging it fresh (both stamps read Dad); the row reads "Logged by Dad".
- Earlier edits by the same guardian are not separately recorded, and the screen says so in a standing caption.
- A same-date merge *discard* is only knowable at the moment the resolver runs, so it is captured then (device-locally, see KTD2) rather than reconstructed later.

The screen must never imply a complete audit trail. A true append-only log is a schema change scoped to its own future issue.

### Content discretion

Feed rows carry change-kind, names, the entry date, and calendar-glance facts (flow *level label*, tag *count*, "note" as a boolean). They never carry note text, tag codes, or anything the month calendar does not already show at a glance. Removed rows carry no payload facts at all. Nothing in the feed reaches notifications, lock screens, or crash reports; the device-local event store holds actor ids and booleans only — no note text, no tags.

### Requirements

- **R1** One row per change source, newest first: day entries (live *and* tombstoned), device-local merge events, and revoked guardian rows.
- **R2** Actor naming order: `you` (current signed-in user) → guardian display name → role label → "a guardian"; a row with no attribution at all renders without an actor phrase and without crashing; a raw uuid is never displayed.
- **R3** A change made on another device by another guardian appears without an app restart: the feed is a Drift stream over the same tables sync writes.
- **R4** A same-date collision that discarded a `flow` or `note` value produces a row that says whose value was kept, whose was discarded, and what kind of value it was.
- **R5** Tapping an entry or merge row opens that date's day sheet (the surviving entry, fetched live at tap time).
- **R6** A single-guardian profile (fewer than two accepted guardian rows, including no rows at all — local-only) shows a quiet explanatory state, not an error and not a blank screen.
- **R7** A `viewer` can open the feed and read it; every path out of it is read-only (day sheet opens in its existing viewer read-only mode); the feed offers no write affordances of its own.
- **R8** Rows newer than the device-local per-profile last-seen stamp show a "New" marker; opening the feed re-stamps it. A null (never-opened) stamp shows nothing new — the first visit baselines everything as seen.
- **R9** Role changes and revocations: revocations appear ("<name> no longer has access" — who *performed* the revocation is not recorded anywhere and is not invented). Joins and role changes are not rendered as events because an accepted row cannot be distinguished from "accepted long ago"; they are deferred, not faked.

### Acceptance-criteria mapping

| Issue AC | Requirement |
| --- | --- |
| Two guardians see correctly named rows | R1, R2 |
| Own changes read "you" | R2 |
| Other-device change appears after sync without restart | R3 |
| Same-date discard produces a row that says so | R4 |
| Tap opens that date's day sheet | R5 |
| Single-guardian quiet state | R6 |
| Viewer reads, cannot mutate | R7 |
| Unattributed entry renders safely | R2 |

---

## Planning Contract

### Key technical decisions

- **KTD1 — No schema, no sync change.** The feed reads `getDayEntries(includeTombstones: true)`, `watchGuardiansForProfile`, and `watchSetting`; it writes only `app_settings` rows. No migration, no Drift schema bump, no `sync_push` change, no server change.
- **KTD2 — Merge outcomes are device-local events, recorded at apply time.** `LunarLogStorage` records a `MergeEvent` in the same transaction as the resolution, in exactly the three places a value is actually discarded: (a) `_resolveSameDateConflicts`'s local-loser branch (the local row's differing `note`/`flow` is about to be tombstoned away), (b) the same function's remote-loser branch (the incoming row's differing values are about to be stored payload-free), and (c) `_applyDayEntry` under `applyResolved` (a server resolution overwrites a held local copy whose `note`/`flow` differs). Tags never generate events — the resolver unions them (issue #8 R7), so nothing is discarded. Events live under the `app_settings` key `activity_merge_events_<profileId>` as a bounded JSON list (cap 200, oldest evicted, idempotent by `(loser entry id, resolution stamp)`), never synced, never carrying note text or tag codes.
- **KTD3 — The unread marker is a per-profile `app_settings` timestamp** (`activity_last_seen_<profileId>`), stamped when the feed opens. The screen freezes the *previous* stamp for its "New" comparison during the visit so the chips do not vanish mid-view; the button at the entry point shows a dot whenever any row predates the stamp.
- **KTD4 — One row per source, derived at read time.** `buildActivityFeed` (pure domain function) classifies each day entry from its attribution stamps and merges in the event lists, sorted by `updated_at` descending, capped at 200 rows. "logged" vs "updated" mirrors `sync_push`'s own stamping: insert stamps both columns with the writer; update re-stamps only `last_modified_by_user_id`; a differing modifier means "updated by", anything else reads "logged by"; a tombstone reads "removed by" the last modifier.
- **KTD5 — Revocation rows name the removed guardian, never the remover.** `profile_guardians` does not record who revoked, and the row does not invent it.
- **KTD6 — The feed is read-only plumbing all the way down.** It creates `ActivityFeedRepository` from the provided `LunarLogStorage` exactly where `ProfileGuardiansRepository` is created today; it mutates nothing except the two `app_settings` keys in KTD2/KTD3.

### Implementation units

- **U1** `lib/domain/activity/merge_events.dart` — `MergeEvent`, JSON codec (tolerant decode), `appendMergeEvent` (idempotent, capped, newest-first), settings-key builders.
- **U2** `lib/domain/activity/activity_feed.dart` — `ActivityKind`, `ActivityItem`, `buildActivityFeed`, `activityActorLabel`, `isActivityNew`, relative-time formatter.
- **U3** `lib/data/db/storage.dart` — `_recordMergeEvent` plus the three recording hooks (KTD2).
- **U4** `lib/data/repositories/activity_feed_repository.dart` — stream combiner over the four watches; `markSeen`.
- **U5** `lib/ui/sharing/activity_feed_screen.dart` — screen, rows, quiet states, tap-through, frozen last-seen; `ActivityFeedButton` (icon + new-dot). Route `ActivityFeedScreen` registered in `lib/observability/route_names.dart`.
- **U6** Entry points: `ProfileDetailScreen` app-bar action (hidden when no storage); `ManageGuardiansScreen` optional `activityRepository` action; wired at `profile_picker_screen.dart`.

### Test plan

- Domain unit tests: classification, ordering, actor-label ladder, null attribution, revoked-guardian rows, cap, new-marker semantics, relative time, codec round-trip/corruption/idempotency/eviction.
- Storage tests (in-memory drift): each recording hook fires only on a real discard (identical payloads, tags-only diffs, and non-resolved applies record nothing); idempotent under a replayed resolved row; event content carries no note text.
- Repository tests: combined snapshot emission, live re-emission on a write, `markSeen` stamp.
- Widget tests: named rows and "you"; New chip + stamping; merge copy; tap-through opens the day sheet; single-guardian quiet state; viewer read-only day sheet; unattributed row; entry-point buttons and the new dot.

---

## Not done (explicit)

- **Per-edit revision history / per-field diffs of ordinary edits** — requires a schema change (issue #124's own design constraints); the feed states the limitation instead.
- **Join and role-change events** — an accepted guardian row cannot be distinguished from "accepted long ago" without a device-local event log for guardian rows; deferred rather than faked (R9).
- **Who performed a revocation** — not recorded anywhere in the schema; not invented (KTD5).
- **Local attribution stamping** — rows created offline keep `logged_by_user_id = null` until the server round-trip stamps them (attribution stays server-authoritative, `sync_push`-only); such rows render actor-less per R2.
