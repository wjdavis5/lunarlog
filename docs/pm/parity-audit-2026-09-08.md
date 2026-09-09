# Clue parity audit — 2026-09-08

Product-management record of the gap between `lunarlog` at commit `c35334e` and a shippable product with Clue feature parity plus the three non-negotiable additions (Clue import, Apple Health / Health Connect bidirectional sync, clinical export). The deliverable is the GitHub issue backlog; this file is the summary, the risk register, the execution order, and the list of assumptions the owner should confirm or overturn.

**Method.** Six read-only reviewers ran in parallel against the repo and the live Supabase project: three Clue researchers (tracking model; predictions/modes/reminders/sharing; health platforms/clinical/privacy/a11y), a mobile product designer, a mobile code reviewer, and a Supabase/Postgres reviewer. Their 246 findings were merged, de-duplicated against the 104 pre-existing issues, prioritised, grouped into 13 epics, and written up by 13 issue writers. No application code, schema, migration, or doc other than this file was changed.

**Backlog delta.**

| | Count |
|---|---|
| New issues created | 120 (#151–#272, excluding #242 which the owner filed the same day) |
| New epic issues | 11 (#155, #179, #195, #214, #227, #230, #232, #261, #267, #270, #272) |
| Existing placeholders promoted to epics | 2 (#115 Clinical Export, #116 Health Platform Sync) |
| Pre-existing issues commented on | 25 (26 comments) |
| Labels created | 13 `epic:*` (existing `P0`–`P3` reused for priority) |
| Open P0 | 6 child issues + 2 epics carrying P0 |

Open issues by epic after this session (children + epic issue):

| Epic | Epic issue | P0 | P1 | P2 | P3 | Total open | New |
|---|---|---|---|---|---|---|---|
| Import | #214 | 4 | 3 | 1 | 0 | 8 | 7 |
| Tracking Model | #267 | 3 | 11 | 2 | 0 | 16 | 13 |
| Predictions & Insights | #261 | 0 | 9 | 9 | 0 | 18 | 14 |
| Modes | #232 | 0 | 3 | 3 | 0 | 6 | 5 |
| Reminders | #195 | 0 | 5 | 5 | 0 | 10 | 8 |
| Sharing | #155 | 0 | 3 | 1 | 0 | 4 | 2 |
| Health Platform Sync | #116 | 1 | 9 | 3 | 1 | 14 | 13 |
| Clinical Export | #115 | 0 | 4 | 0 | 1 | 5 | 4 |
| UI/UX | #270 | 0 | 9 | 7 | 2 | 18 | 16 |
| Mobile Hardening | #227 | 0 | 2 | 9 | 2 | 13 | 11 |
| Backend/Data | #230 | 0 | 6 | 5 | 4 | 15 | 11 |
| Privacy & Compliance | #272 | 0 | 6 | 7 | 1 | 14 | 13 |
| Accessibility & Localization | #179 | 0 | 3 | 2 | 0 | 5 | 4 |

The P0 children are #237 (unknown tag code locks an entry forever), #240 (`observations` schema direction), #190 (Clue export parser), #199 (lossless escape hatch), #167 (bulk-import RPC), and #153 (health-store profile binding). Every one of them either blocks the import path or is a data-integrity guard.

## Parity scorecard

Status of each Clue feature after checking the repo: `exists` (shipped and equivalent), `partial` (some of it exists), `missing`. Counts are of researcher findings, one per feature. "Beyond Clue" notes where lunarlog already exceeds Clue.

| Epic | exists | partial | missing | Notes |
|---|---|---|---|---|
| Import | 0 | 0 | 3 | Nothing can be read in, not even the app's own export (#140). Clue itself has no import at all, so shipping one is a differentiator. |
| Tracking Model | 1 | 12 | 30 | 17 boolean tags in 4 categories vs Clue's 40+ categories and 200+ options. No numeric values, no intensity, no custom tags, no per-profile curation. The daily note exists and is free where Clue's is Plus-only. |
| Predictions & Insights | 0 | 8 | 18 | One pure function and one text card. No history view, no statistics rendering (they are computed and discarded), no fertile window, no PMS, no confidence, no forecast beyond one date. |
| Modes | 0 | 0 | 6 | No mode concept. Clue has period-tracking, conceive, pregnancy, and perimenopause modes. |
| Reminders | 0 | 3 | 4 | Two reminder kinds at a hardcoded 09:00 vs Clue's ~9 types with editable time and text. Android 13+ never asks for notification permission on the local path (#168). |
| Sharing | beyond Clue | 0 | 1 | The guardian model (four roles, invitations, ownership transfer, caregiver alerts) has no Clue equivalent. Clue Connect's prediction-only share is missing (#151) and is a new trust boundary, not a fifth role. |
| Health Platform Sync | 0 | 1 | 35 | Zero integration; no Podfile in the repo. Clue's actual bar is one type, one way, iOS only (#193). Everything else is surplus. |
| Clinical Export | 0 | 0 | 12 | JSON dump only. Clue has no clinician export either; the PDF (#154) and FHIR bundle (#157) are differentiators. |
| UI/UX | 0 | ~10 | ~20 | No design tokens, no cycle wheel, no app shell, no empty states, four taps to log today. Five genuine advantages over Clue are invisible in the UI. |
| Mobile Hardening | n/a | 18 bugs/risks | | Calendar loads the whole history per write; no bulk write; no schema-verification harness; unpinned Flutter in CI. |
| Backend/Data | RLS sound | 4 anon-executable functions | | RLS enabled and forced on all 14 tables and the Realtime publication is correct (verified live). Import cannot pass through `sync_push`. Production has drifted from what the docs say (#163). |
| Privacy & Compliance | 2 | 4 | 9 | No-account mode and ad-free are parity. `PRIVACY.md` still promises no fertility features (#142). Tombstones keep `flow` (#224). Attachments outlive account deletion (#243). |
| Accessibility & Localization | 0 | 1 | 4 | One `Semantics` widget in the app; no localization scaffolding vs Clue's 15 languages. |

## Five biggest risks to shipping parity

1. **The import path is physically impossible through today's sync.** A ten-year Clue history is roughly 3,650 rows per profile. `sync_push` caps at 500 rows, holds a per-user advisory lock, runs about seven statements plus two AFTER triggers per row, and the `authenticated` role has a verified 8-second `statement_timeout`. A batch times out, rolls back, and the engine retries the same doomed batch. Each row also fires one `sync_signals` upsert and one caregiver-alert outbox row per subscribed guardian, so a historical import would push thousands of notifications. **Do:** land #167 (set-based `bulk_import_entries` RPC with a transaction-local GUC that silences the triggers, plus `import_jobs`), #172 (single-transaction local write), and #177 (resumable upload) before any importer ships. Do not route import through the existing push path.

2. **The schema direction is a one-way door on a live database with real rows.** Every epic depends on #240 (the `observations` child table). Production holds real family data, the deploy workflow has never run successfully, and there is no rollback story (#185) and no schema-verification harness for Drift upgrades (#200). **Do:** land #200 first, then #240 with the `tags` array kept as a deprecated mirror for one release so old clients keep syncing, and add #185's pre-push safety step to the workflow before the first production migration of this size.

3. **The Clue export format has four load-bearing unknowns.** The container (password-protected zip, `measurements.json` as a flat `{date, type, value}` array), the category list, and most enum values are attested from Clue's docs and four community parsers. The date format, the BBT value key, the entire weight encoding, and whether daily notes are present are not. Cycle boundaries are definitely absent and must be reconstructed. **Do:** obtain one real export before pinning #190's parser, and build #199's raw escape hatch regardless so an unrecognised datapoint is preserved verbatim rather than dropped.

4. **The privacy posture contradicts the roadmap and has live defects.** `PRIVACY.md` still promises no fertility tracking while #143 and #144 are queued (#142 must land first, not alongside). Separately, and independent of parity: tombstoned entries keep their `flow` on the server forever (#224), four SECURITY DEFINER functions are executable by `anon` and answer "is X a guardian of profile Y" (#158), `token_hash` is readable and redeemable on both invitation tables (#114, #242), feedback screenshots outlive account deletion (#243), and the iOS database sits in `Documents/` inside iCloud backup with the default protection class (#244). **Do:** run these as the first coding session; each is small and none depends on the schema work.

5. **HealthKit and Health Connect are single-subject per device; lunarlog is multi-profile with minors.** A naive integration writes a child's reproductive-health samples into the guardian's own Health store. That is a privacy failure, an App Review 5.1.3 problem, and a Play Health-declaration problem. **Do:** implement #153 (exactly one profile may be bound as the device owner; a guardian device never writes another person's data; minors off by default) before any type mapping, and ship the Clue-parity baseline as one small unit (#193, menstrual flow to Apple Health, one way) rather than the whole surface at once.

A sixth, lower-severity but highly visible risk: the app has no design system, no cycle wheel, and no app shell (#176, #182, #209). Parity features landed on today's UI will each look different and will not read as a competitor to Clue. Land the token layer and shell before the feature UI, not after.

## Recommended execution order

Each line is one coding session of roughly a day. The Clue-import path and the security fixes come first, as required. Issues inside a session are independent unless noted.

1. **Security and data-integrity fixes** (no schema dependency): #158, #114 + #242, #224, #237, #163, #142. Optionally #266 (auth config as code) and #189 (Deno tests for `delete-account`).
2. **Schema foundation**: #200 first, then #240, then #159 (provenance columns) and #247 (flow model: super heavy, spotting split, explicit not-bleeding). Regenerate Drift codegen; extend pgTAP.
3. **Import backend**: #167, #172, #197, #177. Verify a 5,000-row synthetic import completes end to end on local Supabase.
4. **Clue importer**: #190, #199, #257 (custom-tag registry, needed for Clue's free-text tags), then #140's import UI reused for the Clue path. Pin the four unknowns against a real export before merging #190.
5. **Taxonomy**: #249, #251, #252, #253, #255, #256, #259, #260, then #234 (category picker with search and intensity).
6. **Prediction core and modes storage**: #213, #218, #220, #221, #223, #188; then the existing #132, #133, #135, #143 consume it.
7. **UI foundation**: #176, #182, #187, #191, #198, #209, #216, #222; then #137 (dark mode), #160 (localization scaffolding), and #138 (a11y pass) on top of the token layer.
8. **Health platform sync**: #153, #156, #166, #173, #180, #186, #193, #202, #254 (store compliance). Read direction and fertility types (#217, #228, #210, #238) afterwards.
9. **Clinical export**: #152 (terminology), #154 (PDF), #157 (FHIR bundle), #248 (server-side right-of-access export). #161 (C-CDA) stays deferred.
10. **Reminders, modes, sharing, privacy hardening**: #168, #178, #183, #184, #192, #196, #204, #151, #243, #244, #263, #264, #268.

Sessions 1 through 4 are strictly ordered. Sessions 5, 6, and 7 can run in parallel worktrees once session 2 has merged. Sessions 8 and 9 depend on sessions 5 and 6.

## Open questions and assumptions

Decisions made without the owner, recorded in the relevant issues' Assumptions sections. Overturn any of them by commenting on the issue.

1. **Schema direction** (#240): a generic `observations` child table, not wide columns on `day_entries` and not a jsonb blob. Two reviewers reached this independently. The selected-option column is named `code` (the D reviewer's name) rather than `option` (the A1 researcher's name).
2. **Sensitive categories on minor profiles** (#253, #251, #210): sex life, tests, and partying exist in the data model for every profile so a Clue import is lossless, but their UI visibility on `isMinor` profiles is a per-profile setting that defaults to hidden and is controlled by the primary guardian. This is a product call; #123/#142 said fertility is available on all profiles with no restriction, and this assumption is narrower than that for the sex-life category specifically.
3. **Health sync binding** (#153): only the single profile explicitly bound as "this device's owner" may sync; minors default off; consider requiring ownership transfer to the minor's own account before a minor's profile can be bound.
4. **Clinical export is generated on-device** (#154, #157): no server-side renderer, so no Edge Function ever sees a note. Direct Epic `Observation.Create` integration was assessed and ruled out (per-health-system onboarding, not code). C-CDA (#161) is deferred unless a clinic asks.
5. **Two mode axes** (#188 vs #131): Clue's life-stage modes (tracking / conceive / pregnancy / perimenopause / postpartum) are a separate, per-profile, synced axis from #131's care modes (framing by who is reading). The `profile_modes` enum includes `conceive`, which the backend reviewer's draft omitted.
6. **Prediction parameters** (#213): 12-cycle window for predictions, 6-cycle window for displayed averages, ovulation at next-start minus 13 days, all matching Clue's documented behaviour. Confidence-tier thresholds are proposed, not validated.
7. **Custom tags are retired, never deleted** (#257): Clue's delete-destroys-history behaviour is a known complaint and is deliberately not copied.
8. **Priority labels**: the repo's existing `P0`–`P3` labels were reused rather than creating `priority:*` labels. Thirteen `epic:*` labels were created.
9. **Epic issues**: #115 and #116 were promoted to epics rather than duplicated.
10. **Weight in the Clue export**: no source documents its encoding; it routes through the raw escape hatch until a real export is inspected.
11. **Localization**: shipping English-only is acceptable for now, but the scaffolding (#160) should land before the UI grows; French is flagged as a Canadian expectation given US/Canada-only store availability.
12. **Fertility scope**: taken as relaxed on all profiles per #123 and #142. Nothing in the backlog treats it as excluded.
13. **Owner-filed #242** (ownership-transfer `token_hash`) landed during this run and overlaps the backend reviewer's comment on #114. It was labelled into the backend epic; no duplicate was created.
14. **Title prefixes vs labels**: two issues (#162, #250) carry `fix(` titles with the `enhancement` label because the writer instructions fixed the label per epic. Harmless, flagged for tidiness.
15. **Clue Plus tiering** is recorded where a source stated it but is not a parity dimension, since lunarlog has no tiering.

## Source material

The six reviewer reports, the synthesis decision record, and the issue-writer rules were produced in the session scratchpad and are not committed. Every issue cites its source finding ids (`A1-43`, `D-16`, and so on) in its Context section, and the finding text with its evidence is reproduced in the issue body, so the backlog stands on its own.

## Execution log — orchestrated coding run, 2026-09-08/09

Run under the rules: every issue in its own worktree, `in-progress` label as the claim (shared with the zcode coordinator, which paused its own dispatch during this run), review before merge, rebase onto `main` before every merge, CI green on the rebased head, squash merge. Local test runs had to be dropped mid-run because the desktop was memory-starved by orphaned `flutter_tester` processes that the session was not permitted to kill; from that point coders ran `flutter analyze` locally and CI was the gate for tests, pgTAP, and the quality gate.

### Merged (issue → PR)

| Issue | PR | What landed |
|---|---|---|
| #237 (P0) | #279 | Unknown tag codes preserved instead of locking an entry forever |
| #163 | #280 | `push-dispatch` in the deploy step; drift and advisor gates (gates run last, advisors fail on `error` until #158/#194/leaked-password land) |
| #200 | #283 | Drift `SchemaVerifier` harness v1→v5, codegen-freshness CI step; index re-assert gap fixed |
| #158 | #281 | `anon` EXECUTE revoked on four SECURITY DEFINER functions; catalog guard in pgTAP; migration `20260908121000` |
| #177 | #289 | Streaming push in bounded batches, resumable across pauses, profiles paged every round, bounded reads pinned by test |
| #243 | #282 | Attachment cleanup before row deletion (paginated, recursive, fail-closed), explicit ticket deletion, client mapping; migration `20260908130000` |
| #156 | #294 | Podfile + lock from a real `pod install`, HealthKit entitlements and usage strings; human step: regenerate the provisioning profile |
| #224 | #285 | Tombstones clear `flow` in `sync_push` (rebuilt on the care-modes body), all four client paths, backfill + CHECK; migration `20260908140000` |
| #168 | #284 | Android 13+ notification permission requested; denial count persisted; startup prompt inside the system-UI window; Darwin settings fallback |
| #248 | #291 | `export_account_data()` right-of-access RPC scoped to RLS, no secrets, 69 pgTAP assertions; an `invited_by` UID exposure found and fixed during rebase; migration `20260908150000` |

Awaiting CI at the time of writing: #286 (issue #244, iOS DB relocation out of iCloud backup — three review rounds; round 2 had introduced a fresh-install wipe that round 3 removed and pinned) and #293 (issue #153, the P0 health-store binding guard — write-side guard now reads the stored binding itself). In progress: #240 (P0 `observations` schema), #213 (prediction engine v2), #176 (design tokens).

### Filed as discoveries (never fixed in passing)

#287 FCM and local paths both request `POST_NOTIFICATIONS`; #288 AGENTS.md per-file pgTAP counts drift; #290 `_hasPushableDirty` materialises the dirty set; #292 `public.settings` absent from the right-of-access export; #295 whether `isMinor` should stay guardian-editable (product decision, `needs-human-review`); #296 prerequisites before `healthSyncMinorBindingAllowed` may be flipped.

### Needs a human

- #156: regenerate the App Store provisioning profile with the HealthKit capability before the next signed release (signing fails until then).
- #244: device verification on the Mac after #286 merges (backup exclusion, protection class, relocation of a pre-#244 install).
- #295: the `isMinor` decision.
- #163: the first production run of the amended `supabase-migrate.yml` needs the required reviewer, and the `FCM_*`/`PUSH_DISPATCH_WEBHOOK_SECRET` environment secrets.
- Process: a permission rule allowing `Stop-Process` on `flutter_tester.exe`/`dart.exe` would let a future run shed load instead of degrading to CI-only verification.

### Lessons recorded

- Every migration PR edits the same two AGENTS.md sentences (schema paragraph, pgTAP total), so each merge conflicts the next; the resolution is mechanical and was scripted mid-run. A structural fix is tracked in #288.
- Migration timestamps must be assigned by the orchestrator at dispatch time: four in-flight PRs independently picked `20260908120000`.
- Squash-merge a PR's fix-up commits before rebasing; multi-commit branches conflict once per commit.
- Concurrent `flutter test --coverage` runs from several coders exhaust a 32 GB desktop; serialise gates or push them to CI.

### Update — later in the same run

Additional merges (issue → PR): #244 → #286 (iOS DB relocated to Application Support with crash-safe staging, `NSURLIsExcludedFromBackupKey` + `NSFileProtectionComplete` on the file and directory, Android extraction rules incl. staging files; a round-2 regression that would have wiped fresh installs on their second launch was caught in re-review and removed); #153 → #293 (the P0 health-sync guard: write-side checks read the stored device binding themselves; minor gate consults transfer state and birth year; single `AppConfig` flip point, `false`); #166 → #301 (`minSdk 26`, Health Connect permissions for the menstruation baseline, rationale activity, Android 14 permission-usage alias, Play declaration checklist); #176 → #298 (design-token layer: spacing/radius/type ramp, `LunarLogColors` ThemeExtension with contrast-solved roles, one theme factory for all three `MaterialApp`s, dark theme built but deliberately unwired until #137).

In review or CI at the time of writing: #299 (issue #213, prediction engine v2 — 12/6 windows, confidence tiers, forecast; two review rounds plus a complexity split; the history card's average window was found to slice the oldest cycles and was fixed), #305 (issue #222, "Your data" section — export reachable without an account; the docs' claim that export was device-credential-gated was found to be false since #17 and corrected), #302 (issue #240, the P0 `observations` table — review confirmed the 3-argument `sync_push` with a default is safe for shipped clients; fix-up in progress for an honest export document, redacted tombstones, cap on the revive path, restored `sync_push` comments, and the Realtime guard).

Further discoveries filed: #300 (calendar forecast must consume `ActivePrediction.forecast`), #303 (`flow_level` SQL domain instead of three duplicated enum lists), #304 (injected `todayProvider` was silently ignored by two widgets — audit clock seams).

Further human steps: #240 deploy pre-flight (check `day_entries` for duplicate ids before the new unique constraint; verify one live 2-argument `sync_push` call resolves after deploy; zcode's staged wave must rebase onto #302 and use the 3-argument signature); #166 Play Console Health apps declaration; #176 two design choices (mid-dark "spotting" tone, isoluminant badges) recorded for an owner pass.

### Update — second wave, 2026-09-09

Merged (issue → PR): #299 → issue #213 and #305 → issue #222 (both noted above as in review); #187 → #307 (`EmptyState`/`InlineError` components with live-region announcements; the export-failure copy was ported into the new "Your data" section during the rebase); #221 → #309 (days-late count, estimate rolled forward once late, the >60-day open cycle no longer goes silent; review caught that the rolled date was being published to the server's missed-entry gate, which would have silenced caregiver alerts for most of every cycle — fixed to publish the original estimate); #182 → #310 (app shell: bottom navigation Today/Calendar/Insights/More, named routes, visible sync glyph, offline-save confirmation; the Insights placeholder was made honest and a whole-shell rebuild per sync tick removed before merge); #191 → #311 (flow-graded calendar cells from the token ramp with a dot-count non-colour channel, legend, swipe navigation, Today button, month/year picker; one legend swatch was keying a different token than the mark it explained); #240 → #302 (the P0 `observations` table, four review rounds: honest export at schema v3 through a real `ObservationsRepository`, tombstones cleared of `category`, cap and dedup on the revive and date-move paths, `sync_push` and `delete_account_data()` rationale comments restored, Realtime guard extended, JSON-null `raw`, byte-bounded `raw`, backfill signal storm suppressed; three CRAP-gate splits).

In review or CI at the time of writing: #315 (issue #223, Analysis content on the Insights tab — review found a viewer-role write path and two disagreeing statistics on one screen; fix-up in progress), #316 (issue #209, Today card, cycle wheel, one-tap "period started today", shell FAB — in review).

Dispatched on the post-#302 main: #190 (Clue export parser and mapping spec), #159 (import provenance columns, migration `20260908170000`).

Further discoveries and follow-ups filed: #308 (EmptyState/InlineError follow-ups: label pin, heading semantics, scroll safety, overview title style), #312 (calendar follow-ups: today ring on bleed days, legend coverage, large-text budget, fling-bound test), #313 (app shell follow-ups: Android back to Today, three unnamed sharing routes, Activity Feed reachability, tab-switch seam), #314 (remove the cycle-history card from Overview once the Analysis tab mounts it).

Further human steps: #221 carries three product questions from review (roll aggressiveness — a full mean-cycle step at three days late; whether the server-side missed-entry gate should track the original or the rolled date; the irregular-mode exception to "N days late"); #240's deploy pre-flight is restated on the closed issue.

Lessons added this wave: never resolve a rebase conflict with `git checkout --ours <file>` (it takes the whole upstream file and silently drops the branch's other hunks — cost one CI cycle on #307); a CI wait armed before a force-push can report the previous head's failure, so re-arm the wait after every push; the CRAP gate counts each `?:`, so a record-building helper with ten ternaries scores 11 even at full coverage — split into a cleared constant and a live builder.
