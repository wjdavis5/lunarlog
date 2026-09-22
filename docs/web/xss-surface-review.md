# XSS surface review

**Status:** decision record, slice 5 of epic #831. The owner's decision
comment lists an "XSS surface review of every place the app renders
user-authored text (notes, profile names, guardian nicknames, tag labels,
feedback bodies)" as item 1 of the order of work, and `docs/web/security-posture.md`
§6 explicitly deferred it. This document discharges that review. Its
conclusion is that the app has **no HTML-parsing path**: every
user-authored string is rendered through Flutter's own text pipeline, so the
XSS risk is confined to the handful of places that deliberately leave that
pipeline, and those are enumerated and pinned below.

**Method.** Everything here is read from the code at the commit this lands
on; no browser was run and no external documentation was consulted. The
permanent guard is `test/architecture/web_dom_surface_test.dart`, which fails
the build if a new raw-DOM import, raw-HTML sink, or un-gated `launchUrl`
call appears in `lib/`. When that test fails, re-run this review.

---

## 1. How text reaches the DOM on Flutter web

There is no HTML renderer in the shipped build, and there is no HTML string
to render even if there were:

- **The build selects no renderer.** `.github/workflows/ci.yml:397` and
  `.github/workflows/web-deploy.yml:93` both run a plain
  `flutter build web --release` — no `--web-renderer`, no `--wasm`. On the
  Flutter 3.47 line this repo pins (`AGENTS.md`), the HTML renderer no longer
  exists as an option and the engine default (CanvasKit) is what ships.
  `web/index.html:44` loads the generated `flutter_bootstrap.js` with no
  renderer configuration either.
- **A Flutter `Text` never interprets markup.** It takes a Dart `String` and
  lays out glyphs; `<script>`, `&amp;`, and `javascript:` are literal
  characters. The one text-adjacent DOM surface — the accessibility/semantics
  tree — is written by the engine with DOM APIs that set text content, not
  `innerHTML`; the architecture test forbids the latter from `lib/`
  regardless.
- **The CSP is the second layer.** `web/_headers:27` deploys
  `script-src 'self' 'wasm-unsafe-eval'`, `object-src 'none'`,
  `base-uri 'self'`, and `frame-ancestors 'none'`, so even a hypothetical
  injected string could not become executable script.

**Consequence:** the review reduces to "does any code path turn a
user-authored value into HTML or hand it to the browser DOM?" The answer is
no; the two places that touch the DOM/URL launcher are in Section 3. The
surfaces in Section 2 all end in a `Text`/`SelectableText`/`TextField`.

## 2. Every place user-authored text is rendered

Every row below terminates in a Flutter text widget. None is a raw-DOM path,
so each verdict is **safe**. Citations are `file:line` at this commit.

### 2.1 Day notes (`day_entries.note`)

| Where | Render site |
| :--- | :--- |
| Editable field | `lib/ui/logging/day_sheet.dart:686` (`TextEditingController(text: existing?.note ?? '')`) |
| Read-only body | `lib/ui/logging/day_sheet.dart:2993` |
| Same-date merge "lost value" disclosure | `lib/ui/logging/widgets/merge_notice_section.dart:200` (value selected at `:129`) |
| Calendar presence flag (no text) | `lib/ui/logging/month_calendar.dart:449`, `:2631` |

### 2.2 Guardian notes (`guardian_notes.body`)

| Where | Render site |
| :--- | :--- |
| Author line + body | `lib/ui/care/guardian_notes_section.dart:287` and `:290` |
| Editable field | `lib/ui/care/guardian_notes_section.dart:114` |
| Read-only day-sheet slot | `lib/ui/logging/day_sheet.dart:2999` |

### 2.3 Profile display names (`profiles.display_name`)

| Where | Render site |
| :--- | :--- |
| Profile card | `lib/ui/components/profile_card.dart:369` |
| App shell switcher | `lib/ui/components/app_shell.dart:604`, `:614`, `:711`, `:735` |
| Profile picker / household prompt | `lib/ui/profiles/profile_picker_screen.dart:161`, `:295` |
| Profile detail title | `lib/ui/profiles/profile_detail_screen.dart:111` |
| Interpolated into localized copy | `lib/ui/sharing/manage_guardians_screen.dart:381`, `:588`, `:599`, `:978`; `lib/ui/sharing/transfer_ownership_screen.dart:333`, `:371`, `:482`, `:527`; `lib/ui/settings/your_data_section.dart:588` |

