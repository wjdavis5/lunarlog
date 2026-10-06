# Implementation Plan: Fix Health Connect and HealthKit Write Permissions (#1555)

## Goal
On Android and iOS, allow health sync to continue writing authorized data types when one or more write permissions are turned off, instead of treating any single disabled write permission as an all-or-nothing denial that stops every write.

## Files to Touch
1. `android/app/src/main/kotlin/com/wjdavis5/lunarlog/HealthConnectAdapter.kt`:
   - Update `HealthPermissionState` to define `WRITING_SOME = "writingSome"` and have `writeStatusFor` return `WRITING_SOME` when at least one write permission is granted (while retaining `GRANTED` when all are granted, `DENIED` when 0 are granted and asked, and `NOT_ASKED` when 0 are granted and not asked).
   - Add the channel handler for `"grantedWriteTypes"` to return the list of granted write type wire names (`menstrualFlow`, `spotting`, `cervicalMucus`, `ovulationTest`, `basalBodyTemperature`).
   - In `deleteRecords`, catch `SecurityException` per record type so that a missing permission for one record type does not abort deletions for the remaining types.
2. `android/app/src/test/kotlin/com/wjdavis5/lunarlog/HealthPermissionStateTest.kt`:
   - Update unit tests for `writeStatusFor` to verify `writingSome` when any subset of write permissions is granted.
3. `ios/Runner/AppDelegate.swift`:
   - Update `permissionStatus` to return `writingSome` when at least one sample type is authorized and some are denied/undetermined.
   - Add the `"grantedWriteTypes"` case to return the list of authorized write types.
   - In `deleteRecords`, query and delete only for sample types where `store.authorizationStatus(for: sampleType) == .sharingAuthorized`.
   - In `writeSymptomSamples`, filter `toSave` samples to only those where `store.authorizationStatus(for: categoryType) == .sharingAuthorized`.
4. `lib/domain/health/health_platform.dart`:
   - Add `HealthPermissionStatus.writingSome`.
   - Add `Future<Set<String>> grantedWriteTypes();` to `HealthPermissionProbe` and `HealthPlatformStore`.
5. `lib/data/health/health_channel_codec.dart`:
   - Document `"grantedWriteTypes"` and add `HealthChannelMethods.grantedWriteTypes`.
6. `lib/data/health/health_channel.dart`:
   - Implement `grantedWriteTypes()` on `MethodChannelHealthPlatformStore`.
7. `lib/domain/health/health_access_state.dart`:
   - Add `HealthAccessState.writingSome`.
   - Update `changedInSettings` to include `writingSome`.
   - Update `healthAccessState()` to return `writingSome` when `write == HealthPermissionStatus.writingSome`.
8. `lib/data/health/health_flow_write_service.dart`:
   - Treat `HealthPermissionStatus.writingSome` as allowed in the pre-flight check and cursor initialization.
   - Query `grantedWriteTypes()` and skip records whose write permission is off, without failing the pass or holding back the cursor.
   - Ensure `MenstruationPeriodRecord` is skipped if `menstrualFlow` is off.
9. `lib/l10n/app_en.arb`:
   - Add `healthSyncPermissionWritingSome` string.
10. `lib/ui/settings/health_sync_screen.dart`:
    - Display `healthSyncPermissionWritingSome` naming the disabled types with an "Open Settings" link.
11. `test/release/health_deletion_types_test.dart`, `test/domain/health/health_access_state_test.dart`, `test/data/health/health_flow_write_service_test.dart`, `test/ui/health_sync_screen_test.dart`:
    - Add and update tests covering all new behaviors.

## Implementation Steps
1. Native layer updates (Kotlin & Swift):
   - Add `WRITING_SOME` to `HealthPermissionState` and update `writeStatusFor`.
   - Add `grantedWriteTypes` method channel handler in `HealthConnectAdapter.kt` and `AppDelegate.swift`.
   - Guard `deleteRecords` and `writeSymptomSamples` against unauthorized types.
2. Platform & Domain definitions:
   - Add `writingSome` to `HealthPermissionStatus` and `HealthAccessState`.
   - Add `grantedWriteTypes` to `HealthPermissionProbe` and `HealthPlatformStore`.
3. Health flow write service:
   - Query `grantedWriteTypes()` on each pass.
   - Skip unpermitted records gracefully so `outcome.failure` remains null.
4. L10n & UI:
   - Add localization and status display for `HealthAccessState.writingSome`.
5. Run code generation and tests:
   - `flutter gen-l10n`.
   - `flutter test` across all affected test files.

## Verification
- `flutter test test/release/health_deletion_types_test.dart`
- `flutter test test/domain/health/health_access_state_test.dart`
- `flutter test test/data/health/health_flow_write_service_test.dart`
- `flutter test test/ui/health_sync_screen_test.dart`
- `flutter analyze`
