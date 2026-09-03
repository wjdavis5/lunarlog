---
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-ready
product_contract_source: ce-plan
execution: code
---

# Fix(Data): Resolve Timezone Name Format Contract Mismatch in Day Entries (Issue #46)

## Goal Capsule

- **Objective:** Fix the contract mismatch where `DaySheet` writes platform timezone abbreviations (e.g. `'EST'`, `'EDT'`, `'GMT+10'`) via `DateTime.now().timeZoneName` into the `day_entries.tz` column, violating the Drift schema contract and documentation specifying canonical IANA timezone names (e.g. `'America/New_York'`).
- **Means:** Introduce a domain timezone resolution helper (`lib/domain/util/timezone.dart`) backed by `package:timezone`, provide an injectable `timezoneProvider` seam across `DaySheet`, `MonthCalendar`, and `ProfileDetailScreen`, guard timezone initialization against re-initialization reset, and add unit/widget tests verifying IANA timezone formatting on day entry writes.
- **Authority Hierarchy:**
  1. User Directive / GitHub Issue #46: Resolve timezone name format contract mismatch in day entries; pair with #38 timezone resolution; update unit tests.
  2. AGENTS.md: Worktree isolation (`.worktrees/`), clean layer separation (UI does not import `lib/data`), 90% coverage floor, CRAP gate <= 10.
  3. Finding #23 in Issue #37: Write the resolved IANA zone rather than platform abbreviations.
- **Stop Conditions:** All tests green (`flutter test`), `flutter analyze` clean, `dart run tool/quality_gate.dart` passing (coverage >= 90%, CRAP <= 10), changes reviewed and committed.

## Product Contract

### Context & Problem Statement
In `lib/ui/logging/day_sheet.dart:91`, `DayEntry` is created with:
```dart
tz: DateTime.now().timeZoneName,
```
In Dart on desktop/mobile/web, `DateTime.now().timeZoneName` yields platform abbreviations such as `'EST'`, `'EDT'`, `'CST'`, `'CDT'`, `'PST'`, `'PDT'`, `'GMT+10'`.
However, the Drift schema (`lib/data/db/tables.dart:84`) and `DayEntry` domain model (`lib/domain/models/day_entry.dart:33`) explicitly specify:
```dart
/// IANA time zone name the [localDate] was recorded in.
TextColumn get tz => text()();
```
Writing platform abbreviations produces ambiguous offsets across devices during sync (e.g., 'CST' is Central Standard Time in the US, China Standard Time, or Cuba Standard Time).

### Requirements
- **R1:** `DaySheet` must populate `tz` with a resolved canonical IANA timezone identifier (e.g. `'America/New_York'`, `'America/Chicago'`, `'Etc/UTC'`), paired with `package:timezone`'s `tz.local` (which is configured by timezone resolution in #38).
- **R2:** Provide an injectable `timezoneProvider` seam (`String Function()?`) on `DaySheet`, `MonthCalendar`, and `ProfileDetailScreen` (defaulting to `resolveCurrentTimeZone`), consistent with the existing `todayProvider` pattern.
- **R3:** Guard `tzdata.initializeTimeZones()` so that subsequent calls do not wipe or reset `tz.local` if it was already configured.
- **R4:** Add unit tests for `resolveCurrentTimeZone()` and `isValidIanaTimeZone()`.
- **R5:** Update unit/widget tests in `test/ui/logging_test.dart` to verify that saving a day entry persists a canonical IANA timezone name and respects the injected seam.

## Planning Contract

### Technical Design

1. **Domain Timezone Helper (`lib/domain/util/timezone.dart`)**:
   - `String resolveCurrentTimeZone()`:
     - Checks `if (tz.timeZoneDatabase.locations.isEmpty) tzdata.initializeTimeZones();`
     - Returns `tz.local.name`.
   - `bool isValidIanaTimeZone(String tzName)`:
     - Checks `if (tz.timeZoneDatabase.locations.isEmpty) tzdata.initializeTimeZones();`
     - Returns `tz.timeZoneDatabase.locations.containsKey(tzName)`.

2. **UI Seam (`DaySheet`, `MonthCalendar`, `ProfileDetailScreen`)**:
   - `DaySheet`:
     - Constructor parameter: `final String Function()? timezoneProvider;`
     - In `_save()`: `final tz = (widget.timezoneProvider ?? resolveCurrentTimeZone)();`
   - `MonthCalendar`:
     - Constructor parameter: `final String Function()? timezoneProvider;`
     - Forwarded to `DaySheet` in `_openDay()`.
   - `ProfileDetailScreen`:
     - Constructor parameter: `final String Function()? timezoneProvider;`
     - Forwarded to `MonthCalendar` in `build()`.

3. **Notification Scheduler Idempotency (`lib/data/notifications/notification_scheduler.dart`)**:
   - In `initialize()`:
     ```dart
     if (tz.timeZoneDatabase.locations.isEmpty) {
       tzdata.initializeTimeZones();
     }
     ```
     This prevents `tzdata.initializeTimeZones()` from resetting `tz.local` back to `Etc/UTC` if `tz.setLocalLocation` was already set.

4. **Testing**:
   - `test/domain/timezone_test.dart`:
     - Test `resolveCurrentTimeZone()` default return is canonical IANA (`Etc/UTC`).
     - Test `tz.setLocalLocation(...)` changes `resolveCurrentTimeZone()`.
     - Test `isValidIanaTimeZone()` accepts canonical names (`America/New_York`, `UTC`, `Etc/UTC`) and rejects abbreviations (`EDT`, `EST`, `PDT`, `GMT+10`).
   - `test/ui/logging_test.dart`:
     - Assert `saved!.tz` in existing save test is a valid IANA timezone.
     - Add explicit test with injected `timezoneProvider: () => 'America/New_York'` verifying saved `tz`.

## Implementation Tasks

- [ ] Task 1: Create `lib/domain/util/timezone.dart` with `resolveCurrentTimeZone` and `isValidIanaTimeZone`.
- [ ] Task 2: Update `lib/data/notifications/notification_scheduler.dart` to make `initializeTimeZones` call conditional on `locations.isEmpty`.
- [ ] Task 3: Update `DaySheet` in `lib/ui/logging/day_sheet.dart` to use `resolveCurrentTimeZone` and support `timezoneProvider`.
- [ ] Task 4: Thread `timezoneProvider` through `MonthCalendar` (`lib/ui/logging/month_calendar.dart`) and `ProfileDetailScreen` (`lib/ui/profiles/profile_detail_screen.dart`).
- [ ] Task 5: Add tests in `test/domain/timezone_test.dart` and update `test/ui/logging_test.dart`.
- [ ] Task 6: Run `flutter analyze`, `flutter test`, and `dart run tool/quality_gate.dart`.