Interpolating a name into an ARB string does not change the sink: the result
is still a Dart `String` passed to `Text`.

### 2.4 Guardian nicknames (`profile_guardians.display_name`)

The name a guardian chose (invite acceptance, `accept_invite_sheet.dart:94`,
or their account display name), resolved for display:

| Where | Render site |
| :--- | :--- |
| Manage-guardians tile + role-change/removal dialogs | `lib/ui/sharing/manage_guardians_screen.dart:591`, `:637`, `:1489` |
| Day-entry attribution badge | `lib/ui/logging/widgets/caregiver_attribution_badge.dart:41` |
| Merge-notice sentence | `lib/ui/logging/widgets/merge_notice_section.dart:72` |
| Activity-feed actor | `lib/ui/l10n/activity_actor_copy.dart:32`; `lib/ui/sharing/activity_feed_screen.dart:253`, `:313`, `:332` |
| Care-note attribution | `lib/ui/care/care_notes_screen.dart:428`, `:583`, `:761` |
| Household signals | `lib/ui/overview/household_signals.dart:390` (text from `householdChangesLine`, which uses `activityActorLabel`) |

### 2.5 Relationship labels (closed set, not user-authored)

`lib/domain/models/profile_relationship.dart:45` is a fixed enum; it is
labelled, never free text. Rendered at
`lib/ui/profiles/first_run_screen.dart:1067` and
`lib/ui/profiles/profile_dialogs.dart:774`. **Safe** (constant vocabulary,
but listed because the issue names it).

### 2.6 Custom tag labels (`profile_tag_registry.display_name`)

| Where | Render site |
| :--- | :--- |
| Tag manager list, rename sheet, retire confirm | `lib/ui/logging/widgets/custom_tag_manager_sheet.dart:247`, `:305`, `:352` |
| Logging chips (offered + retired) | `lib/ui/logging/day_sheet.dart:2475`, `:2801`, `:2983` (resolved by `_displayOf`, `:562`) |
| Category picker list/filter/chip | `lib/ui/components/category_picker.dart:397`, `:484`, `:490` |

### 2.7 Feedback ticket bodies and replies

| Where | Render site |
| :--- | :--- |
| Ticket body (first line) | `lib/ui/feedback/support_history_screen.dart:190` |
| Reply body | `lib/ui/feedback/support_history_screen.dart:223` |
| Reply author label (closed enum) | `lib/ui/feedback/support_history_screen.dart:222` |
| Ticket body input | `lib/ui/feedback/feedback_screen.dart:196` |

### 2.8 Invite previews and invite links

| Where | Render site |
| :--- | :--- |
| Accept-invite preview (profile name + role into localized copy) | `lib/ui/sharing/accept_invite_sheet.dart:139`, `:146` |
| Invite link (app-built `Uri`) | `lib/ui/sharing/invite_guardian_dialog.dart:280` |
| Prediction-connection link (app-built `Uri`) | `lib/ui/sharing/share_predictions_dialog.dart:122` |
| Ownership-transfer link (app-built `Uri`) | `lib/ui/sharing/transfer_ownership_screen.dart:536` |

The links are built by `buildInviteLink` (`lib/domain/sharing/invite_links.dart:102`)
from an app-generated code and configured domain; the user-supplied part is
the guardian display name, which never enters a URL. They are displayed as
`SelectableText`, never navigated to.

### 2.9 Import source labels and import errors

| Where | Render site |
| :--- | :--- |
| Source dropdown + preview (closed enum) | `lib/ui/settings/your_data_section.dart:657`, `:664` (labels defined at `lib/domain/profiles/profile_erasure_service.dart:117`) |
| Imported profile name + skip reason | `lib/ui/settings/import_screen.dart:534`, `:636` |
| Clue summary lines (app-built counts) | `lib/ui/settings/import_screen.dart:606`, `:646` |

### 2.10 Care notes and supplies items (`care_notes.body` / `visit_prep_items.body`)

| Where | Render site |
| :--- | :--- |
| Care-note body | `lib/ui/care/care_notes_screen.dart:571` |
| Visit-prep / supplies item body | `lib/ui/care/care_notes_screen.dart:758` |
| Restock nudge joins item bodies | `lib/ui/care/care_notes_screen.dart:914` |

### 2.11 Custom reminder title/body (also user-authored, added for completeness)

`lib/ui/settings/reminder_text_editor_screen.dart:241` and `:249` render the
operator's custom reminder title and body; the same strings are stored and
later pushed as notification content, never as HTML.

### 2.12 Error and session strings

`lib/ui/startup/fail_closed_screen.dart:104` (`SelectableText(error.toString())`)
and `lib/ui/account/restore_error_screen.dart:60`, `:72` render exception
text. These are Dart `String`s from typed failures or a scrubbed error, and
even a server-influenced message is rendered as literal characters.

## 3. Raw-DOM touch points

These are the only places in `lib/` that leave the Flutter text pipeline, with
their verdicts:

| Touch point | Location | Verdict |
| :--- | :--- | :--- |
| `package:web` (only direct browser-DOM import in `lib/`) | `lib/data/auth/web_url_cleaner_web.dart:10`, called at `:15` | **Safe.** `window.history.replaceState` only — no HTML, no user text; the URI is built by the app's pure `cleanAuthUrl`. Reached only through the `dart.library.js_interop` conditional import at `lib/data/auth/web_url_cleaner.dart:14`, so native never compiles it. Allowlisted in the architecture test. |
| `url_launcher` | `lib/ui/gate/device_settings_launcher.dart:21` | **Safe, now gated.** The only launch site routes through `safeLaunchUrl` (`lib/ui/components/safe_launch_url.dart:51`), which refuses any scheme outside an explicit allowlist before calling the platform. Device settings pass the fixed `app-settings`/`intent` set (`device_settings_launcher.dart:36`); the default set is `http`/`https`/`mailto`/`tel`. No user-authored URL reaches it. |
| `Uri.parse` of user text | `lib/data/db/web_db.dart:19`–`:20`; `lib/ui/gate/device_settings_launcher.dart:114`, `:139`, `:148`; `lib/domain/sharing/invite_links.dart:139` | **Not an XSS path.** Every `Uri.parse` argument is an app constant (`sqlite3.wasm`, `drift_worker.js`, the settings schemes) except the invite-link parser, which reads `Uri.queryParameters` from an incoming deep link and only extracts `code`/`profile`/`kind` — it never navigates, renders markup, or launches. |
| `HtmlElementView`, `innerHTML`, `setInnerHtml`, `dangerouslySetInnerHTML` | none | **Absent.** Pinned by the architecture test. |
| Markdown / HTML-rendering / WebView packages | none in `pubspec.yaml` (the only web-facing dependency is `url_launcher: ^6.3.0`, `pubspec.yaml:83`) | **Absent.** There is no `flutter_html`, `flutter_markdown`, `webview_flutter`, or `Image.network` on user text. |
| `Image.network` / remote images | none (MFA enrol build a local SVG data URI; `lib/domain/auth/mfa.dart:33`) | **Safe / not reachable.** No remote image is fetched or rendered. |

## 4. Residual list (out of scope for this review)

- **The engine and third-party packages are trusted, not audited.**
  `package:web`, `url_launcher`/`url_launcher_web`, CanvasKit/skwasm,
  `sqlite3.wasm`, and `drift_worker.js` are reviewed only at their call
  boundary. A vulnerability inside one of them is out of this doc's scope;
  this is the same deferral §6 records as a dedicated engine/dependency
  penetration test.
- **The semantics DOM is not audited.** Flutter's accessibility layer may
  write text into DOM nodes with text-content APIs; this review confirms the
  app never supplies HTML to it, not the engine's internal implementation.
- **The scheme allowlist is not a host allowlist.** `safeLaunchUrl` accepts
  any `https:`/`mailto:`/`tel:` URL; today no user-authored URL reaches it,
  but a future feature that launches a user-supplied link should add host
  validation on top.
- **No live-browser verification.** These are static facts, not a
  browser-driven penetration test; the hosting slice owns the first
  real-origin exercise, as §6 already notes for the URL cleanup.
- **The test pins shape, not behaviour.** `web_dom_surface_test.dart` is a
  source-text scan; it cannot prove a renderer. A new HTML-rendering
  dependency or `HtmlElementView` would fail it, which is the tripwire that
  forces a re-run of this review.

## 5. References

- Epic #831 decision comment — "an XSS surface review of every place the app
  renders user-authored text".
- `docs/web/security-posture.md` — the web threat model this review sits
  under; §2's "XSS becomes a total compromise" is the risk this document
  bounds.
- `test/architecture/web_dom_surface_test.dart` — the tripwire that keeps
  the conclusions here true.
- `lib/ui/components/safe_launch_url.dart` — the scheme gate.
- `web/_headers` — the CSP that is the second layer.
