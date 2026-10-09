/// Widget tests for [HealthSyncScreen] (Issue #153) — exercised directly,
/// bypassing `SettingsScreen`'s `AppConfig.hasHealthSync` gate, per that
/// flag's "ships dormant but testable" doc comment. Uses a real
/// [HealthSyncBinding] backed by [FakeSettingsStore] (the actual invariant
/// logic under test), a plain in-memory [FakeProfilesRepository], and a
/// bare async function for guardian rows — no database required.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/health/health_channel.dart';
import 'package:lunarlog/domain/health/health_import.dart';
import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/domain/health/health_sync_binding.dart';
import 'package:lunarlog/domain/health/health_sync_policy.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/models/profile_relationship.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/l10n/app_localizations_en.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/domain/logging/tracking_preferences.dart';
import 'package:lunarlog/domain/models/measurement_unit.dart';
import 'package:lunarlog/ui/components/destructive_button.dart';
import 'package:lunarlog/ui/settings/health_sync_screen.dart';

import '../support/fake_settings_store.dart';

class FakeProfilesRepository implements ProfilesRepository {
  FakeProfilesRepository(this.profiles);

  final List<Profile> profiles;

  @override
  Future<Profile> create({
    required String displayName,
    required bool isMinor,
    int sortOrder = 0,
    ProfileMode mode = ProfileMode.standard,
    bool? irregularFraming,
    int? birthYear,
    ProfileRelationship? relationship,
    LocalDate? lastPeriodStart,
    int? typicalCycleLengthDays,
    int? typicalPeriodLengthDays,
    BbtUnit bbtUnit = BbtUnit.celsius,
    WeightUnit weightUnit = WeightUnit.kg,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> delete(String id) => throw UnimplementedError();

  @override
  Future<Profile?> setTrackingPreferences(
          String id, TrackingPreferences? preferences) =>
      throw UnimplementedError();

  @override
  Future<Profile?> findById(String id) async {
    for (final profile in profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  @override
  Future<List<Profile>> list() async => profiles;

  @override
  Future<void> setArchived(String id, bool archived) =>
      throw UnimplementedError();

  @override
  Future<Profile> update(Profile profile) => throw UnimplementedError();

  @override
  Stream<List<Profile>> watch() => Stream.value(profiles);

  @override
  Future<void> applyServerPurge(String id) => throw UnimplementedError();
}

/// A repository whose `list()` always throws — exercises `_load()`'s
/// `catchError` handling (review fix): the loading spinner must resolve
/// instead of spinning forever.
/// Counts how often the screen reads the profile list, which it does
/// once for each time it loads.
class CountingProfilesRepository extends FakeProfilesRepository {
  CountingProfilesRepository(super.profiles);

  int lists = 0;

  @override
  Future<List<Profile>> list() {
    lists++;
    return super.list();
  }
}

class ThrowingProfilesRepository implements ProfilesRepository {
  @override
  Future<Profile> create({
    required String displayName,
    required bool isMinor,
    int sortOrder = 0,
    ProfileMode mode = ProfileMode.standard,
    bool? irregularFraming,
    int? birthYear,
    ProfileRelationship? relationship,
    LocalDate? lastPeriodStart,
    int? typicalCycleLengthDays,
    int? typicalPeriodLengthDays,
    BbtUnit bbtUnit = BbtUnit.celsius,
    WeightUnit weightUnit = WeightUnit.kg,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> delete(String id) => throw UnimplementedError();

  @override
  Future<Profile?> setTrackingPreferences(
          String id, TrackingPreferences? preferences) =>
      throw UnimplementedError();

  @override
  Future<Profile?> findById(String id) => throw UnimplementedError();

  @override
  Future<List<Profile>> list() async =>
      throw StateError('boom: repository unavailable');

  @override
  Future<void> setArchived(String id, bool archived) =>
      throw UnimplementedError();

  @override
  Future<Profile> update(Profile profile) => throw UnimplementedError();

  @override
  Stream<List<Profile>> watch() => throw UnimplementedError();

  @override
  Future<void> applyServerPurge(String id) => throw UnimplementedError();
}

/// A binding whose `canBind` always allows but whose `bind` always denies
/// — simulates eligibility changing out from under the operator between
/// this screen's last load and the confirm dialog closing (e.g. another
/// device changed the binding or this profile's ownership mid-flow), so
/// the "surface bind()'s deny reason" code path (review fix) can be
/// exercised deterministically.
class _AlwaysAllowThenDenyBinding extends HealthSyncBinding {
  _AlwaysAllowThenDenyBinding(super.settings);

  @override
  HealthSyncCheck canBind({
    required Profile profile,
    required String? signedInUserId,
    required String? ownerUserId,
    required bool minorBindingAllowed,
  }) =>
      HealthSyncCheck.allowed;

  @override
  Future<HealthSyncCheck> bind({
    required Profile profile,
    required String? signedInUserId,
    required String? ownerUserId,
    required bool minorBindingAllowed,
  }) async =>
      HealthSyncCheck.notOwner;
}

Profile _profile({
  required String id,
  required String name,
  bool isMinor = false,
  DateTime? archivedAt,
}) =>
    Profile(
      id: id,
      displayName: name,
      isMinor: isMinor,
      archivedAt: archivedAt,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

ProfileGuardian _owner(String profileId, String userId) => ProfileGuardian(
      id: 'g-$profileId',
      profileId: profileId,
      userId: userId,
      role: GuardianRole.primaryGuardian,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// A programmable [HealthImportRunner] for the #217/#458 UI states.
class _FakeImporter implements HealthImportRunner {
  _FakeImporter(this.summary, {this.platform = HealthImportPlatform.appleHealth});

  HealthImportSummary summary;

  @override
  final HealthImportPlatform platform;
  int calls = 0;

  /// When set, an import does not finish until this completes, and
  /// throws [importError] then if that is set.
  Completer<void>? importGate;
  Object? importError;

  @override
  Future<HealthImportSummary> importNow({
    void Function(HealthImportProgress progress)? onProgress,
  }) async {
    calls++;
    await importGate?.future;
    final error = importError;
    if (error != null) throw error;
    storeDeletedDays = storeDeletedDaysAfterImport ?? storeDeletedDays;
    return summary;
  }

  /// Issue #1594: how many imported days the store has said were
  /// deleted, what each kind of pass leaves that at, and what a removal
  /// answers.
  int storeDeletedDays = 0;
  int? storeDeletedDaysAfterImport;
  int storeDeletedDaysAfterRemoval = 0;
  int storeDeletedDaysAfterKeep = 0;
  bool storeDeletedThrows = false;
  bool keepThrows = false;
  Object? removalError;
  HealthImportSummary removalSummary = const HealthImportSummary(
    samplesRead: 8,
    daysUnchanged: 8,
    daysRemoved: 2,
  );

  /// The offers she answered, as the screen handed them back.
  final List<HealthStoreDeletedOffer> removed = [];
  final List<HealthStoreDeletedOffer> kept = [];

  /// Held open, the offer is not answered until it completes.
  Completer<void>? storeDeletedGate;

  /// One fabricated record a day.
  static HealthStoreDeletedOffer offerOf(int days) => HealthStoreDeletedOffer(
        days: days,
        recordIds: {for (var day = 0; day < days; day++) 'rec-$day'},
      );

  @override
  Future<HealthStoreDeletedOffer> daysDeletedInStore() async {
    if (storeDeletedThrows) throw StateError('storage');
    await storeDeletedGate?.future;
    return offerOf(storeDeletedDays);
  }

  @override
  Future<HealthImportSummary> removeDaysDeletedInStore(
    HealthStoreDeletedOffer offer, {
    void Function(HealthImportProgress progress)? onProgress,
  }) async {
    removed.add(offer);
    await importGate?.future;
    final error = removalError;
    if (error != null) throw error;
    // A removal that was stopped leaves the days on offer.
    if (!removalSummary.isBlocked) {
      storeDeletedDays = storeDeletedDaysAfterRemoval;
    }
    return removalSummary;
  }

  @override
  Future<void> keepDaysDeletedInStore(HealthStoreDeletedOffer offer) async {
    kept.add(offer);
    if (keepThrows) throw StateError('storage');
    storeDeletedDays = storeDeletedDaysAfterKeep;
  }

  /// Issue #1573: whether the store has an "Access past data" switch at
  /// all, and what a request for it ends in.
  bool pastDataOffered = true;
  bool pastDataOfferedThrows = false;
  bool grantsPastData = false;
  bool pastDataRequestThrows = false;
  int pastDataOfferedProbes = 0;
  int pastDataRequests = 0;

  /// Run when a request is granted, so a test can make the probe answer
  /// that reads now reach the older data.
  void Function()? onPastDataGranted;

  /// When set, a request does not answer until this completes: the
  /// prompt is up.
  Completer<void>? pastDataPrompt;

  @override
  Future<bool> pastDataSwitchOffered() async {
    pastDataOfferedProbes++;
    if (pastDataOfferedThrows) throw StateError('boom');
    return pastDataOffered;
  }

  @override
  Future<bool> requestPastDataAccess() async {
    pastDataRequests++;
    await pastDataPrompt?.future;
    if (pastDataRequestThrows) throw StateError('boom');
    if (grantsPastData) onPastDataGranted?.call();
    return grantsPastData;
  }
}

/// A scripted [HealthPermissionProbe] for the Issue #1515 status line: each
/// direction's answer is set by hand and each probe is counted, so a test
/// can prove which questions the screen asked — in particular that it never
/// asks the read-side one of a store that does not disclose read access.
class _ScriptedProbe implements HealthPermissionProbe {
  _ScriptedProbe({
    required this.readAccessDisclosed,
    required this.write,
    this.read = HealthPermissionStatus.unavailable,
    this.readThrows = false,
    this.reachesPastData = true,
    this.pastDataThrows = false,
    this.grantedTypes = const {},
    this.neverAskedTypes = const {},
    this.neverAskedThrows = false,
    this.writeTypeRequestThrows = false,
  });

  @override
  final bool readAccessDisclosed;

  HealthPermissionStatus write;
  HealthPermissionStatus read;
  final bool readThrows;

  /// Issue #1549: whether "Access past data" is on. On by default, so a
  /// test that is not about it sees the store's whole history.
  bool reachesPastData;
  final bool pastDataThrows;
  Set<String> grantedTypes;
  int writeProbes = 0;
  int readProbes = 0;
  int pastDataProbes = 0;
  int grantedWriteTypesProbes = 0;

  /// Issue #1590: the write types no sheet has asked about, what the
  /// per-type probe does, and every ask the screen raised — the facts and
  /// the exact set of types, in order.
  Set<String> neverAskedTypes;
  final bool neverAskedThrows;
  final bool writeTypeRequestThrows;
  int neverAskedProbes = 0;
  int writeTypeRequests = 0;
  final List<({HealthGuardFacts facts, Set<String> types})>
      writeTypeRequestCalls = [];

  /// Run when an ask answers, so a test can make the probe show the
  /// type as asked (or granted).
  void Function()? onWriteTypeRequest;

  @override
  Future<HealthPermissionStatus> permissionStatus() async {
    writeProbes++;
    return write;
  }

  @override
  Future<Set<String>> grantedWriteTypes() async {
    grantedWriteTypesProbes++;
    return grantedTypes;
  }

  @override
  Future<Set<String>> neverAskedWriteTypes() async {
    neverAskedProbes++;
    if (neverAskedThrows) throw StateError('boom');
    return neverAskedTypes;
  }

  @override
  Future<HealthPlatformResult> requestWriteAuthorizationForTypes(
    HealthGuardFacts facts,
    Set<String> types,
  ) async {
    writeTypeRequests++;
    writeTypeRequestCalls.add((facts: facts, types: types));
    if (writeTypeRequestThrows) throw StateError('boom');
    onWriteTypeRequest?.call();
    return const HealthPlatformResult.allowed();
  }

  @override
  Future<HealthPermissionStatus> importPermissionStatus() async {
    readProbes++;
    if (readThrows) throw StateError('boom');
    return read;
  }

  @override
  Future<bool> importReachesPastData() async {
    pastDataProbes++;
    if (pastDataThrows) throw StateError('boom');
    return reachesPastData;
  }

  int settingsOpened = 0;

  @override
  Future<void> openPermissionSettings() async {
    settingsOpened++;
  }
}

/// A runner that throws, for the unexpected-failure line.
class _ThrowingImporter implements HealthImportRunner {
  @override
  HealthImportPlatform get platform => HealthImportPlatform.appleHealth;

  @override
  Future<HealthImportSummary> importNow({
    void Function(HealthImportProgress progress)? onProgress,
  }) async =>
      throw StateError('boom');

  @override
  Future<bool> pastDataSwitchOffered() async => true;

  @override
  Future<bool> requestPastDataAccess() async => false;

  @override
  Future<HealthStoreDeletedOffer> daysDeletedInStore() async =>
      const HealthStoreDeletedOffer();

  @override
  Future<HealthImportSummary> removeDaysDeletedInStore(
    HealthStoreDeletedOffer offer, {
    void Function(HealthImportProgress progress)? onProgress,
  }) =>
      throw StateError('boom');

  @override
  Future<void> keepDaysDeletedInStore(HealthStoreDeletedOffer offer) async {}
}

void main() {
  // Fixture: 'eligible' owned by the signed-in user (u1), 'minor' also
  // owned by u1 but is a minor, 'other' owned by a different account,
  // 'archived-profile' owned by u1 but archived (excluded from the
  // picker entirely — review fix).
  final profiles = [
    _profile(id: 'eligible', name: 'Alice'),
    _profile(id: 'minor', name: 'Baby', isMinor: true),
    _profile(id: 'other', name: 'Charlie'),
    _profile(
      id: 'archived-profile',
      name: 'Dana',
      archivedAt: DateTime.utc(2026, 1, 2),
    ),
  ];
  final guardiansByProfile = <String, List<ProfileGuardian>>{
    'eligible': [_owner('eligible', 'u1')],
    'minor': [_owner('minor', 'u1')],
    'other': [_owner('other', 'someone-else')],
    'archived-profile': [_owner('archived-profile', 'u1')],
  };

  Future<List<ProfileGuardian>> guardiansForProfile(String profileId) async =>
      guardiansByProfile[profileId] ?? const [];

  // Issue #959: the OS-permission status is driven through the real
  // `lunarlog/health` channel via a mock handler — the "channel fake" the
  // issue asks for — so these tests also pin the method name the native
  // halves must answer, not merely a hand-rolled Dart stand-in.
  const healthChannel = MethodChannel('lunarlog/health');
  final permissionCalls = <MethodCall>[];
  Object? permissionResult;
  // Issue #1515: what the fake native side answers for the READ-side probe
  // (`importPermissionStatus`, Android only). Null — a native half with no
  // such handler — decodes to "cannot tell", which leaves the status line
  // as the write answer alone, so every older test here reads as it did.
  Object? importPermissionResult;
  setUp(() {
    permissionCalls.clear();
    permissionResult = 'granted';
    importPermissionResult = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(healthChannel, (call) async {
      permissionCalls.add(call);
      if (call.method == 'permissionStatus') return permissionResult;
      if (call.method == 'importPermissionStatus') {
        return importPermissionResult;
      }
      return null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(healthChannel, null);
  });

  HealthPermissionProbe buildPermissionProbe() => MethodChannelHealthPlatform(
        binding: HealthSyncBinding(FakeSettingsStore()),
        minorBindingAllowed: true,
        readAccessDisclosed: true,
      );

  Future<void> pumpScreen(
    WidgetTester tester, {
    required HealthSyncBinding binding,
    String? signedInUserId = 'u1',
    ProfilesRepository? profilesRepository,
    HealthImportRunner? importer,
    HealthPermissionProbe? permissionProbe,
    bool writeEnabled = true,
    HealthImportPlatform? storePlatform,
    Size viewport = const Size(800, 1800),
  }) async {
    // The screen is a lazy ListView holding the profile tiles, the import
    // and unbind actions and, below them since Issue #1521, the reference
    // paragraphs, so give it a tall viewport to keep all of it inside the
    // build window. Issue #1017 overrides this with a short viewport to
    // prove the result is scrolled into view after a pass.
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        // Issue #238: the screen reads copy (including the Android
        // symptom-limitation line) through AppLocalizations, so the harness
        // registers the delegates and locales the real app wires.
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HealthSyncScreen(
          profilesRepository:
              profilesRepository ?? FakeProfilesRepository(profiles),
          guardiansForProfile: guardiansForProfile,
          binding: binding,
          signedInUserId: signedInUserId,
          importer: importer,
          permissionProbe: permissionProbe,
          writeEnabled: writeEnabled,
          storePlatform: storePlatform,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists every non-archived profile, showing a deny reason '
      'only for ineligible ones, and excludes archived profiles entirely',
      (tester) async {
    final binding = HealthSyncBinding(FakeSettingsStore());
    await pumpScreen(tester, binding: binding);

    expect(find.byKey(const ValueKey('health-sync-profile-eligible')), findsOneWidget);
    expect(find.byKey(const ValueKey('health-sync-profile-minor')), findsOneWidget);
    expect(find.byKey(const ValueKey('health-sync-profile-other')), findsOneWidget);

    // Archived profiles never appear in the picker (review fix).
    expect(
      find.byKey(const ValueKey('health-sync-profile-archived-profile')),
      findsNothing,
    );

    // The eligible profile shows no deny-reason subtitle.
    final eligibleTile = tester.widget<ListTile>(
      find.byKey(const ValueKey('health-sync-profile-eligible')),
    );
    expect(eligibleTile.subtitle, isNull);
    expect(eligibleTile.enabled, isTrue);

    // Issue #882: a minor profile owned by the signed-in account is
    // eligible on the same terms as an adult, so it shows no deny reason
    // and its tile is enabled.
    final minorTile = tester.widget<ListTile>(
      find.byKey(const ValueKey('health-sync-profile-minor')),
    );
    expect(minorTile.subtitle, isNull);
    expect(minorTile.enabled, isTrue);
    expect(find.textContaining('after ownership transfer'), findsNothing);

    // The non-owner profile (a real, resolved different owner) explains
    // the ownership requirement plainly.
    expect(
      find.textContaining("not this profile's owner"),
      findsOneWidget,
    );
    final otherTile = tester.widget<ListTile>(
      find.byKey(const ValueKey('health-sync-profile-other')),
    );
    expect(otherTile.enabled, isFalse);

    // No unbind action while nothing is bound.
    expect(find.byKey(const ValueKey('health-sync-unbind-tile')), findsNothing);
  });

  testWidgets('documents the forward-only write surface, the flow collapse '
      '(issue #193, mirroring Clue\'s own disclosure) and the user-initiated '
      'import (issue #217)', (tester) async {
    final binding = HealthSyncBinding(FakeSettingsStore());
    await pumpScreen(tester, binding: binding);

    // Issue #217 rewrote the old "nothing is ever read back" claim: import
    // exists, but only when the operator starts it. Issue #1215 then made
    // the copy match the enforced gate: the first import is the operator's
    // to start, and only after it does the import keep itself current in
    // the background.
    expect(
      find.textContaining('you start the first import yourself'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
          'after it lunarlog keeps the import current in the background'),
      findsOneWidget,
    );
    // Issue #1491: on an iPhone that promise has a condition the screen
    // used to leave out. The Health app never tells an app whether it may
    // read, so the background import goes by the write permissions — all
    // of them — and the sentence that makes the promise says so.
    expect(
      find.textContaining(
          'keeps the import current in the background, as long as all of '
          "lunarlog's write permissions in the Health app are on."),
      findsOneWidget,
    );
    expect(
      find.textContaining('nothing is read unless'),
      findsNothing,
      reason: 'the pre-#1215 claim, false since the gate shipped, verbatim',
    );
    expect(
      find.textContaining('Only days logged after sync is turned on'),
      findsOneWidget,
    );
    // The one lossy mapping in the #193 table: superHeavy -> Apple's
    // `heavy`, plus the A3-4 spotting rule, spelled out.
    expect(
      find.textContaining('Super heavy days are written to the Health app '
          'as Heavy'),
      findsOneWidget,
    );
    expect(
      find.textContaining('spotting between periods is written as '
          'intermenstrual bleeding'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('health-sync-symptoms-copy')),
      findsOneWidget,
    );
    // Issue #1526: the sentence names every tag that is written, not four
    // of them, and the iPhone screen has the list of what is written that
    // only the Android screen used to have.
    expect(
      find.textContaining('Cramps, Headache, Back pain, Breast tenderness, '
          'Bloating, Acne, Nausea, Fatigue, Dizziness, Sleep trouble and '
          'Other craving'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Symptoms you tag — cramps, headache, bloating'),
      findsNothing,
    );
    // The list itself, word for word (its items are tied to what is written
    // in health_sync_written_types_test.dart).
    expect(
      find.text('What lunarlog writes to the Health app: flow, with the '
          'first day of each period marked; spotting between periods; '
          'discharge you tag as sticky, creamy or egg white (cervical '
          'mucus); ovulation test results; basal body temperature, unless '
          'you exclude the reading from charts; and the symptoms and moods '
          'listed below.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('An intensity you give Cramps, Headache, Back '
          'pain or Breast tenderness is written with it, as mild, moderate '
          'or severe.'),
      findsOneWidget,
    );
  });

  testWidgets('an import-only platform (Android, Issue #458) shows the '
      'import explanation and hides the write-only copy', (tester) async {
    final binding = HealthSyncBinding(FakeSettingsStore());
    await pumpScreen(
      tester,
      binding: binding,
      writeEnabled: false,
    );

    expect(
      find.byKey(const ValueKey('health-sync-import-only-copy')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('health-sync-forward-only-copy')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('health-sync-flow-collapse-copy')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('health-sync-symptoms-copy')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('health-sync-revocation-copy')),
      findsNothing,
    );
  });

  // Issue #1478: an import-only screen used to follow "nothing is written
  // automatically" with a line saying days logged with symptoms "still sync
  // their flow and spotting". The symptom line now belongs to the Android
  // write screen (where that is true) and is gone from here.
  testWidgets('an import-only platform does not contradict "nothing is '
      'written" with a line about what still syncs (Issue #1478)',
      (tester) async {
    final binding = HealthSyncBinding(FakeSettingsStore());
    await pumpScreen(tester, binding: binding, writeEnabled: false);

    expect(find.textContaining('nothing is written automatically'),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('health-sync-symptoms-android-limitation')),
      findsNothing,
    );
    expect(find.textContaining('still sync their flow'), findsNothing);
  });

  testWidgets('Android, which writes, documents the permanent symptom '
      'limitation (Issue #238)', (tester) async {
    final binding = HealthSyncBinding(FakeSettingsStore());
    await pumpScreen(
      tester,
      binding: binding,
      writeEnabled: true,
      storePlatform: HealthImportPlatform.healthConnect,
    );

    expect(
      find.byKey(const ValueKey('health-sync-symptoms-android-limitation')),
      findsOneWidget,
    );
    expect(
      find.textContaining("Symptoms (cramps, headaches, mood, and more) "
          "can't be written to Health Connect"),
      findsOneWidget,
    );
  });

  testWidgets('a write-enabled platform (iOS) does not show the Android '
      'symptom limitation (Issue #238)', (tester) async {
    final binding = HealthSyncBinding(FakeSettingsStore());
    await pumpScreen(tester, binding: binding);

    expect(
      find.byKey(const ValueKey('health-sync-symptoms-android-limitation')),
      findsNothing,
    );
  });

  testWidgets('tapping an eligible profile opens a confirm dialog naming '
      'what binding means; confirming binds it', (tester) async {
    final binding = HealthSyncBinding(FakeSettingsStore());
    await pumpScreen(tester, binding: binding);

    await tester.tap(find.byKey(const ValueKey('health-sync-profile-eligible')));
    await tester.pumpAndSettle();

    expect(find.text('Sync Alice to this phone?'), findsOneWidget);
    expect(
      find.textContaining("Only Alice's data will ever be written"),
      findsOneWidget,
    );
    final dialogRoute = ModalRoute.of(
      tester.element(find.text('Sync Alice to this phone?')),
    );
    expect(dialogRoute?.settings.name, kRouteHealthSyncBindDialog);

    await tester.tap(find.byKey(const ValueKey('health-sync-confirm-bind')));
    await tester.pumpAndSettle();

    expect(await binding.boundProfileId(), 'eligible');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('health-sync-profile-eligible')),
        matching: find.byKey(const ValueKey('health-sync-bound-check')),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('health-sync-unbind-tile')), findsOneWidget);
  });

  testWidgets('canceling the confirm dialog leaves the profile unbound',
      (tester) async {
    final binding = HealthSyncBinding(FakeSettingsStore());
    await pumpScreen(tester, binding: binding);

    await tester.tap(find.byKey(const ValueKey('health-sync-profile-eligible')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await binding.boundProfileId(), isNull);
    expect(find.byKey(const ValueKey('health-sync-unbind-tile')), findsNothing);
  });

  testWidgets('tapping the minor profile opens the confirm dialog and '
      'binds it on confirmation (Issue #882: minors bind on the same terms '
      'as adults, so the tile is no longer disabled)', (tester) async {
    final binding = HealthSyncBinding(FakeSettingsStore());
    await pumpScreen(tester, binding: binding);

    await tester.tap(find.byKey(const ValueKey('health-sync-profile-minor')));
    await tester.pumpAndSettle();

    expect(find.text('Sync Baby to this phone?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('health-sync-confirm-bind')));
    await tester.pumpAndSettle();

    expect(await binding.boundProfileId(), 'minor');
  });

  testWidgets('confirming a bind that the binding then denies surfaces the '
      'deny reason instead of discarding it (review fix)', (tester) async {
    final binding = _AlwaysAllowThenDenyBinding(FakeSettingsStore());
    await pumpScreen(tester, binding: binding);

    await tester.tap(find.byKey(const ValueKey('health-sync-profile-eligible')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('health-sync-confirm-bind')));
    await tester.pumpAndSettle();

    expect(await binding.boundProfileId(), isNull);
    expect(
      find.textContaining("You are not this profile's owner"),
      findsOneWidget,
    );

    // Let the SnackBar retire before the test ends, matching
    // `test/ui/gate_test.dart`'s convention for avoiding a pending-timer
    // failure.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('the unbind action (confirmed) clears the binding and hides '
      'itself', (tester) async {
    final settings = FakeSettingsStore();
    final binding = HealthSyncBinding(settings);
    await binding.bind(
      profile: profiles.firstWhere((p) => p.id == 'eligible'),
      signedInUserId: 'u1',
      ownerUserId: 'u1',
      minorBindingAllowed: false,
    );

    await pumpScreen(tester, binding: binding);

    expect(find.byKey(const ValueKey('health-sync-unbind-tile')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('health-sync-unbind-tile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('health-sync-confirm-unbind')));
    await tester.pumpAndSettle();

    expect(await binding.boundProfileId(), isNull);
    expect(find.byKey(const ValueKey('health-sync-unbind-tile')), findsNothing);
  });

  testWidgets('tapping the unbind tile opens a confirm dialog naming the '
      'profile and does NOT unbind on cancel (Issue #893)', (tester) async {
    final binding = HealthSyncBinding(FakeSettingsStore());
    await binding.bind(
      profile: profiles.firstWhere((p) => p.id == 'eligible'),
      signedInUserId: 'u1',
      ownerUserId: 'u1',
      minorBindingAllowed: false,
    );
    await pumpScreen(tester, binding: binding);

    await tester.tap(find.byKey(const ValueKey('health-sync-unbind-tile')));
    await tester.pumpAndSettle();

    expect(find.text('Stop syncing Alice to this phone?'), findsOneWidget);
    expect(
      find.textContaining("Nothing already logged in lunarlog"),
      findsOneWidget,
    );
    final dialogRoute = ModalRoute.of(
      tester.element(find.text('Stop syncing Alice to this phone?')),
    );
    expect(dialogRoute?.settings.name, kRouteHealthSyncUnbindDialog);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await binding.boundProfileId(), 'eligible');
    expect(find.byKey(const ValueKey('health-sync-unbind-tile')), findsOneWidget);
  });

  testWidgets('confirming the unbind dialog unbinds the profile (Issue #893)',
      (tester) async {
    final binding = HealthSyncBinding(FakeSettingsStore());
    await binding.bind(
      profile: profiles.firstWhere((p) => p.id == 'eligible'),
      signedInUserId: 'u1',
      ownerUserId: 'u1',
      minorBindingAllowed: false,
    );
    await pumpScreen(tester, binding: binding);

    await tester.tap(find.byKey(const ValueKey('health-sync-unbind-tile')));
    await tester.pumpAndSettle();
    // The dialog must not have already torn the binding down on its own.
    expect(await binding.boundProfileId(), 'eligible');

    await tester.tap(find.byKey(const ValueKey('health-sync-confirm-unbind')));
    await tester.pumpAndSettle();

    expect(await binding.boundProfileId(), isNull);
    expect(find.byKey(const ValueKey('health-sync-unbind-tile')), findsNothing);
  });

  testWidgets('a signed-out session denies every non-minor profile with an '
      'actionable "sign in and sync" prompt, not the plain not-owner '
      'message (review fix — distinct copy for a never-synced local-only '
      'user)', (tester) async {
    final binding = HealthSyncBinding(FakeSettingsStore());
    await pumpScreen(tester, binding: binding, signedInUserId: null);

    final eligibleTile = tester.widget<ListTile>(
      find.byKey(const ValueKey('health-sync-profile-eligible')),
    );
    expect(eligibleTile.enabled, isFalse);
    expect(
      find.textContaining('Sign in and sync once'),
      findsWidgets,
    );
    expect(find.textContaining("not this profile's owner"), findsNothing);
  });

  testWidgets('a signed-in profile with no resolved owner (guardians not '
      'yet synced) is allowed — no one else claims it (Issue #882 review '
      'round 2)', (tester) async {
    final binding = HealthSyncBinding(FakeSettingsStore());
    await pumpScreen(
      tester,
      binding: binding,
      profilesRepository:
          FakeProfilesRepository([_profile(id: 'unsynced', name: 'Eve')]),
      signedInUserId: 'u1',
    );

    final tile = tester.widget<ListTile>(
      find.byKey(const ValueKey('health-sync-profile-unsynced')),
    );
    expect(tile.subtitle, isNull);
    expect(tile.enabled, isTrue);
    expect(find.textContaining('Sign in and sync once'), findsNothing);
  });

  testWidgets('a throwing repository resolves the spinner into an error '
      'state instead of spinning forever (review fix)', (tester) async {
    final binding = HealthSyncBinding(FakeSettingsStore());
    await pumpScreen(
      tester,
      binding: binding,
      profilesRepository: ThrowingProfilesRepository(),
    );

    expect(find.byKey(const ValueKey('health-sync-loading')), findsNothing);
    expect(find.byKey(const ValueKey('health-sync-load-error')), findsOneWidget);
  });

  group('Issue #217 import', () {
    Future<HealthSyncBinding> boundBinding(FakeSettingsStore settings) async {
      final binding = HealthSyncBinding(settings);
      await binding.bind(
        profile: profiles.firstWhere((p) => p.id == 'eligible'),
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: false,
      );
      return binding;
    }

    testWidgets('after an import completes on a short screen the result is '
        'scrolled into view and announced in a SnackBar (Issue #1017)',
        (tester) async {
      final importer = _FakeImporter(const HealthImportSummary(
        samplesRead: 3,
        daysWritten: 3,
        samplesFromDeviceZone: 3,
      ));
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(
        tester,
        binding: binding,
        importer: importer,
        // Short enough that the import tile and its result cannot both be
        // on screen at once, so the pass must scroll the result into view.
        viewport: const Size(400, 300),
      );

      final tile = find.byKey(const ValueKey('health-sync-import-tile'));
      await tester.scrollUntilVisible(tile, 120);
      // The coarse scroll stops at first partial visibility, so the tile
      // can still peek in from below the 300 px viewport — a centre tap
      // would then land off-screen and silently miss. Finish the reveal.
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();

      final result = find.byKey(const ValueKey('health-sync-import-summary'));
      expect(result, findsOneWidget);
      final screenHeight = tester.view.physicalSize.height /
          tester.view.devicePixelRatio;
      final rect = tester.getRect(result);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(
        rect.bottom,
        lessThanOrEqualTo(screenHeight),
        reason: 'the result must be scrolled fully into view after the pass',
      );
      // The completion headline is also announced in a SnackBar so the tap
      // cannot look like it did nothing.
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.textContaining('Imported 3 days'),
        ),
        findsOneWidget,
      );

      // Retire the SnackBar so no timer outlives the test.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('a finished import states its outcome exactly once — the '
        'headline, without the pre-#992 duplicate lines (Issue #1017)',
        (tester) async {
      final importer = _FakeImporter(const HealthImportSummary(
        samplesRead: 3,
        daysWritten: 3,
        daysUnchanged: 1,
      ));
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(tester, binding: binding, importer: importer);

      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      final summary = find.byKey(const ValueKey('health-sync-import-summary'));
      expect(
        find.descendant(
          of: summary,
          matching: find.text('Imported 3 days, skipped 1 already logged.'),
        ),
        findsOneWidget,
      );
      // The headline already carries the imported and skipped counts, so the
      // summary must not restate them with "Updated N days" / "N days
      // already matched".
      expect(
        find.descendant(
          of: summary,
          matching: find.textContaining('Updated 3 days'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: summary,
          matching: find.textContaining('already matched'),
        ),
        findsNothing,
      );
      // Exactly one line: the outcome is stated once.
      expect(
        find.descendant(of: summary, matching: find.byType(Text)),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('the import tile is hidden when no runner is provided or '
        'nothing is bound', (tester) async {
      final settings = FakeSettingsStore();
      final binding = HealthSyncBinding(settings);
      await pumpScreen(tester, binding: binding);
      // Not bound: no tile even with a runner.
      expect(
        find.byKey(const ValueKey('health-sync-import-tile')),
        findsNothing,
      );

      await pumpScreen(
        tester,
        binding: await boundBinding(FakeSettingsStore()),
      );
      // Bound but no runner (an unconfigured/test build): still hidden.
      expect(
        find.byKey(const ValueKey('health-sync-import-tile')),
        findsNothing,
      );
    });

    testWidgets('tapping Import runs the runner once and renders the '
        'positive summary', (tester) async {
      final importer = _FakeImporter(const HealthImportSummary(
        samplesRead: 2,
        daysWritten: 2,
        daysKeptManual: 1,
      ));
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(tester, binding: binding, importer: importer);

      expect(
        find.byKey(const ValueKey('health-sync-import-tile')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      expect(importer.calls, 1);
      // importedDays = 2, skippedAlreadyLoggedDays = 1.
      final summary = find.byKey(const ValueKey('health-sync-import-summary'));
      expect(
        find.descendant(
          of: summary,
          matching: find.text('Imported 2 days, skipped 1 already logged.'),
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Kept your own changes on 1 day.'),
        findsOneWidget,
      );
      // Issue #1017: the pre-#992 "Updated N days" line restated the
      // headline's imported count and is gone.
      expect(find.textContaining('Updated 2 days'), findsNothing);
    });

    testWidgets('the completion summary headline reports imported days and '
        'days skipped because a value was already there (Issue #992)',
        (tester) async {
      final importer = _FakeImporter(const HealthImportSummary(
        samplesRead: 3,
        daysWritten: 2,
        daysUnchanged: 4,
        daysKeptManual: 1,
      ));
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(tester, binding: binding, importer: importer);

      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      // importedDays = 2, skippedAlreadyLoggedDays = 4 + 1 = 5. Scoped to the
      // result block: the completion SnackBar (Issue #1017) announces the
      // same headline.
      final summary = find.byKey(const ValueKey('health-sync-import-summary'));
      expect(
        find.descendant(
          of: summary,
          matching: find.textContaining('Imported 2 days, skipped 5 already '
              'logged.'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a pass stopped by the page cap says so rather than '
        'pretending it finished (Issue #992)', (tester) async {
      final importer = _FakeImporter(const HealthImportSummary(
        samplesRead: 2,
        daysWritten: 1,
        pageLimitReached: true,
      ));
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(tester, binding: binding, importer: importer);

      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('The import stopped early'),
        findsOneWidget,
      );
    });

    testWidgets('a device-zone import is reported as dated alongside the '
        'unplaceable skips, never labelled skipped itself (Issue #902, #1001, '
        'reshaped by #1017)', (tester) async {
      final importer = _FakeImporter(const HealthImportSummary(
        samplesRead: 4,
        daysWritten: 3,
        samplesFromDeviceZone: 2,
        samplesWithoutZone: 1,
      ));
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(tester, binding: binding, importer: importer);

      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          'Dated 2 entries using the time zone of this phone.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Skipped 1 entry with no recorded time zone.'),
        findsOneWidget,
      );
      // The two inferred placements are reported as dated, never folded
      // into the skip count.
      expect(find.textContaining('Skipped 2 entries'), findsNothing);
    });

    testWidgets('a confirmed unbind clears the previous import summary from '
        'the screen (Issue #893)', (tester) async {
      final importer = _FakeImporter(const HealthImportSummary(
        samplesRead: 2,
        daysWritten: 2,
      ));
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(tester, binding: binding, importer: importer);

      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();
      final summary = find.byKey(const ValueKey('health-sync-import-summary'));
      expect(
        find.descendant(
          of: summary,
          // Issue #1557: with nothing skipped it says only what came in.
          matching: find.text('Imported 2 days.'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('health-sync-unbind-tile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('health-sync-confirm-unbind')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('health-sync-import-summary')),
        findsNothing,
      );
    });

    testWidgets('an empty result renders the neutral ambiguity copy, never '
        '"nothing tracked" or "permission denied"', (tester) async {
      final importer = _FakeImporter(const HealthImportSummary());
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(tester, binding: binding, importer: importer);

      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          healthImportEmptyCopy(AppLocalizationsEn(), HealthImportPlatform.appleHealth),
        ),
        findsOneWidget,
      );
      // The neutral copy itself states both possibilities; it must not
      // assert either as fact, and no denial line is rendered.
      expect(find.textContaining('permission denied'), findsNothing);
    });

    testWidgets('a denied read renders the same neutral copy as an empty '
        'one (HealthKit opacity)', (tester) async {
      final importer = _FakeImporter(const HealthImportSummary(
        blocked: HealthPlatformPermissionDenied(),
      ));
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(tester, binding: binding, importer: importer);

      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          healthImportEmptyCopy(AppLocalizationsEn(), HealthImportPlatform.appleHealth),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('permission denied'), findsNothing);
    });

    testWidgets('a guard refusal renders the cannot-import line', (tester) async {
      final importer = _FakeImporter(const HealthImportSummary(
        blocked: HealthPlatformRefused(HealthSyncCheck.notOwner),
      ));
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(tester, binding: binding, importer: importer);

      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining("This profile can't import from the Health app"),
        findsOneWidget,
      );
    });

    testWidgets('a platform unavailable outcome renders platform-specific copy',
        (tester) async {
      final iosImporter = _FakeImporter(const HealthImportSummary(
        blocked: HealthPlatformUnavailable(),
      ), platform: HealthImportPlatform.appleHealth);
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(tester, binding: binding, importer: iosImporter);

      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      expect(
        find.text("The Health app isn't available on this device."),
        findsOneWidget,
      );

      final androidImporter = _FakeImporter(const HealthImportSummary(
        blocked: HealthPlatformUnavailable(),
      ), platform: HealthImportPlatform.healthConnect);
      final androidBinding = await boundBinding(FakeSettingsStore());
      await pumpScreen(
        tester,
        binding: androidBinding,
        importer: androidImporter,
        writeEnabled: false,
      );

      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      expect(
        find.text("Health Connect isn't available on this device."),
        findsOneWidget,
      );
    });

    testWidgets('a platform failed outcome renders generic retry copy',
        (tester) async {
      final importer = _FakeImporter(const HealthImportSummary(
        blocked: HealthPlatformFailed('disk error'),
      ));
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(tester, binding: binding, importer: importer);

      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      expect(
        find.text("Couldn't finish the import. Please try again."),
        findsOneWidget,
      );
    });

    testWidgets('a platform allowed with empty summary renders neutral copy',
        (tester) async {
      final importer = _FakeImporter(const HealthImportSummary(
        blocked: HealthPlatformAllowed(),
      ));
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(tester, binding: binding, importer: importer);

      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      expect(
        find.text(healthImportEmptyCopy(AppLocalizationsEn(), HealthImportPlatform.appleHealth)),
        findsOneWidget,
      );
    });

    testWidgets('an Android runner names Health Connect and renders the '
        'spotting line (Issue #458)', (tester) async {
      final importer = _FakeImporter(
        const HealthImportSummary(spottingDaysWritten: 2),
        platform: HealthImportPlatform.healthConnect,
      );
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(tester, binding: binding, importer: importer);

      expect(
        find.text('Import from Health Connect'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Added spotting to 2 days from Health Connect.'),
        findsWidgets,
      );
      // No day was imported and none was skipped, so there is no headline:
      // "Imported 0 days." stood above this line before.
      expect(find.textContaining('Imported 0'), findsNothing);
      expect(find.textContaining('Nothing new'), findsNothing);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('an import that adds spotting and no day leads with the '
        'spotting, then says the days were already logged', (tester) async {
      final importer = _FakeImporter(
        const HealthImportSummary(
          samplesRead: 5,
          spottingDaysWritten: 1,
          daysUnchanged: 2,
          daysKeptManual: 2,
        ),
        platform: HealthImportPlatform.healthConnect,
      );
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(tester, binding: binding, importer: importer);

      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      final summary = find.byKey(const ValueKey('health-sync-import-summary'));
      final lines = [
        for (final text in tester.widgetList<Text>(
          find.descendant(of: summary, matching: find.byType(Text)),
        ))
          text.data,
      ];
      const added = 'Added spotting to 1 day from Health Connect.';
      const alreadyLogged = '4 days were already logged.';
      expect(lines, containsAllInOrder([added, alreadyLogged]));
      expect(lines, contains('Kept your own changes on 2 days.'));
      expect(find.textContaining('Imported 0'), findsNothing);
      expect(find.textContaining('Nothing new'), findsNothing);
      // The announcement is the result's first line.
      expect(
        find.descendant(of: find.byType(SnackBar), matching: find.text(added)),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('one day already logged reads in the singular', (tester) async {
      final importer = _FakeImporter(
        const HealthImportSummary(
          samplesRead: 2,
          spottingDaysWritten: 1,
          daysUnchanged: 1,
        ),
        platform: HealthImportPlatform.healthConnect,
      );
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(tester, binding: binding, importer: importer);

      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      expect(find.text('1 day was already logged.'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    // Issue #1594. The health store reports that records lunarlog imported
    // from were deleted. lunarlog removes nothing on that report alone: it
    // says how many days, asks, and asks once more before removing.
    group('Issue #1594 days the store deleted', () {
      const offerTwo = 'Records lunarlog imported for 2 days were deleted in '
          'Health Connect.';
      const detailTwo = 'They may have been removed in the app they came '
          "from, or that app's data may have been cleared. You can remove "
          'what was imported for those days, or keep it.';
      const confirmTitleTwo = 'Remove what was imported for 2 days?';
      const confirmBodyTwo = 'The imported flow or spotting comes off those '
          'days, here and on every device this profile syncs to. Tags, notes '
          'and other entries stay. This cannot be undone.';
      const removedTwo = 'Removed what was imported for 2 days: their '
          'records were deleted in Health Connect.';
      const nothingRemoved = 'Nothing was removed.';
      const readFailed = 'lunarlog could not read everything in Health '
          'Connect. Please try again.';
      const nothingNew =
          'Nothing new to import from Health Connect since the last import.';
      final offer = find.byKey(const ValueKey('health-sync-store-deleted-offer'));
      final remove =
          find.byKey(const ValueKey('health-sync-store-deleted-remove'));
      final keep = find.byKey(const ValueKey('health-sync-store-deleted-keep'));
      final confirm =
          find.byKey(const ValueKey('health-sync-store-deleted-confirm'));
      final result = find.byKey(const ValueKey('health-sync-import-summary'));
      final importTile = find.byKey(const ValueKey('health-sync-import-tile'));

      _FakeImporter importerWith({
        int waiting = 0,
        HealthImportPlatform platform = HealthImportPlatform.healthConnect,
      }) =>
          _FakeImporter(
            const HealthImportSummary(incremental: true, pagesRead: 1),
            platform: platform,
          )..storeDeletedDays = waiting;

      List<String?> linesIn(WidgetTester tester, Finder block) => [
            for (final text in tester.widgetList<Text>(
              find.descendant(of: block, matching: find.byType(Text)),
            ))
              text.data,
          ];

      Future<void> pumpBound(WidgetTester tester, _FakeImporter importer) async =>
          pumpScreen(
            tester,
            binding: await boundBinding(FakeSettingsStore()),
            importer: importer,
          );

      Future<void> letTheSnackBarGo(WidgetTester tester) async {
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      }

      /// Remove, and then the confirmation.
      Future<void> removeAndConfirm(WidgetTester tester) async {
        await tester.tap(remove);
        await tester.pumpAndSettle();
        await tester.tap(confirm);
        await tester.pumpAndSettle();
      }

      testWidgets('days waiting when the screen opens are offered, with both '
          'answers and Keep first', (tester) async {
        await pumpBound(tester, importerWith(waiting: 2));

        expect(linesIn(tester, offer), [
          offerTwo,
          detailTwo,
          'Keep',
          'Remove from lunarlog',
        ]);
        // Neither answer is dressed as the one to pick.
        expect(tester.widget(keep), isA<OutlinedButton>());
        expect(tester.widget(remove), isA<OutlinedButton>());
      });

      testWidgets('one day reads in the singular', (tester) async {
        await pumpBound(tester, importerWith(waiting: 1));

        expect(linesIn(tester, offer).take(2), [
          'A record lunarlog imported for 1 day was deleted in Health '
              'Connect.',
          'It may have been removed in the app it came from, or that '
              "app's data may have been cleared. You can remove what was "
              'imported for that day, or keep it.',
        ]);
      });

      testWidgets('on an iPhone the store is the Health app', (tester) async {
        await pumpBound(
          tester,
          importerWith(waiting: 2, platform: HealthImportPlatform.appleHealth),
        );

        expect(
          linesIn(tester, offer).first,
          'Records lunarlog imported for 2 days were deleted in the Health '
              'app.',
        );
      });

      testWidgets('nothing is offered when no day is waiting', (tester) async {
        await pumpBound(tester, importerWith());
        expect(offer, findsNothing);
      });

      testWidgets('an import that finds deleted records says there is '
          'nothing to import, and offers the days under it', (tester) async {
        final importer = importerWith()..storeDeletedDaysAfterImport = 2;
        await pumpBound(tester, importer);
        expect(offer, findsNothing);

        await tester.tap(importTile);
        await tester.pumpAndSettle();

        expect(linesIn(tester, result), [nothingNew]);
        expect(linesIn(tester, offer).first, offerTwo);
        expect(importer.removed, isEmpty, reason: 'nothing removed unasked');
      });

      testWidgets('Remove asks once more, saying what goes, what stays, '
          'where, and that it cannot be undone', (tester) async {
        final importer = importerWith(waiting: 2);
        await pumpBound(tester, importer);

        await tester.tap(remove);
        await tester.pumpAndSettle();

        final dialog = find.byType(AlertDialog);
        expect(linesIn(tester, dialog), [
          confirmTitleTwo,
          confirmBodyTwo,
          'Cancel',
          'Remove',
        ]);
        expect(
          ModalRoute.of(tester.element(dialog))?.settings.name,
          kRouteHealthSyncStoreDeletedDialog,
        );
        // The step that cannot be taken back is the destructive one.
        expect(tester.widget(confirm), isA<DestructiveButton>());
        expect(importer.removed, isEmpty, reason: 'not before she confirms');
      });

      testWidgets('the confirmation for one day reads in the singular',
          (tester) async {
        await pumpBound(tester, importerWith(waiting: 1));

        await tester.tap(remove);
        await tester.pumpAndSettle();

        expect(linesIn(tester, find.byType(AlertDialog)).take(2), [
          'Remove what was imported for 1 day?',
          'The imported flow or spotting comes off that day, here and on '
              'every device this profile syncs to. Tags, notes and other '
              'entries stay. This cannot be undone.',
        ]);
      });

      testWidgets('Cancel removes nothing and leaves the offer', (tester) async {
        final importer = importerWith(waiting: 2);
        await pumpBound(tester, importer);

        await tester.tap(remove);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(importer.removed, isEmpty);
        expect(importer.kept, isEmpty);
        expect(importer.calls, 0);
        expect(linesIn(tester, offer).first, offerTwo);
        expect(result, findsNothing);
      });

      testWidgets('confirmed, the removal is of the offer she was shown; it '
          'says what it did, and the offer goes', (tester) async {
        final importer = importerWith(waiting: 2);
        await pumpBound(tester, importer);

        await removeAndConfirm(tester);

        expect(importer.removed.single.days, 2);
        expect(importer.removed.single.recordIds, {'rec-0', 'rec-1'});
        expect(importer.calls, 0, reason: 'a removal is not an import');
        expect(
          linesIn(tester, result),
          [removedTwo, '8 days were already logged.'],
        );
        expect(find.textContaining('Nothing new'), findsNothing);
        expect(offer, findsNothing);
        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.text(removedTwo),
          ),
          findsOneWidget,
        );
        await letTheSnackBarGo(tester);
      });

      // More turn up while she is reading the confirmation. She agreed to
      // two days, so two days it is, and the rest are offered afterwards.
      testWidgets('days the store reports after she tapped Remove are not '
          'part of that removal', (tester) async {
        final importer = importerWith(waiting: 2)
          ..storeDeletedDaysAfterRemoval = 3;
        await pumpBound(tester, importer);

        await tester.tap(remove);
        await tester.pumpAndSettle();
        importer.storeDeletedDays = 5;
        await tester.tap(confirm);
        await tester.pumpAndSettle();

        expect(importer.removed.single, isA<HealthStoreDeletedOffer>());
        expect(importer.removed.single.days, 2);
        expect(importer.removed.single.recordIds, {'rec-0', 'rec-1'});
        expect(
          linesIn(tester, offer).first,
          'Records lunarlog imported for 3 days were deleted in Health '
              'Connect.',
        );
        await letTheSnackBarGo(tester);
      });

      testWidgets('Keep hands back the offer she was shown, leaves '
          'everything as it is, and the offer goes', (tester) async {
        final importer = importerWith(waiting: 2);
        await pumpBound(tester, importer);

        await tester.tap(keep);
        await tester.pumpAndSettle();

        expect(importer.kept.single.recordIds, {'rec-0', 'rec-1'});
        expect(importer.removed, isEmpty);
        expect(importer.calls, 0);
        expect(offer, findsNothing);
        expect(result, findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
      });

      testWidgets('after Keep, days the store has reported since are offered',
          (tester) async {
        final importer = importerWith(waiting: 2)..storeDeletedDaysAfterKeep = 1;
        await pumpBound(tester, importer);

        await tester.tap(keep);
        await tester.pumpAndSettle();

        expect(
          linesIn(tester, offer).first,
          'A record lunarlog imported for 1 day was deleted in Health '
              'Connect.',
        );
      });

      testWidgets('a Keep that could not be stored leaves the offer up',
          (tester) async {
        final importer = importerWith(waiting: 2)..keepThrows = true;
        await pumpBound(tester, importer);

        await tester.tap(keep);
        await tester.pumpAndSettle();

        expect(importer.kept, hasLength(1));
        expect(linesIn(tester, offer).first, offerTwo);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a removal that could not read the store says nothing was '
          'removed, and the days stay on offer', (tester) async {
        final importer = importerWith(waiting: 2)
          ..removalSummary = const HealthImportSummary(
            blocked: HealthPlatformResult.failed('the read did not finish'),
          );
        await pumpBound(tester, importer);

        await removeAndConfirm(tester);

        expect(importer.removed, hasLength(1));
        expect(linesIn(tester, result), [nothingRemoved, readFailed]);
        expect(linesIn(tester, offer).first, offerTwo);
      });

      // No read was tried: the reason is the import's own line, and
      // "try again" would not be true.
      testWidgets('a removal the profile may not make says nothing was '
          'removed, and why', (tester) async {
        final importer = importerWith(waiting: 2)
          ..removalSummary = const HealthImportSummary(
            blocked: HealthPlatformResult.refused(HealthSyncCheck.notOwner),
          );
        await pumpBound(tester, importer);

        await removeAndConfirm(tester);

        expect(linesIn(tester, result), [
          nothingRemoved,
          "This profile can't import from Health Connect right now.",
        ]);
        expect(linesIn(tester, offer).first, offerTwo);
      });

      // She had turned reading off, and declined the sheet the tap
      // raised. The import's line for that is "no data, or reading is
      // off", which would sit oddly over an offer about deleted records.
      testWidgets('a removal that was not allowed to read says so, not '
          'that the store has no data', (tester) async {
        final importer = importerWith(waiting: 2)
          ..removalSummary = const HealthImportSummary(
            blocked: HealthPlatformPermissionDenied(),
          );
        await pumpBound(tester, importer);

        await removeAndConfirm(tester);

        expect(linesIn(tester, result), [nothingRemoved, readFailed]);
      });

      // The read of everything found nothing in the store, so the
      // removal is all the pass did.
      testWidgets('a removal that read nothing still says what it removed',
          (tester) async {
        final importer = importerWith(waiting: 2)
          ..removalSummary = const HealthImportSummary(daysRemoved: 2);
        await pumpBound(tester, importer);

        await removeAndConfirm(tester);

        expect(linesIn(tester, result), [removedTwo]);
        await letTheSnackBarGo(tester);
      });

      testWidgets('a removal that failed part-way does not call itself an '
          'import, and does not say nothing was removed', (tester) async {
        final importer = importerWith(waiting: 2)
          ..removalError = StateError('storage');
        await pumpBound(tester, importer);

        await removeAndConfirm(tester);

        expect(
          linesIn(tester, result),
          ['Could not finish removing. Please try again.'],
        );
      });

      // What a result says depends on which kind of pass produced it.
      testWidgets('an import that is stopped after a removal was stopped '
          'speaks as an import', (tester) async {
        const stopped = HealthImportSummary(
          blocked: HealthPlatformResult.failed('the store went away'),
        );
        final importer = _FakeImporter(
          stopped,
          platform: HealthImportPlatform.healthConnect,
        )
          ..storeDeletedDays = 2
          ..removalSummary = stopped;
        await pumpBound(tester, importer);
        await removeAndConfirm(tester);
        expect(linesIn(tester, result), [nothingRemoved, readFailed]);

        await tester.ensureVisible(importTile);
        await tester.tap(importTile);
        await tester.pumpAndSettle();

        expect(
          linesIn(tester, result),
          ["Couldn't finish the import. Please try again."],
        );
      });

      testWidgets('the offer is out of the way while a pass is running',
          (tester) async {
        final importer = importerWith(waiting: 2)..importGate = Completer<void>();
        await pumpBound(tester, importer);

        await tester.tap(remove);
        await tester.pumpAndSettle();
        await tester.tap(confirm);
        await tester.pump();
        await tester.pump();
        expect(offer, findsNothing);
        expect(importer.removed, hasLength(1));

        importer.importGate!.complete();
        await tester.pumpAndSettle();
        expect(offer, findsNothing);
        await letTheSnackBarGo(tester);
      });

      testWidgets('an offer that cannot be read is not made, and does not '
          'stop the screen loading', (tester) async {
        await pumpBound(
          tester,
          importerWith(waiting: 2)..storeDeletedThrows = true,
        );

        expect(offer, findsNothing);
        expect(importTile, findsOneWidget);
      });

      // The days were the old binding's. The screen loads again after a
      // change, and until that load is done it still shows the old
      // binding: the offer must not be among what it shows.
      testWidgets('stopping the sync takes the offer down at once, before '
          'the screen has loaded again', (tester) async {
        final importer = importerWith(waiting: 2);
        await pumpBound(tester, importer);
        expect(offer, findsOneWidget);
        final unbind = find.byKey(const ValueKey('health-sync-unbind-tile'));
        await tester.ensureVisible(unbind);
        await tester.pumpAndSettle();
        importer.storeDeletedGate = Completer<void>();

        await tester.tap(unbind);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('health-sync-confirm-unbind')),
        );
        await tester.pumpAndSettle();

        expect(unbind, findsOneWidget, reason: 'the load is still waiting');
        expect(offer, findsNothing);

        importer.storeDeletedGate!.complete();
        await tester.pumpAndSettle();
        expect(unbind, findsNothing);
        expect(offer, findsNothing);
      });

      testWidgets('with no profile bound there is nothing to offer',
          (tester) async {
        await pumpScreen(
          tester,
          binding: HealthSyncBinding(FakeSettingsStore()),
          importer: importerWith(waiting: 2),
        );

        expect(offer, findsNothing);
      });

      testWidgets('a removal with a day imported in the same pass leads with '
          'the import', (tester) async {
        final importer = importerWith(waiting: 1)
          ..removalSummary = const HealthImportSummary(
            samplesRead: 1,
            daysWritten: 1,
            daysRemoved: 1,
          );
        await pumpBound(tester, importer);

        await removeAndConfirm(tester);

        expect(
          linesIn(tester, result),
          [
            'Imported 1 day.',
            'Removed what was imported for 1 day: its record was deleted in '
                'Health Connect.',
          ],
        );
        await letTheSnackBarGo(tester);
      });
    });

    testWidgets('a throwing runner renders the generic failure line',
        (tester) async {
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(
        tester,
        binding: binding,
        importer: _ThrowingImporter(),
      );

      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining("Couldn't finish the import. Please try again."),
        findsOneWidget,
      );
    });
  });

  // Issue #959: the OS permission state is shown per platform, with the
  // settings deep link offered only when it is denied.
  group('Issue #959 OS permission status', () {
    Future<HealthSyncBinding> boundBinding(FakeSettingsStore settings) async {
      final binding = HealthSyncBinding(settings);
      await binding.bind(
        profile: profiles.firstWhere((p) => p.id == 'eligible'),
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: false,
      );
      return binding;
    }

    testWidgets('renders granted / not-yet-asked / denied from the channel '
        'fake, and offers the settings link only when denied', (tester) async {
      final probe = buildPermissionProbe();
      final binding = HealthSyncBinding(FakeSettingsStore());

      for (final (wire, expected) in [
        ('granted', 'Health app access: granted'),
        ('notAsked', 'Health app access: not yet asked'),
        ('denied', 'Health app access: denied — open Settings to change'),
      ]) {
        permissionResult = wire;
        // Tear the previous tree down so the screen's State is recreated
        // and re-runs its permission load for the new wire value.
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpScreen(tester, binding: binding, permissionProbe: probe);

        expect(
          find.byKey(const ValueKey('health-sync-permission-status')),
          findsOneWidget,
        );
        expect(find.text(expected), findsOneWidget);
        expect(
          find.byKey(const ValueKey('health-sync-open-settings')),
          wire == 'denied' ? findsOneWidget : findsNothing,
        );
      }
    });

    testWidgets('the permission line is sentence-initial on both platforms — '
        'iOS never reads a lowercase "the" (Issue #1053)', (tester) async {
      final binding = HealthSyncBinding(FakeSettingsStore());

      // iOS: Apple Health's mid-sentence form is 'the Health app', but the
      // status line opens with the store name, so it must use the
      // sentence-initial title form 'Health app'.
      permissionResult = 'notAsked';
      await pumpScreen(
        tester,
        binding: binding,
        permissionProbe: buildPermissionProbe(),
      );
      expect(find.text('Health app access: not yet asked'), findsOneWidget);
      final line = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('health-sync-permission-status')),
          matching: find.byType(Text),
        ),
      );
      expect(line.data, startsWith('Health app'));
      expect(line.data, isNot(startsWith('the ')));

      // Android: Health Connect is the same name in both positions, and the
      // line still reads as expected (writeEnabled: false selects it when no
      // importer is wired).
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpScreen(
        tester,
        binding: binding,
        permissionProbe: buildPermissionProbe(),
        writeEnabled: false,
      );
      expect(find.text('Health Connect access: not yet asked'), findsOneWidget);
    });

    testWidgets('read status is never rendered as denied on iOS — a granted '
        'or not-yet-asked write permission is never a refusal', (tester) async {
      final probe = buildPermissionProbe();
      final binding = HealthSyncBinding(FakeSettingsStore());

      for (final wire in ['granted', 'notAsked']) {
        permissionResult = wire;
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpScreen(tester, binding: binding, permissionProbe: probe);

        const statusKey = ValueKey('health-sync-permission-status');
        expect(
          find.descendant(
            of: find.byKey(statusKey),
            matching: find.textContaining('denied'),
          ),
          findsNothing,
        );
        // The line reports the write/access state only — Apple's opaque read
        // authorization must never surface as a status.
        expect(
          find.descendant(
            of: find.byKey(statusKey),
            matching: find.textContaining('read'),
          ),
          findsNothing,
        );
      }
    });

    testWidgets('tapping the settings link opens the platform settings deep '
        'link', (tester) async {
      permissionResult = 'denied';
      final binding = HealthSyncBinding(FakeSettingsStore());
      await pumpScreen(
        tester,
        binding: binding,
        permissionProbe: buildPermissionProbe(),
      );

      await tester.tap(find.byKey(const ValueKey('health-sync-open-settings')));
      await tester.pumpAndSettle();

      expect(
        permissionCalls.map((call) => call.method),
        contains('openPermissionSettings'),
      );
    });

    testWidgets('a revoked write permission updates the line after an import '
        '(Issue #959)', (tester) async {
      final importer = _FakeImporter(
        const HealthImportSummary(samplesRead: 1, daysWritten: 1),
      );
      permissionResult = 'granted';
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(
        tester,
        binding: binding,
        importer: importer,
        permissionProbe: buildPermissionProbe(),
      );

      expect(find.text('Health app access: granted'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('health-sync-open-settings')),
        findsNothing,
      );

      // The OS permission is revoked while the screen is open; the import
      // pass re-reads the status and the line follows.
      permissionResult = 'denied';
      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      expect(
        find.text('Health app access: denied — open Settings to change'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('health-sync-open-settings')),
        findsOneWidget,
      );
    });

    testWidgets('no probe means no status line or settings link (an '
        'unconfigured build)', (tester) async {
      final binding = HealthSyncBinding(FakeSettingsStore());
      await pumpScreen(tester, binding: binding);

      expect(
        find.byKey(const ValueKey('health-sync-permission-status')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('health-sync-open-settings')),
        findsNothing,
      );
    });
  });

  group('Issue #1001 platform-specific health store copy', () {
    testWidgets(
        'iOS renders Health app sync in app bar and the Health app in import tile',
        (tester) async {
      final binding = HealthSyncBinding(FakeSettingsStore());
      await binding.bind(
        profile: profiles.firstWhere((p) => p.id == 'eligible'),
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: false,
      );
      final importer = _FakeImporter(
        const HealthImportSummary(),
        platform: HealthImportPlatform.appleHealth,
      );
      await pumpScreen(
        tester,
        binding: binding,
        importer: importer,
        writeEnabled: true,
      );

      expect(find.text('Health app sync'), findsOneWidget);
      expect(find.text('Import from the Health app'), findsOneWidget);
      expect(
        find.text(
          "Choose the one profile whose data this phone may ever write to its "
          "Health app. Every other profile stays out of this phone's Health app "
          'entirely.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'Android renders Health Connect sync in app bar, intro, and import tile',
        (tester) async {
      final binding = HealthSyncBinding(FakeSettingsStore());
      await binding.bind(
        profile: profiles.firstWhere((p) => p.id == 'eligible'),
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: false,
      );
      final importer = _FakeImporter(
        const HealthImportSummary(),
        platform: HealthImportPlatform.healthConnect,
      );
      await pumpScreen(
        tester,
        binding: binding,
        importer: importer,
        writeEnabled: false,
      );

      expect(find.text('Health Connect sync'), findsOneWidget);
      expect(find.text('Import from Health Connect'), findsOneWidget);
      expect(
        find.text(
          'Choose the one profile this phone may import health data into. Every '
          'other profile stays out of Health Connect entirely.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('bind dialog references platform health store', (tester) async {
      final binding = HealthSyncBinding(FakeSettingsStore());
      // iOS bind dialog
      await pumpScreen(tester, binding: binding, writeEnabled: true);
      await tester.tap(find.byKey(const ValueKey('health-sync-profile-eligible')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          "Only Alice's data will ever be written to the Health app. This phone "
          'can sync one profile at a time — choosing a different profile later '
          'replaces this one.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Android bind dialog
      await pumpScreen(tester, binding: binding, writeEnabled: false);
      await tester.tap(find.byKey(const ValueKey('health-sync-profile-eligible')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          "Only Alice's data will ever be imported from Health Connect. This "
          'phone can sync one profile at a time — choosing a different profile '
          'later replaces this one.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('unbind dialog references platform health store', (tester) async {
      final binding = HealthSyncBinding(FakeSettingsStore());
      await binding.bind(
        profile: profiles.firstWhere((p) => p.id == 'eligible'),
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: false,
      );

      // iOS unbind dialog
      await pumpScreen(tester, binding: binding, writeEnabled: true);
      await tester.tap(find.byKey(const ValueKey('health-sync-unbind-tile')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This phone will stop writing data for Alice to the Health app and '
          'stop importing from it. Nothing already logged in lunarlog, or '
          'already written to the Health app, is deleted.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Android unbind dialog
      await pumpScreen(tester, binding: binding, writeEnabled: false);
      await tester.tap(find.byKey(const ValueKey('health-sync-unbind-tile')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This phone will stop importing data for Alice from Health Connect. '
          'Nothing already logged is deleted.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });
  // Issue #1478: Android writes to Health Connect. The write screen there
  // must describe what Android does, in Health Connect's name — and the
  // status line must not say "denied" before anyone has been asked.
  group('Issue #1478 Android writes to Health Connect', () {
    Future<HealthSyncBinding> boundBinding() async {
      final binding = HealthSyncBinding(FakeSettingsStore());
      await binding.bind(
        profile: profiles.firstWhere((p) => p.id == 'eligible'),
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: false,
      );
      return binding;
    }

    Future<void> pumpAndroid(
      WidgetTester tester, {
      required HealthSyncBinding binding,
      HealthPermissionProbe? permissionProbe,
    }) =>
        pumpScreen(
          tester,
          binding: binding,
          importer: _FakeImporter(
            const HealthImportSummary(),
            platform: HealthImportPlatform.healthConnect,
          ),
          permissionProbe: permissionProbe,
          writeEnabled: true,
          storePlatform: HealthImportPlatform.healthConnect,
          viewport: const Size(800, 2400),
        );

    /// Every string the screen (and any open dialog) currently shows.
    Iterable<String> shown(WidgetTester tester) => tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data ?? '');

    testWidgets('nothing on the Android write screen says "Health app"',
        (tester) async {
      permissionResult = 'granted';
      await pumpAndroid(
        tester,
        binding: await boundBinding(),
        permissionProbe: buildPermissionProbe(),
      );

      expect(shown(tester), isNotEmpty);
      expect(
        shown(tester).where((text) => text.contains('Health app')),
        isEmpty,
        reason: 'that is the iPhone store; Android writes to Health Connect',
      );
      expect(find.text('Health Connect sync'), findsOneWidget);
      expect(
        find.text(
          'Choose the one profile whose data this phone may ever write to '
          'Health Connect. Every other profile stays out of Health Connect '
          'entirely.',
        ),
        findsOneWidget,
      );
      expect(find.text('Health Connect access: granted'), findsOneWidget);
      expect(
        find.textContaining("removing lunarlog's access in Health Connect"),
        findsOneWidget,
      );
    });

    testWidgets('it never claims symptoms are written — it says they are not',
        (tester) async {
      await pumpAndroid(tester, binding: await boundBinding());

      expect(
        find.byKey(const ValueKey('health-sync-symptoms-copy')),
        findsNothing,
        reason: 'the iPhone "written as symptom entries" paragraph',
      );
      expect(
        shown(tester).where((text) => text.contains('symptom entries')),
        isEmpty,
      );
      expect(
        shown(tester).where((text) => text.contains('Mood Changes')),
        isEmpty,
      );
      expect(
        find.byKey(const ValueKey('health-sync-symptoms-android-limitation')),
        findsOneWidget,
      );
      expect(
        find.textContaining("can't be written to Health Connect"),
        findsOneWidget,
      );
    });

    testWidgets('it lists what Android writes, in Health Connect\'s own names',
        (tester) async {
      await pumpAndroid(tester, binding: await boundBinding());

      final written = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('health-sync-written-types-copy')),
          matching: find.byType(Text),
        ),
      );
      // The five things the adapter writes (HealthConnectAdapter.kt's
      // writtenRecordTypes): flow + period, spotting between periods,
      // cervical mucus, ovulation tests, basal body temperature.
      for (final name in [
        'flow',
        'first and last day of each period',
        '(Menstruation)',
        '(Spotting)',
        '(Cervical mucus)',
        'ovulation test results',
        'basal body temperature',
      ]) {
        expect(written.data, contains(name));
      }
      expect(written.data, isNot(contains('ymptom')));

      // The lossy mappings, without the iPhone store's name.
      expect(
        find.text(
          'Super heavy days are written as Heavy flow. Spotting logged inside '
          'a period is written as Light flow. A peak ovulation test is '
          'written as Positive.',
        ),
        findsOneWidget,
      );
      // Forward-only, dated from write access (not from "sync turned on":
      // the clock starts when the write permissions are granted), and the
      // import named for Health Connect.
      expect(
        find.textContaining('Only days logged after you allow lunarlog to '
            'write to Health Connect are written'),
        findsOneWidget,
      );
      expect(
        find.textContaining('import menstrual flow and spotting from Health '
            'Connect'),
        findsOneWidget,
      );
    });

    // Issue #1491. On Android the background import is gated on the reads
    // it performs, no longer on the write permissions, so the promise holds
    // for someone who allowed reading only — and the sentence names what it
    // does depend on, in the words Health Connect's own screens use.
    testWidgets('the background-import promise names the reads and the '
        'background access it depends on, and no write permission',
        (tester) async {
      await pumpAndroid(tester, binding: await boundBinding());

      final forwardOnly = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('health-sync-forward-only-copy')),
          matching: find.byType(Text),
        ),
      );
      const promise = 'after it lunarlog keeps the import current in the '
          'background';
      expect(forwardOnly.data, contains(promise));
      final condition = forwardOnly.data!.substring(
        forwardOnly.data!.indexOf(promise) + promise.length,
      );
      expect(
        condition,
        ', as long as Health Connect allows it to read Menstruation and '
        'Spotting and to access data in the background.',
      );
      expect(condition, isNot(contains('write')));
    });

    testWidgets('the scope note makes the same promise with a condition, on '
        'both stores, naming neither', (tester) async {
      const note = 'Imports everything the health store makes available, not '
          'a recent window — and, once you have run it once, keeps itself '
          'current in the background as long as it still has the permissions '
          'it needs for that.';
      Text scopeNote() => tester.widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('health-sync-full-history-copy')),
              matching: find.byType(Text),
            ),
          );

      await pumpAndroid(tester, binding: await boundBinding());
      expect(scopeNote().data, note);

      await tester.pumpWidget(const SizedBox.shrink());
      await pumpScreen(
        tester,
        binding: HealthSyncBinding(FakeSettingsStore()),
        writeEnabled: true,
        storePlatform: HealthImportPlatform.appleHealth,
      );
      expect(scopeNote().data, note);
    });

    // The review of #1478 (decision G): a period that began before write
    // access is written with its true first day, and the screen has to say
    // so — it is the one way anything logged earlier reaches Health Connect.
    testWidgets('it says what a period record covers, and that imported '
        'days are never written back', (tester) async {
      await pumpAndroid(tester, binding: await boundBinding());

      final note = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('health-sync-period-record-copy')),
          matching: find.byType(Text),
        ),
      );
      expect(
        note.data,
        'Once a day in a period is written, the first and last day you logged '
        'in lunarlog for that period are written with it, even if the period '
        'began before you allowed lunarlog to write. Days imported from Health '
        'Connect are never written back and never count towards a period '
        'lunarlog writes.',
      );

      // An iPhone has no period record: the note is Health Connect's alone.
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpScreen(
        tester,
        binding: HealthSyncBinding(FakeSettingsStore()),
        writeEnabled: true,
        storePlatform: HealthImportPlatform.appleHealth,
      );
      expect(
        find.byKey(const ValueKey('health-sync-period-record-copy')),
        findsNothing,
      );
    });

    testWidgets('the store decides the wording, not the write flag: with '
        'writes on and no importer, Health Connect gets its own copy and the '
        'iPhone keeps its own', (tester) async {
      final binding = HealthSyncBinding(FakeSettingsStore());
      // Before #1478 "writes on, no importer" could only mean Apple Health.
      await pumpScreen(
        tester,
        binding: binding,
        writeEnabled: true,
        storePlatform: HealthImportPlatform.healthConnect,
      );

      expect(find.text('Health Connect sync'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('health-sync-written-types-copy')),
        findsOneWidget,
      );
      expect(
        shown(tester).where((text) => text.contains('Health app')),
        isEmpty,
      );

      // The same screen for the iPhone store: none of the Android wording
      // leaks over, and the symptom-write paragraph stays. Since Issue
      // #1526 the iPhone has a list of what is written too, in its own
      // words.
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpScreen(
        tester,
        binding: binding,
        writeEnabled: true,
        storePlatform: HealthImportPlatform.appleHealth,
      );

      expect(find.text('Health app sync'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('health-sync-written-types-copy')),
          matching: find.text(AppLocalizationsEn().healthSyncWrittenTypes),
        ),
        findsOneWidget,
      );
      expect(
        find.text(AppLocalizationsEn().healthSyncWrittenTypesHealthConnect),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('health-sync-symptoms-copy')),
        findsOneWidget,
      );
      expect(
        shown(tester).where((text) => text.contains('Health Connect')),
        isEmpty,
      );
    });

    testWidgets('binding and unbinding on Android name Health Connect as the '
        'store being written to', (tester) async {
      final binding = HealthSyncBinding(FakeSettingsStore());
      await pumpAndroid(tester, binding: binding);

      await tester.tap(
        find.byKey(const ValueKey('health-sync-profile-eligible')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          "Only Alice's data will ever be written to Health Connect. This "
          'phone can sync one profile at a time — choosing a different '
          'profile later replaces this one.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('health-sync-confirm-bind')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('health-sync-unbind-tile')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This phone will stop writing data for Alice to Health Connect and '
          'stop importing from it. Nothing already logged in lunarlog, or '
          'already written to Health Connect, is deleted.',
        ),
        findsOneWidget,
      );
      expect(
        shown(tester).where((text) => text.contains('Health app')),
        isEmpty,
      );
    });

    testWidgets('"not yet asked" before the sheet, then the line follows the '
        'answer given on Health Connect\'s own screens: it is read again '
        'when the app comes back, and only then', (tester) async {
      int statusReads() => permissionCalls
          .where((call) => call.method == 'permissionStatus')
          .length;

      // A fresh install: nobody has been asked, so nothing is "denied" and
      // there is nothing in Settings to change yet.
      permissionResult = 'notAsked';
      await pumpAndroid(
        tester,
        binding: await boundBinding(),
        permissionProbe: buildPermissionProbe(),
      );
      expect(
        find.text('Health Connect access: not yet asked'),
        findsOneWidget,
      );
      expect(
        shown(tester).where((text) => text.contains('denied')),
        isEmpty,
      );
      expect(
        find.byKey(const ValueKey('health-sync-open-settings')),
        findsNothing,
      );
      final readsAfterLoad = statusReads();

      // The write path raises the permission sheet a moment after the
      // profile is bound. Going behind it reads nothing...
      permissionResult = 'granted';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(statusReads(), readsAfterLoad);
      expect(
        find.text('Health Connect access: not yet asked'),
        findsOneWidget,
      );

      // ...and coming back, with access allowed, reads it once.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(statusReads(), readsAfterLoad + 1);
      expect(find.text('Health Connect access: granted'), findsOneWidget);
      expect(find.text('Health Connect access: not yet asked'), findsNothing);

      // And the other way: access removed in Health Connect's settings.
      permissionResult = 'denied';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(
        find.text('Health Connect access: denied — open Settings to change'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('health-sync-open-settings')),
        findsOneWidget,
      );
    });
  });

  // Issue #1515. The status line was the write answer alone, so on Android
  // someone who let lunarlog read from Health Connect and not write to it
  // was told "access: denied" while her import was working. Health Connect
  // says which reads are granted, so there the line tells the two
  // directions apart. Apple Health does not, so on an iPhone the line stays
  // exactly what it was.
  group('Issue #1515 the status line tells reading from writing', () {
    const readingOnly = 'Health Connect access: reading only, so lunarlog '
        "can import but can't write — open Settings to change";
    const writingOnly = 'Health Connect access: writing only, so lunarlog '
        "can write but can't import — open Settings to change";
    const statusKey = ValueKey('health-sync-permission-status');
    const settingsKey = ValueKey('health-sync-open-settings');

    Future<HealthSyncBinding> boundBinding() async {
      final binding = HealthSyncBinding(FakeSettingsStore());
      await binding.bind(
        profile: profiles.firstWhere((p) => p.id == 'eligible'),
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: false,
      );
      return binding;
    }

    Future<void> pumpAndroid(
      WidgetTester tester, {
      required HealthSyncBinding binding,
      required HealthPermissionProbe permissionProbe,
      HealthImportRunner? importer,
    }) =>
        pumpScreen(
          tester,
          binding: binding,
          importer: importer ??
              _FakeImporter(
                const HealthImportSummary(),
                platform: HealthImportPlatform.healthConnect,
              ),
          permissionProbe: permissionProbe,
          writeEnabled: true,
          storePlatform: HealthImportPlatform.healthConnect,
          viewport: const Size(800, 2400),
        );

    Future<void> pumpIphone(
      WidgetTester tester, {
      required HealthPermissionProbe permissionProbe,
    }) =>
        pumpScreen(
          tester,
          binding: HealthSyncBinding(FakeSettingsStore()),
          permissionProbe: permissionProbe,
          writeEnabled: true,
          storePlatform: HealthImportPlatform.appleHealth,
        );

    String statusLine(WidgetTester tester) => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(statusKey),
            matching: find.byType(Text),
          ),
        )
        .data!;

    // The case the issue is about, through the real channel adapter and the
    // method names the Kotlin half answers. Before #1515 this read "Health
    // Connect access: denied — open Settings to change".
    testWidgets('reads on, writes off: the line does not say denied — it '
        'says reading is on and writing is off, and keeps the way into '
        'Settings', (tester) async {
      // Health Connect holds the two reads and no write permission.
      permissionResult = 'denied';
      importPermissionResult = 'granted';
      await pumpAndroid(
        tester,
        binding: await boundBinding(),
        permissionProbe: buildPermissionProbe(),
      );

      expect(statusLine(tester), isNot(contains('denied')));
      expect(statusLine(tester), readingOnly);
      expect(find.byKey(settingsKey), findsOneWidget);

      await tester.tap(find.byKey(settingsKey));
      await tester.pumpAndSettle();
      expect(
        permissionCalls.map((call) => call.method),
        contains('openPermissionSettings'),
      );
    });

    testWidgets('Android: every case of the two answers, and which of them '
        'offer the settings link', (tester) async {
      final binding = await boundBinding();
      for (final (write, read, expected, settingsLink) in [
        // Writes granted: unchanged while reading is on too.
        ('granted', 'granted', 'Health Connect access: granted', false),
        // Writes not granted, reads granted: the new state — whether she
        // declined the writes or has not been asked for them yet.
        ('denied', 'granted', readingOnly, true),
        ('notAsked', 'granted', readingOnly, true),
        // Neither granted, never asked: unchanged.
        (
          'notAsked',
          'notAsked',
          'Health Connect access: not yet asked',
          false,
        ),
        // Neither granted, asked: unchanged.
        (
          'denied',
          'denied',
          'Health Connect access: denied — open Settings to change',
          true,
        ),
        // Asked for the reads by Import and declined them, not yet asked
        // for the writes: the write path will still ask, so not "denied".
        (
          'notAsked',
          'denied',
          'Health Connect access: not yet asked',
          false,
        ),
        // Writes granted, reads not: writing works and the import does not,
        // so a bare "granted" would mislead.
        ('granted', 'denied', writingOnly, true),
        // A read side that cannot answer leaves the write answer alone.
        ('granted', 'unavailable', 'Health Connect access: granted', false),
        (
          'denied',
          'unavailable',
          'Health Connect access: denied — open Settings to change',
          true,
        ),
        // No write answer at all: nothing is claimed about either side.
        (
          'unavailable',
          'granted',
          'Health Connect access is not available on this device.',
          false,
        ),
      ]) {
        permissionResult = write;
        importPermissionResult = read;
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpAndroid(
          tester,
          binding: binding,
          permissionProbe: buildPermissionProbe(),
        );

        expect(statusLine(tester), expected, reason: 'write=$write read=$read');
        expect(
          find.byKey(settingsKey),
          settingsLink ? findsOneWidget : findsNothing,
          reason: 'write=$write read=$read',
        );
      }
    });

    testWidgets('Android: the line follows an answer given on Health '
        'Connect\'s own screens when the app comes back', (tester) async {
      permissionResult = 'denied';
      importPermissionResult = 'denied';
      await pumpAndroid(
        tester,
        binding: await boundBinding(),
        permissionProbe: buildPermissionProbe(),
      );
      expect(
        statusLine(tester),
        'Health Connect access: denied — open Settings to change',
      );

      // She turns the two reads on in Health Connect and comes back.
      importPermissionResult = 'granted';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(statusLine(tester), readingOnly);

      // Then the writes too.
      permissionResult = 'granted';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(statusLine(tester), 'Health Connect access: granted');
      expect(find.byKey(settingsKey), findsNothing);
    });

    testWidgets('Android: the answers are read again after an import, so '
        'reads allowed while it ran move the line from denied to reading '
        'only without leaving the screen', (tester) async {
      permissionResult = 'denied';
      importPermissionResult = 'denied';
      await pumpAndroid(
        tester,
        binding: await boundBinding(),
        permissionProbe: buildPermissionProbe(),
        importer: _FakeImporter(
          const HealthImportSummary(samplesRead: 1, daysWritten: 1),
          platform: HealthImportPlatform.healthConnect,
        ),
      );
      expect(
        statusLine(tester),
        'Health Connect access: denied — open Settings to change',
      );

      // The import asks for the reads and she allows them; the pass then
      // re-reads both answers.
      importPermissionResult = 'granted';
      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      expect(statusLine(tester), readingOnly);
      expect(find.byKey(settingsKey), findsOneWidget);
    });

    // Issue #1523. A second import with nothing new showed "Health Connect
    // returned no menstrual-flow data. This can mean nothing was tracked,
    // or that read access is off." to someone whose first import was on her
    // calendar and whose status line, on the same screen, said reading was
    // on. After the first import Health Connect is asked only for what
    // changed, so an empty answer means nothing changed.
    group('Issue #1523 an import that brings nothing back', () {
      const nothingNew =
          'Nothing new to import from Health Connect since the last import.';
      const nothingToImport = 'Health Connect has no menstrual flow or '
          'spotting from other apps to import.';
      final neutralHealthConnect = healthImportEmptyCopy(
        AppLocalizationsEn(),
        HealthImportPlatform.healthConnect,
      );
      final neutralAppleHealth = healthImportEmptyCopy(
        AppLocalizationsEn(),
        HealthImportPlatform.appleHealth,
      );

      // The result line is the summary's first text. A result that says
      // older data is hidden has a button under it.
      String resultLine(WidgetTester tester) => tester
          .widget<Text>(
            find
                .descendant(
                  of: find.byKey(
                    const ValueKey('health-sync-import-summary'),
                  ),
                  matching: find.byType(Text),
                )
                .first,
          )
          .data!;
      final resultSettings =
          find.byKey(const ValueKey('health-sync-import-open-settings'));
      // Issue #1573: the button a result brings first raises Health
      // Connect's own prompt. Settings is what is left after it.
      final resultAllow =
          find.byKey(const ValueKey('health-sync-import-allow-past-data'));

      Future<void> leaveAndComeBack(WidgetTester tester) async {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpAndSettle();
      }

      Future<String> importAndReadResult(WidgetTester tester) async {
        await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
        await tester.pumpAndSettle();
        return resultLine(tester);
      }

      _FakeImporter androidImporter(HealthImportSummary summary) =>
          _FakeImporter(summary, platform: HealthImportPlatform.healthConnect);

      // Issue #1599. The screen learns which profile is bound when it
      // loads and does not watch it. With the profile gone since, the
      // import reads nothing, and its result used to be the line for an
      // empty store: a statement about a store nobody had looked at.
      group('Issue #1599 no profile is bound any more', () {
        const noProfileHealthConnect = 'Nothing was imported. No profile is '
            'syncing with Health Connect on this phone any more. Choose a '
            'profile above to sync it.';
        const noProfileAppleHealth = 'Nothing was imported. No profile is '
            'syncing with the Health app on this phone any more. Choose a '
            'profile above to sync it.';
        final importTile = find.byKey(const ValueKey('health-sync-import-tile'));
        final unbindTile = find.byKey(const ValueKey('health-sync-unbind-tile'));

        void expectNoLineAboutTheStore() {
          for (final line in [
            nothingNew,
            nothingToImport,
            neutralHealthConnect,
            neutralAppleHealth,
          ]) {
            expect(find.text(line), findsNothing, reason: line);
          }
          expect(find.textContaining('older data'), findsNothing);
          expect(resultAllow, findsNothing);
          expect(resultSettings, findsNothing);
          expect(find.byType(SnackBar), findsNothing);
        }

        testWidgets('Android: the result says so, says nothing about what '
            'Health Connect holds, and the screen shows nothing chosen',
            (tester) async {
          final binding = await boundBinding();
          await pumpAndroid(
            tester,
            binding: binding,
            // Reading allowed and older data hidden: what gave the "nothing
            // to import" line and the button under it.
            permissionProbe: _ScriptedProbe(
              readAccessDisclosed: true,
              write: HealthPermissionStatus.granted,
              read: HealthPermissionStatus.granted,
              reachesPastData: false,
            ),
            importer: androidImporter(const HealthImportSummary(bound: false)),
          );
          expect(importTile, findsOneWidget);
          // The binding goes away behind the open screen.
          await binding.unbind();

          expect(await importAndReadResult(tester), noProfileHealthConnect);
          expectNoLineAboutTheStore();
          // Loaded again: nothing is chosen now, so there is nothing to
          // import into and nothing to stop.
          expect(importTile, findsNothing);
          expect(unbindTile, findsNothing);
          expect(
            find.byKey(const ValueKey('health-sync-profile-eligible')),
            findsOneWidget,
          );
        });

        testWidgets('iPhone: the same, naming the Health app', (tester) async {
          final binding = await boundBinding();
          await pumpScreen(
            tester,
            binding: binding,
            importer: _FakeImporter(const HealthImportSummary(bound: false)),
            permissionProbe: _ScriptedProbe(
              readAccessDisclosed: false,
              write: HealthPermissionStatus.granted,
              read: HealthPermissionStatus.granted,
            ),
            writeEnabled: true,
            storePlatform: HealthImportPlatform.appleHealth,
            viewport: const Size(800, 2400),
          );
          await binding.unbind();

          expect(await importAndReadResult(tester), noProfileAppleHealth);
          expectNoLineAboutTheStore();
          expect(importTile, findsNothing);
        });

        // Loading again is for the pass that found nothing bound. Any
        // other pass leaves the screen as it is.
        testWidgets('the screen is loaded again after that pass, and not '
            'after one that had a profile to import into', (tester) async {
          for (final (summary, loads) in const [
            (HealthImportSummary(bound: false), 2),
            (HealthImportSummary(incremental: true, pagesRead: 1), 1),
          ]) {
            final repository = CountingProfilesRepository(profiles);
            await pumpScreen(
              tester,
              binding: await boundBinding(),
              importer: androidImporter(summary),
              permissionProbe: _ScriptedProbe(
                readAccessDisclosed: true,
                write: HealthPermissionStatus.granted,
                read: HealthPermissionStatus.granted,
              ),
              profilesRepository: repository,
              writeEnabled: true,
              storePlatform: HealthImportPlatform.healthConnect,
              viewport: const Size(800, 2400),
            );
            expect(repository.lists, 1);

            await importAndReadResult(tester);

            expect(repository.lists, loads, reason: '${summary.bound}');
            await tester.pumpWidget(const SizedBox.shrink());
          }
        });

        // The stored id can also outlive its profile (deleted on another
        // device). The binding still names one, so the tiles stay; the
        // result is the same line.
        testWidgets('a binding whose profile is gone: the same line, and '
            'choosing a profile takes it down', (tester) async {
          await pumpAndroid(
            tester,
            binding: await boundBinding(),
            permissionProbe: _ScriptedProbe(
              readAccessDisclosed: true,
              write: HealthPermissionStatus.granted,
              read: HealthPermissionStatus.granted,
            ),
            importer: androidImporter(const HealthImportSummary(bound: false)),
          );

          expect(await importAndReadResult(tester), noProfileHealthConnect);
          expectNoLineAboutTheStore();
          expect(importTile, findsOneWidget);

          await tester.tap(
            find.byKey(const ValueKey('health-sync-profile-eligible')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('health-sync-confirm-bind')),
          );
          await tester.pumpAndSettle();
          expect(find.text(noProfileHealthConnect), findsNothing);
        });
      });

      testWidgets('Android: a repeat import with nothing new says so, and '
          'says nothing about access', (tester) async {
        await pumpAndroid(
          tester,
          binding: await boundBinding(),
          permissionProbe: _ScriptedProbe(
            readAccessDisclosed: true,
            write: HealthPermissionStatus.denied,
            read: HealthPermissionStatus.granted,
          ),
          importer: androidImporter(
            const HealthImportSummary(incremental: true, pagesRead: 1),
          ),
        );

        final line = await importAndReadResult(tester);
        expect(line, nothingNew);
        expect(line, isNot(contains('access')));
        expect(line, isNot(contains('returned no')));
        // The line above it still says what her access is.
        expect(statusLine(tester), readingOnly);
      });

      testWidgets('Android: a whole-history import that comes back empty '
          'while reading is allowed does not suggest access is off',
          (tester) async {
        await pumpAndroid(
          tester,
          binding: await boundBinding(),
          permissionProbe: _ScriptedProbe(
            readAccessDisclosed: true,
            write: HealthPermissionStatus.granted,
            read: HealthPermissionStatus.granted,
          ),
          importer: androidImporter(const HealthImportSummary(pagesRead: 1)),
        );

        final line = await importAndReadResult(tester);
        expect(line, nothingToImport);
        expect(line, isNot(contains('access')));
      });

      // Issue #1549. "Has no period or spotting data" is a claim about the
      // whole store. Health Connect hides data older than about a month
      // before the first grant unless "Access past data" is on, so with
      // it off an empty read proves nothing about what is in there.
      const olderHidden = 'Nothing to import that lunarlog can see. Health '
          'Connect hides older data from lunarlog unless "Access past '
          'data" is on for it.';

      testWidgets('Android: with "Access past data" off, an empty import '
          'does not say the store is empty', (tester) async {
        final probe = _ScriptedProbe(
          readAccessDisclosed: true,
          write: HealthPermissionStatus.granted,
          read: HealthPermissionStatus.granted,
          reachesPastData: false,
        );
        await pumpAndroid(
          tester,
          binding: await boundBinding(),
          permissionProbe: probe,
          importer: androidImporter(const HealthImportSummary(pagesRead: 1)),
        );

        // Not asked when the screen opens: it is a question about a read.
        expect(probe.pastDataProbes, 0);

        final line = await importAndReadResult(tester);
        expect(line, olderHidden);
        expect(line, isNot(contains('has no')));
        expect(probe.pastDataProbes, 1);
        // It does not say reading is off either: the status line above
        // says it is on.
        expect(line, isNot(contains('read access is off')));
      });

      testWidgets('Android: when it cannot tell whether past data is '
          'readable, it does not say the store is empty', (tester) async {
        await pumpAndroid(
          tester,
          binding: await boundBinding(),
          permissionProbe: _ScriptedProbe(
            readAccessDisclosed: true,
            write: HealthPermissionStatus.granted,
            read: HealthPermissionStatus.granted,
            pastDataThrows: true,
          ),
          importer: androidImporter(const HealthImportSummary(pagesRead: 1)),
        );

        expect(await importAndReadResult(tester), olderHidden);
      });

      testWidgets('Android: turning "Access past data" on changes what '
          'the next empty import says', (tester) async {
        final probe = _ScriptedProbe(
          readAccessDisclosed: true,
          write: HealthPermissionStatus.granted,
          read: HealthPermissionStatus.granted,
          reachesPastData: false,
        );
        await pumpAndroid(
          tester,
          binding: await boundBinding(),
          permissionProbe: probe,
          importer: androidImporter(const HealthImportSummary(pagesRead: 1)),
        );
        expect(await importAndReadResult(tester), olderHidden);

        // She turns it on in Health Connect, and imports again. The
        // adapter then reads the whole history once more (the Kotlin
        // rule `pastReadStep`), and the screen asks again after
        // every pass.
        probe.reachesPastData = true;
        expect(await importAndReadResult(tester), nothingToImport);
        expect(resultSettings, findsNothing);
        expect(resultAllow, findsNothing);
      });

      testWidgets('Android: a result is about its own pass, and coming '
          'back from Settings does not rewrite it', (tester) async {
        final probe = _ScriptedProbe(
          readAccessDisclosed: true,
          write: HealthPermissionStatus.granted,
          read: HealthPermissionStatus.granted,
          reachesPastData: false,
        );
        await pumpAndroid(
          tester,
          binding: await boundBinding(),
          permissionProbe: probe,
          importer: androidImporter(const HealthImportSummary(pagesRead: 1)),
        );
        expect(await importAndReadResult(tester), olderHidden);

        // She follows the line: turns "Access past data" on and comes
        // back. Nothing new has been read, so the result must not turn
        // into "Health Connect has no…".
        probe.reachesPastData = true;
        await leaveAndComeBack(tester);
        expect(resultLine(tester), olderHidden);
      });

      testWidgets('Android: a pass that ran while reading was off is not '
          'rewritten when reading is turned on', (tester) async {
        final probe = _ScriptedProbe(
          readAccessDisclosed: true,
          write: HealthPermissionStatus.granted,
          read: HealthPermissionStatus.denied,
        );
        await pumpAndroid(
          tester,
          binding: await boundBinding(),
          permissionProbe: probe,
          importer: androidImporter(const HealthImportSummary(pagesRead: 1)),
        );
        expect(await importAndReadResult(tester), neutralHealthConnect);

        probe.read = HealthPermissionStatus.granted;
        await leaveAndComeBack(tester);
        // That pass read nothing because it was not allowed to. It says
        // nothing about what the store holds.
        expect(resultLine(tester), neutralHealthConnect);
      });

      testWidgets('Android: the line that names the switch brings the way '
          'to it, even when no permission is off', (tester) async {
        // Reading and writing both allowed: the status line offers no
        // settings link, because nothing there is off.
        final probe = _ScriptedProbe(
          readAccessDisclosed: true,
          write: HealthPermissionStatus.granted,
          read: HealthPermissionStatus.granted,
          reachesPastData: false,
        );
        await pumpAndroid(
          tester,
          binding: await boundBinding(),
          permissionProbe: probe,
          importer: androidImporter(const HealthImportSummary(pagesRead: 1)),
        );
        expect(
          find.byKey(const ValueKey('health-sync-open-settings')),
          findsNothing,
        );
        expect(resultSettings, findsNothing);

        expect(resultAllow, findsNothing);

        expect(await importAndReadResult(tester), olderHidden);
        expect(resultAllow, findsOneWidget);
        expect(resultSettings, findsNothing);
        expect(probe.settingsOpened, 0);
      });

      // Issue #1557. The line and the button used to appear on one result
      // only, the empty whole-history one. Someone whose first import
      // brought recent days in was told nothing about the older ones, and
      // someone who had imported with the switch off only ever saw "nothing
      // new since the last import".
      const olderHint =
          'Health Connect hides older data from lunarlog unless '
          '"Access past data" is on for it.';

      Future<void> importWith(
        WidgetTester tester, {
        required bool? reachesPastData,
        required HealthImportSummary summary,
        HealthPermissionStatus read = HealthPermissionStatus.granted,
      }) async {
        await pumpAndroid(
          tester,
          binding: await boundBinding(),
          permissionProbe: _ScriptedProbe(
            readAccessDisclosed: true,
            write: HealthPermissionStatus.granted,
            read: read,
            reachesPastData: reachesPastData ?? false,
            pastDataThrows: reachesPastData == null,
          ),
          importer: androidImporter(summary),
        );
        await importAndReadResult(tester);
      }

      const broughtDaysIn = HealthImportSummary(
        pagesRead: 1,
        samplesRead: 2,
        daysWritten: 2,
      );
      const nothingSince = HealthImportSummary(incremental: true, pagesRead: 1);

      testWidgets('Android: an import that brought days in with the switch '
          'off says older data is hidden, and offers to allow it',
          (tester) async {
        await importWith(tester,
            reachesPastData: false, summary: broughtDaysIn);
        // In the result, and announced in the snackbar as well.
        expect(find.text('Imported 2 days.'), findsWidgets);
        expect(find.text(olderHint), findsOneWidget);
        expect(resultAllow, findsOneWidget);
        expect(resultSettings, findsNothing);
      });

      testWidgets('Android: a repeat import with the switch off says so too',
          (tester) async {
        await importWith(tester, reachesPastData: false, summary: nothingSince);
        expect(find.text(nothingNew), findsOneWidget);
        expect(find.text(olderHint), findsOneWidget);
        expect(resultAllow, findsOneWidget);
        expect(resultSettings, findsNothing);
      });

      testWidgets('Android: when it cannot tell, it says the same',
          (tester) async {
        await importWith(tester, reachesPastData: null, summary: broughtDaysIn);
        expect(find.text(olderHint), findsOneWidget);
        expect(resultAllow, findsOneWidget);
        expect(resultSettings, findsNothing);
      });

      testWidgets('Android: with the switch on, no result carries the line or '
          'the button', (tester) async {
        for (final summary in [broughtDaysIn, nothingSince]) {
          await importWith(tester, reachesPastData: true, summary: summary);
          expect(find.text(olderHint), findsNothing);
          expect(resultSettings, findsNothing);
          expect(resultAllow, findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      });

      testWidgets('Android: the empty whole-history result says it once, in '
          'its own sentence', (tester) async {
        await importWith(
          tester,
          reachesPastData: false,
          summary: const HealthImportSummary(pagesRead: 1),
        );
        expect(find.text(olderHidden), findsOneWidget);
        expect(find.text(olderHint), findsNothing);
        expect(resultAllow, findsOneWidget);
        expect(resultSettings, findsNothing);
      });

      testWidgets('Android: reading not allowed gets neither: the status '
          'line already says what is off', (tester) async {
        await importWith(
          tester,
          reachesPastData: false,
          summary: broughtDaysIn,
          read: HealthPermissionStatus.denied,
        );
        expect(find.text(olderHint), findsNothing);
        expect(resultSettings, findsNothing);
        expect(resultAllow, findsNothing);
      });

      // Issue #1573. The button used to open Health Connect's first
      // screen, three taps from the switch. It now raises Health Connect's
      // own prompt for that one permission.
      group('the button under a result (#1573)', () {
        const stillOff = '"Access past data" is still off. You can turn it '
            'on for lunarlog in Health Connect.';
        const recentOnly = 'Health Connect on this phone hides older data '
            'from lunarlog, and has no setting to change that.';

        _ScriptedProbe switchOff() => _ScriptedProbe(
              readAccessDisclosed: true,
              write: HealthPermissionStatus.granted,
              read: HealthPermissionStatus.granted,
              reachesPastData: false,
            );

        Future<void> importOn(
          WidgetTester tester,
          _ScriptedProbe probe,
          _FakeImporter importer,
        ) async {
          await pumpAndroid(
            tester,
            binding: await boundBinding(),
            permissionProbe: probe,
            importer: importer,
          );
          await importAndReadResult(tester);
        }

        testWidgets('asks Health Connect, and a grant runs the import again',
            (tester) async {
          final probe = switchOff();
          final importer = androidImporter(broughtDaysIn)
            ..grantsPastData = true
            ..onPastDataGranted = () => probe.reachesPastData = true;
          await importOn(tester, probe, importer);
          expect(find.text('Allow access to past data'), findsOneWidget);
          expect(importer.pastDataRequests, 0,
              reason: 'nothing is asked until she taps');

          await tester.tap(resultAllow);
          await tester.pumpAndSettle();

          expect(importer.pastDataRequests, 1);
          expect(importer.calls, 2,
              reason: 'the import she asked the older data for');
          expect(find.text(olderHint), findsNothing);
          expect(resultAllow, findsNothing);
          expect(resultSettings, findsNothing);
          expect(probe.settingsOpened, 0);
        });

        testWidgets('when the switch is still off afterwards, it says so and '
            'offers Settings', (tester) async {
          final probe = switchOff();
          final importer = androidImporter(broughtDaysIn);
          await importOn(tester, probe, importer);

          await tester.tap(resultAllow);
          await tester.pumpAndSettle();

          expect(importer.pastDataRequests, 1);
          expect(importer.calls, 1, reason: 'no import: nothing changed');
          expect(find.text(olderHint), findsOneWidget);
          expect(find.text(stillOff), findsOneWidget);
          expect(resultAllow, findsNothing,
              reason: 'asking again would be dropped, or unwelcome');
          await tester.tap(resultSettings);
          await tester.pump();
          expect(probe.settingsOpened, 1);
        });

        // Issue #1616 item 3: she opens the removal confirmation, leaves
        // for Health Connect to turn the switch on, and confirms when she
        // is back — by then the resume has started an import, and the
        // removal used to be dropped without a word. It now runs when that
        // import finishes.
        testWidgets('a removal confirmed while the resumed import runs '
            'waits for it', (tester) async {
          final probe = switchOff();
          final importer = androidImporter(broughtDaysIn)..storeDeletedDays = 2;
          await importOn(tester, probe, importer);

          // She asks for the switch; it stays off.
          await tester.tap(resultAllow);
          await tester.pumpAndSettle();
          expect(resultSettings, findsOneWidget);

          // The offer's confirmation is open when she comes back.
          await tester.tap(
            find.byKey(const ValueKey('health-sync-store-deleted-remove')),
          );
          await tester.pumpAndSettle();
          final confirm =
              find.byKey(const ValueKey('health-sync-store-deleted-confirm'));

          // The switch is on now. Coming back starts an import, held open.
          probe.reachesPastData = true;
          importer.importGate = Completer<void>();
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.paused);
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          // No pumpAndSettle while the import runs: its progress bar never
          // settles.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          // She confirms while that import runs: it waits, not dropped.
          await tester.tap(confirm);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(importer.removed, isEmpty,
              reason: 'the running import comes first');

          importer.importGate!.complete();
          importer.importGate = null;
          await tester.pumpAndSettle();

          expect(importer.removed, hasLength(1),
              reason: 'it runs when the import finishes');
          expect(importer.removed.single.days, 2);
        });

        // Issue #1616 item 2: with the switch off, the read that precedes a
        // removal cannot see a record in Health Connect's hidden range, so
        // the confirmation says a day removed here can come back.
        testWidgets('the removal confirmation names the hidden range when '
            'the switch is off', (tester) async {
          final probe = switchOff();
          final importer = androidImporter(broughtDaysIn)..storeDeletedDays = 2;
          await importOn(tester, probe, importer);
          expect(find.text(olderHint), findsOneWidget,
              reason: 'the read ran with the switch off');

          await tester.tap(
            find.byKey(const ValueKey('health-sync-store-deleted-remove')),
          );
          await tester.pumpAndSettle();

          expect(
            find.text(
              'Older records may be hidden while Health Connect\'s "Access '
              'past data" setting is off, so a day removed here can come '
              'back after that setting is on and an import runs.',
            ),
            findsOneWidget,
          );
        });

        testWidgets('a request that fails ends the same way', (tester) async {
          final probe = switchOff();
          final importer = androidImporter(broughtDaysIn)
            ..pastDataRequestThrows = true;
          await importOn(tester, probe, importer);

          await tester.tap(resultAllow);
          await tester.pumpAndSettle();

          expect(find.text(stillOff), findsOneWidget);
          expect(resultSettings, findsOneWidget);
          expect(importer.calls, 1);
        });

        testWidgets('a new import starts over with the prompt', (tester) async {
          final probe = switchOff();
          final importer = androidImporter(broughtDaysIn);
          await importOn(tester, probe, importer);
          await tester.tap(resultAllow);
          await tester.pumpAndSettle();
          expect(resultSettings, findsOneWidget);

          await importAndReadResult(tester);

          expect(find.text(stillOff), findsNothing);
          expect(resultAllow, findsOneWidget);
          expect(resultSettings, findsNothing);
        });

        testWidgets('on a Health Connect with no such switch, it names none '
            'and offers nothing', (tester) async {
          final importer = androidImporter(broughtDaysIn)
            ..pastDataOffered = false;
          await importOn(tester, switchOff(), importer);

          expect(find.text(recentOnly), findsOneWidget);
          expect(find.textContaining('Access past data'), findsNothing);
          expect(resultAllow, findsNothing);
          expect(resultSettings, findsNothing);
        });

        testWidgets('and its empty whole-history result names none either',
            (tester) async {
          final importer =
              androidImporter(const HealthImportSummary(pagesRead: 1))
                ..pastDataOffered = false;
          await pumpAndroid(
            tester,
            binding: await boundBinding(),
            permissionProbe: switchOff(),
            importer: importer,
          );

          expect(
            await importAndReadResult(tester),
            'Nothing to import that lunarlog can see. $recentOnly',
          );
          expect(find.text(recentOnly), findsNothing,
              reason: 'said once, in the result line');
          expect(find.textContaining('Access past data'), findsNothing);
          expect(resultAllow, findsNothing);
        });

        testWidgets('whether there is a switch is asked only when a read did '
            'not reach the older data', (tester) async {
          final reaches = _ScriptedProbe(
            readAccessDisclosed: true,
            write: HealthPermissionStatus.granted,
            read: HealthPermissionStatus.granted,
          );
          final importer = androidImporter(broughtDaysIn);
          await importOn(tester, reaches, importer);
          expect(importer.pastDataOfferedProbes, 0);

          await tester.pumpWidget(const SizedBox.shrink());
          final other = androidImporter(broughtDaysIn);
          await importOn(tester, switchOff(), other);
          expect(other.pastDataOfferedProbes, 1);
        });

        testWidgets('while the prompt is up the button does nothing more, '
            'and a second tap raises no second prompt', (tester) async {
          final importer = androidImporter(broughtDaysIn)
            ..pastDataPrompt = Completer<void>();
          await importOn(tester, switchOff(), importer);

          await tester.tap(resultAllow);
          await tester.pump();
          expect(
            tester.widget<TextButton>(resultAllow).onPressed,
            isNull,
            reason: 'disabled while Health Connect\'s sheet is up',
          );
          await tester.tap(resultAllow, warnIfMissed: false);
          await tester.pump();
          expect(importer.pastDataRequests, 1);

          importer.pastDataPrompt!.complete();
          await tester.pumpAndSettle();
          expect(find.text(stillOff), findsOneWidget);
        });

        testWidgets('leaving the screen while the prompt is up is harmless',
            (tester) async {
          final importer = androidImporter(broughtDaysIn)
            ..grantsPastData = true
            ..pastDataPrompt = Completer<void>();
          await importOn(tester, switchOff(), importer);
          await tester.tap(resultAllow);
          await tester.pump();

          await tester.pumpWidget(const SizedBox.shrink());
          importer.pastDataPrompt!.complete();
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(importer.calls, 1, reason: 'no import for a screen that is gone');
        });

        // She follows "Open Settings", turns the switch on in Health
        // Connect, and comes back.
        testWidgets('coming back with the switch on runs the import, and '
            'takes the line down', (tester) async {
          final probe = switchOff();
          final importer = androidImporter(broughtDaysIn);
          await importOn(tester, probe, importer);
          await tester.tap(resultAllow);
          await tester.pumpAndSettle();
          expect(find.text(stillOff), findsOneWidget);

          await leaveAndComeBack(tester);
          expect(importer.calls, 1, reason: 'still off: nothing to do');
          expect(find.text(stillOff), findsOneWidget);

          probe.reachesPastData = true;
          await leaveAndComeBack(tester);

          expect(importer.calls, 2);
          expect(find.text(stillOff), findsNothing);
          expect(find.text(olderHint), findsNothing);
          expect(resultSettings, findsNothing);

          await leaveAndComeBack(tester);
          expect(importer.calls, 2, reason: 'once');
        });

        // An import whose reads are off raises Health Connect's sheet, and
        // nothing is asked from here except by a tap.
        testWidgets('but not when reading has been switched off meanwhile',
            (tester) async {
          final probe = switchOff();
          final importer = androidImporter(broughtDaysIn);
          await importOn(tester, probe, importer);
          await tester.tap(resultAllow);
          await tester.pumpAndSettle();

          probe
            ..reachesPastData = true
            ..read = HealthPermissionStatus.denied;
          await leaveAndComeBack(tester);

          expect(importer.calls, 1);
        });

        // A result belongs to the binding that produced it. Left up
        // across a change of profile, a return to the screen imported the
        // whole history into a profile nobody had tapped Import for.
        testWidgets('choosing the profile again takes the result down, and '
            'coming back then runs nothing', (tester) async {
          final probe = switchOff();
          final importer = androidImporter(broughtDaysIn);
          await importOn(tester, probe, importer);
          await tester.tap(resultAllow);
          await tester.pumpAndSettle();
          expect(find.text(stillOff), findsOneWidget);

          await tester.tap(
            find.byKey(const ValueKey('health-sync-profile-eligible')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('health-sync-confirm-bind')));
          await tester.pumpAndSettle();

          expect(find.byKey(const ValueKey('health-sync-import-summary')),
              findsNothing);
          expect(find.text(stillOff), findsNothing);
          expect(resultAllow, findsNothing);

          probe.reachesPastData = true;
          await leaveAndComeBack(tester);
          expect(importer.calls, 1);
        });

        // The profile tiles stay live while an import runs, and the pass
        // cannot be called back.
        testWidgets('an import still running when the profile is chosen '
            'again does not put its result up afterwards', (tester) async {
          for (final error in <Object?>[null, StateError('storage')]) {
            final importer = androidImporter(broughtDaysIn)
              ..importGate = Completer<void>()
              ..importError = error;
            await pumpAndroid(
              tester,
              binding: await boundBinding(),
              permissionProbe: switchOff(),
              importer: importer,
            );
            await tester.tap(
              find.byKey(const ValueKey('health-sync-import-tile')),
            );
            await tester.pump();

            // No pumpAndSettle while the import runs: its progress bar
            // never settles.
            Future<void> pumpThrough() async {
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 500));
            }

            await tester.tap(
              find.byKey(const ValueKey('health-sync-profile-eligible')),
            );
            await pumpThrough();
            await tester.tap(
              find.byKey(const ValueKey('health-sync-confirm-bind')),
            );
            await pumpThrough();
            importer.importGate!.complete();
            await tester.pumpAndSettle();

            expect(
              find.byKey(const ValueKey('health-sync-import-summary')),
              findsNothing,
              reason: '$error',
            );
            expect(resultAllow, findsNothing);

            // And the screen is ready for an import under the new binding.
            importer
              ..importGate = null
              ..importError = null;
            await importAndReadResult(tester);
            expect(importer.calls, 2);
            expect(resultAllow, findsOneWidget);
            await tester.pumpWidget(const SizedBox.shrink());
          }
        });

        testWidgets('so does stopping the sync', (tester) async {
          final probe = switchOff();
          final importer = androidImporter(broughtDaysIn);
          await importOn(tester, probe, importer);
          await tester.tap(resultAllow);
          await tester.pumpAndSettle();

          await tester.tap(find.byKey(const ValueKey('health-sync-unbind-tile')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('health-sync-confirm-unbind')),
          );
          await tester.pumpAndSettle();

          probe.reachesPastData = true;
          await leaveAndComeBack(tester);
          expect(importer.calls, 1);
          expect(find.text(stillOff), findsNothing);
        });

        testWidgets('coming back to a result that is not waiting on the '
            'switch runs nothing', (tester) async {
          final probe = switchOff();
          final importer = androidImporter(broughtDaysIn);
          await importOn(tester, probe, importer);

          probe.reachesPastData = true;
          await leaveAndComeBack(tester);

          expect(importer.calls, 1);
          expect(resultAllow, findsOneWidget,
              reason: 'the result describes the pass that produced it');
        });

        testWidgets('when it cannot tell whether there is a switch, it '
            'offers the prompt', (tester) async {
          final importer = androidImporter(broughtDaysIn)
            ..pastDataOfferedThrows = true;
          await importOn(tester, switchOff(), importer);

          expect(find.text(olderHint), findsOneWidget);
          expect(resultAllow, findsOneWidget);
        });
      });

      testWidgets('iPhone: an import that brought days in has no such line',
          (tester) async {
        await pumpScreen(
          tester,
          binding: await boundBinding(),
          importer: _FakeImporter(broughtDaysIn),
          permissionProbe: _ScriptedProbe(
            readAccessDisclosed: false,
            write: HealthPermissionStatus.granted,
            read: HealthPermissionStatus.granted,
          ),
          writeEnabled: true,
          storePlatform: HealthImportPlatform.appleHealth,
          viewport: const Size(800, 2400),
        );
        await importAndReadResult(tester);
        // In the result, and announced in the snackbar as well.
        expect(find.text('Imported 2 days.'), findsWidgets);
        expect(find.textContaining('Access past data'), findsNothing);
        expect(resultSettings, findsNothing);
        expect(resultAllow, findsNothing);
      });

      testWidgets('Android: the question is only asked once reading is '
          'allowed', (tester) async {
        final probe = _ScriptedProbe(
          readAccessDisclosed: true,
          write: HealthPermissionStatus.granted,
          read: HealthPermissionStatus.denied,
          reachesPastData: false,
        );
        await pumpAndroid(
          tester,
          binding: await boundBinding(),
          permissionProbe: probe,
          importer: androidImporter(const HealthImportSummary(pagesRead: 1)),
        );

        // Reading is not allowed, so the neutral line stands: it already
        // says access may be the reason.
        expect(await importAndReadResult(tester), neutralHealthConnect);
        expect(probe.pastDataProbes, 0);
      });

      testWidgets('Android: when reading is not known to be allowed, an '
          'empty whole-history import keeps the neutral line', (tester) async {
        for (final probe in [
          _ScriptedProbe(
            readAccessDisclosed: true,
            write: HealthPermissionStatus.granted,
            read: HealthPermissionStatus.denied,
          ),
          _ScriptedProbe(
            readAccessDisclosed: true,
            write: HealthPermissionStatus.granted,
            read: HealthPermissionStatus.notAsked,
          ),
          // Cannot tell: the read-side probe throws.
          _ScriptedProbe(
            readAccessDisclosed: true,
            write: HealthPermissionStatus.granted,
            readThrows: true,
          ),
        ]) {
          await pumpAndroid(
            tester,
            binding: await boundBinding(),
            permissionProbe: probe,
            importer: androidImporter(const HealthImportSummary(pagesRead: 1)),
          );
          expect(await importAndReadResult(tester), neutralHealthConnect);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      });

      testWidgets('Android: reading switched off between the tap and the '
          'answer is read again after the pass', (tester) async {
        final probe = _ScriptedProbe(
          readAccessDisclosed: true,
          write: HealthPermissionStatus.granted,
          read: HealthPermissionStatus.granted,
        );
        await pumpAndroid(
          tester,
          binding: await boundBinding(),
          permissionProbe: probe,
          importer: androidImporter(const HealthImportSummary()),
        );
        // What the screen loaded with is no longer true when the pass ends.
        probe.read = HealthPermissionStatus.denied;

        expect(await importAndReadResult(tester), neutralHealthConnect);
      });

      testWidgets('iPhone: an empty import keeps the neutral line whatever '
          'a read-side probe could answer, and that probe is never asked',
          (tester) async {
        final probe = _ScriptedProbe(
          readAccessDisclosed: false,
          write: HealthPermissionStatus.granted,
          read: HealthPermissionStatus.granted,
        );
        await pumpScreen(
          tester,
          binding: await boundBinding(),
          importer: _FakeImporter(const HealthImportSummary(pagesRead: 1)),
          permissionProbe: probe,
          writeEnabled: true,
          storePlatform: HealthImportPlatform.appleHealth,
          viewport: const Size(800, 2400),
        );

        expect(await importAndReadResult(tester), neutralAppleHealth);
        expect(probe.readProbes, 0);
        // Issue #1549: nor the question about past data, and no button.
        expect(probe.pastDataProbes, 0);
        expect(resultSettings, findsNothing);
      });

      testWidgets('with no permission probe wired, an empty import keeps '
          'the neutral line', (tester) async {
        await pumpScreen(
          tester,
          binding: await boundBinding(),
          importer: androidImporter(const HealthImportSummary(pagesRead: 1)),
          writeEnabled: true,
          storePlatform: HealthImportPlatform.healthConnect,
          viewport: const Size(800, 2400),
        );

        expect(await importAndReadResult(tester), neutralHealthConnect);
      });

      testWidgets('a pass that never read (reading declined) is not '
          'described as nothing new', (tester) async {
        await pumpAndroid(
          tester,
          binding: await boundBinding(),
          permissionProbe: _ScriptedProbe(
            readAccessDisclosed: true,
            write: HealthPermissionStatus.granted,
            read: HealthPermissionStatus.denied,
          ),
          importer: androidImporter(
            const HealthImportSummary(blocked: HealthPlatformPermissionDenied()),
          ),
        );

        expect(await importAndReadResult(tester), neutralHealthConnect);
      });
    });

    testWidgets('Android: a read-side probe that throws leaves the write '
        'answer on the line', (tester) async {
      final probe = _ScriptedProbe(
        readAccessDisclosed: true,
        write: HealthPermissionStatus.denied,
        readThrows: true,
      );
      await pumpAndroid(
        tester,
        binding: await boundBinding(),
        permissionProbe: probe,
      );

      expect(probe.readProbes, 1);
      expect(
        statusLine(tester),
        'Health Connect access: denied — open Settings to change',
      );
    });

    // iPhone. HealthKit does not disclose read access, so there the
    // read-side probe is only the write answer under another name. The
    // screen decides on the platform fact (`readAccessDisclosed`), not on
    // what the two answers happen to be: it never asks the read-side
    // question at all.
    testWidgets('iPhone: the read-side question is never asked, so nothing '
        'it could answer can put "reading only" on the line',
        (tester) async {
      for (final write in HealthPermissionStatus.values) {
        // A probe that would claim reading is on, whatever the writes are —
        // exactly the pair of answers that reads "reading only" on Android.
        final probe = _ScriptedProbe(
          readAccessDisclosed: false,
          write: write,
          read: HealthPermissionStatus.granted,
          grantedTypes: write == HealthPermissionStatus.writingSome
              ? const {'menstrualFlow'}
              : const {},
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpIphone(tester, permissionProbe: probe);

        expect(probe.writeProbes, 1, reason: 'write=$write');
        expect(probe.readProbes, 0, reason: 'write=$write');
        expect(statusLine(tester), isNot(contains('reading only')));
        expect(statusLine(tester), isNot(contains('writing only')));
        expect(
          statusLine(tester),
          switch (write) {
            HealthPermissionStatus.granted => 'Health app access: granted',
            HealthPermissionStatus.writingSome =>
              'Health app access: writing some (Basal body temperature, Cervical mucus, Ovulation test, Spotting, Symptoms off) — open Settings to change',
            HealthPermissionStatus.notAsked =>
              'Health app access: not yet asked',
            HealthPermissionStatus.denied =>
              'Health app access: denied — open Settings to change',
            HealthPermissionStatus.unavailable =>
              'Health app access is not available on this device.',
          },
        );
        expect(
          find.byKey(settingsKey),
          write == HealthPermissionStatus.denied ||
                  write == HealthPermissionStatus.writingSome
              ? findsOneWidget
              : findsNothing,
        );
      }
    });

    testWidgets('iPhone: the real adapter sends Swift the write probe once '
        'per reading and never the read-side one', (tester) async {
      final HealthPermissionProbe ios = createHealthPlatform(
        TargetPlatform.iOS,
        binding: HealthSyncBinding(FakeSettingsStore()),
        minorBindingAllowed: true,
      );
      expect((ios as MethodChannelHealthPlatform).readAccessDisclosed, isFalse);

      for (final (wire, expected) in [
        ('granted', 'Health app access: granted'),
        ('notAsked', 'Health app access: not yet asked'),
        ('denied', 'Health app access: denied — open Settings to change'),
      ]) {
        permissionCalls.clear();
        permissionResult = wire;
        // What a Kotlin half would answer; an iPhone never hears the
        // question, so this must not matter.
        importPermissionResult = 'granted';
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpIphone(tester, permissionProbe: ios);

        expect(statusLine(tester), expected);
        expect(
          permissionCalls.map((call) => call.method),
          // Issue #1590: a denied state also reads which write types were
          // never asked about — the type an app update added — but the
          // read-side question (`importPermissionStatus`) is an Android
          // one and is never sent to Swift.
          wire == 'denied'
              ? ['permissionStatus', 'neverAskedWriteTypes']
              : ['permissionStatus'],
          reason: 'the write probe and, when some writes are off, the '
              'never-asked one — nothing the read side would have to answer',
        );
      }
    });

    testWidgets('Android: the real adapter asks Kotlin both questions',
        (tester) async {
      final HealthPermissionProbe android = createHealthPlatform(
        TargetPlatform.android,
        binding: HealthSyncBinding(FakeSettingsStore()),
        minorBindingAllowed: true,
      );
      expect(
        (android as MethodChannelHealthPlatform).readAccessDisclosed,
        isTrue,
      );

      permissionResult = 'denied';
      importPermissionResult = 'granted';
      await pumpAndroid(
        tester,
        binding: await boundBinding(),
        permissionProbe: android,
      );

      expect(statusLine(tester), readingOnly);
      // Issue #1549: and not the third, about past data. That one is
      // asked when an import finishes, not when the screen opens.
      expect(
        permissionCalls.map((call) => call.method),
        [
          'permissionStatus',
          'importPermissionStatus',
          // Issue #1590: and which write types no sheet has asked about,
          // so a type an app update added is asked for once.
          'neverAskedWriteTypes',
        ],
      );
    });

    testWidgets(
        'Android: writingSome shows off types and settings link (issue #1555)',
        (tester) async {
      final probe = _ScriptedProbe(
        readAccessDisclosed: true,
        write: HealthPermissionStatus.writingSome,
        read: HealthPermissionStatus.granted,
        grantedTypes: const {
          'menstrualFlow',
          'basalBodyTemperature',
          'cervicalMucus',
          'ovulationTest',
          'symptoms',
        },
      );
      await pumpAndroid(
        tester,
        binding: await boundBinding(),
        permissionProbe: probe,
      );

      expect(
        statusLine(tester),
        'Health Connect access: writing some (Spotting off) — open Settings to change',
      );
      expect(find.byKey(settingsKey), findsOneWidget);
    });
  });

  // Issue #1590: the write pass asks for authorization once, while no
  // forward-only floor is stamped, so a write type an app update adds is
  // never asked for on a phone that already gave access — and never
  // written there. The sync screen tells "never asked" from "declined" per
  // type and asks for the never-asked ones once, at a moment of its own
  // rather than in the pass's day-logging upkeep.
  group('Issue #1590 a write type no sheet has asked about', () {
    const statusKey = ValueKey('health-sync-permission-status');

    Future<HealthSyncBinding> boundBinding() async {
      final binding = HealthSyncBinding(FakeSettingsStore());
      await binding.bind(
        profile: profiles.firstWhere((p) => p.id == 'eligible'),
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: false,
      );
      return binding;
    }

    Future<void> pumpAndroid(
      WidgetTester tester, {
      required HealthSyncBinding binding,
      required HealthPermissionProbe permissionProbe,
      bool writeEnabled = true,
    }) =>
        pumpScreen(
          tester,
          binding: binding,
          permissionProbe: permissionProbe,
          writeEnabled: writeEnabled,
          storePlatform: HealthImportPlatform.healthConnect,
          viewport: const Size(800, 2400),
        );

    String statusLine(WidgetTester tester) => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(statusKey),
            matching: find.byType(Text),
          ),
        )
        .data!;

    testWidgets('asks once, for exactly the never-asked types, with the '
        'bound profile\'s guard facts', (tester) async {
      final probe = _ScriptedProbe(
        readAccessDisclosed: true,
        write: HealthPermissionStatus.writingSome,
        read: HealthPermissionStatus.granted,
        grantedTypes: const {'menstrualFlow'},
        neverAskedTypes: const {'spotting'},
      );
      // What the person choosing "allow" leaves behind: the type is no
      // longer one no sheet has asked about.
      probe.onWriteTypeRequest = () {
        probe.neverAskedTypes = const {};
        probe.grantedTypes = const {'menstrualFlow', 'spotting'};
      };
      await pumpAndroid(
        tester,
        binding: await boundBinding(),
        permissionProbe: probe,
      );

      // Exactly one ask, carrying only the type no sheet has offered —
      // Health Connect drops a whole request that carries a permission
      // already declined twice.
      expect(probe.writeTypeRequests, 1);
      final call = probe.writeTypeRequestCalls.single;
      expect(call.types, {'spotting'});
      // The same guard facts the bind flow evaluates.
      expect(call.facts.profile.id, 'eligible');
      expect(call.facts.signedInUserId, 'u1');
      expect(call.facts.ownerUserId, 'u1');
      // The per-type answers are read again after the sheet, so the status
      // line and the off-types list are what the person just answered.
      expect(probe.neverAskedProbes, 2);
    });

    testWidgets('does not ask in the state the write pass\'s own first '
        'request owns', (tester) async {
      // On a fresh install every type is "never asked"; the pass asks on
      // its first pass, a moment after a profile is bound. The screen must
      // not race it with a sheet of its own.
      final probe = _ScriptedProbe(
        readAccessDisclosed: false,
        write: HealthPermissionStatus.notAsked,
        neverAskedTypes: const {'menstrualFlow', 'spotting'},
      );
      await pumpScreen(
        tester,
        binding: HealthSyncBinding(FakeSettingsStore()),
        permissionProbe: probe,
        storePlatform: HealthImportPlatform.appleHealth,
      );

      expect(probe.writeTypeRequests, 0);
      expect(probe.neverAskedProbes, 0);
    });

    testWidgets('asks on a denied state too: the denied types are not the '
        'never-asked one', (tester) async {
      final probe = _ScriptedProbe(
        readAccessDisclosed: true,
        write: HealthPermissionStatus.denied,
        read: HealthPermissionStatus.granted,
        neverAskedTypes: const {'spotting'},
      );
      await pumpAndroid(
        tester,
        binding: await boundBinding(),
        permissionProbe: probe,
      );

      expect(probe.writeTypeRequests, 1);
      expect(probe.writeTypeRequestCalls.single.types, {'spotting'});
    });

    testWidgets('a probe that cannot answer leaves the status line on the '
        'screen and asks nothing', (tester) async {
      final probe = _ScriptedProbe(
        readAccessDisclosed: true,
        write: HealthPermissionStatus.denied,
        read: HealthPermissionStatus.granted,
        neverAskedThrows: true,
      );
      await pumpAndroid(
        tester,
        binding: await boundBinding(),
        permissionProbe: probe,
      );

      expect(probe.writeTypeRequests, 0);
      expect(statusLine(tester), isNot(contains('not available')));
    });

    testWidgets('asks nothing while no profile is bound', (tester) async {
      final probe = _ScriptedProbe(
        readAccessDisclosed: true,
        write: HealthPermissionStatus.denied,
        read: HealthPermissionStatus.granted,
        neverAskedTypes: const {'spotting'},
      );
      await pumpAndroid(
        tester,
        binding: HealthSyncBinding(FakeSettingsStore()),
        permissionProbe: probe,
      );

      expect(probe.writeTypeRequests, 0);
    });

    testWidgets('asks nothing on a build where the write direction is not '
        'wired', (tester) async {
      final probe = _ScriptedProbe(
        readAccessDisclosed: true,
        write: HealthPermissionStatus.denied,
        read: HealthPermissionStatus.granted,
        neverAskedTypes: const {'spotting'},
      );
      await pumpAndroid(
        tester,
        binding: await boundBinding(),
        permissionProbe: probe,
        writeEnabled: false,
      );

      expect(probe.writeTypeRequests, 0);
    });

    testWidgets('a request that throws is best effort: one ask, not a '
        'crash', (tester) async {
      final probe = _ScriptedProbe(
        readAccessDisclosed: true,
        write: HealthPermissionStatus.writingSome,
        read: HealthPermissionStatus.granted,
        grantedTypes: const {'menstrualFlow'},
        neverAskedTypes: const {'spotting'},
        writeTypeRequestThrows: true,
      );
      await pumpAndroid(
        tester,
        binding: await boundBinding(),
        permissionProbe: probe,
      );

      expect(probe.writeTypeRequests, 1);
    });
  });

  // Issue #1521. Every explanation stood above the profile rows, so the
  // only things a person can do on the screen (choose a profile, import,
  // stop) sat under six or more paragraphs, below the fold on Android. The
  // reference detail is below them now. Two paragraphs stay first: the
  // intro, and the one that says what is sent and when and that the import
  // goes on in the background. The screen is a disclosure surface, so the
  // other half of the change is what did not change: every sentence is
  // still on it, unedited.
  group('Issue #1521 what a person can do comes before the reference detail',
      () {
    // Whether it all fits one screenful is a question about real text
    // metrics, and this harness draws with the test font (every glyph a
    // full em wide), so a pixel budget here would measure the font. What
    // is pinned instead is what stands above the controls and what does
    // not; the fit itself was checked on renders with the app's own font
    // and on a device (see the pull request).
    final l10n = AppLocalizationsEn();

    Future<HealthSyncBinding> boundBinding() async {
      final binding = HealthSyncBinding(FakeSettingsStore());
      await binding.bind(
        profile: profiles.firstWhere((p) => p.id == 'eligible'),
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: false,
      );
      return binding;
    }

    Rect rectOf(WidgetTester tester, String key) =>
        tester.getRect(find.byKey(ValueKey(key)));

    /// The texts of the list that start above [key]'s top edge.
    List<String> textsAbove(WidgetTester tester, String key) {
      final limit = rectOf(tester, key).top;
      final texts = find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Text),
      );
      return [
        for (final element in texts.evaluate())
          if (tester.getRect(find.byWidget(element.widget)).top < limit)
            (element.widget as Text).data!,
      ];
    }

    /// The paragraphs of the "Writing" group, by key, in the order shown.
    List<String> writingKeys(HealthImportPlatform platform) => [
          // Issue #1526: both stores list what is written.
          'health-sync-written-types-copy',
          if (platform == HealthImportPlatform.healthConnect)
            'health-sync-period-record-copy',
          'health-sync-flow-collapse-copy',
          if (platform == HealthImportPlatform.healthConnect)
            'health-sync-symptoms-android-limitation'
          else
            'health-sync-symptoms-copy',
        ];

    /// Every reference paragraph below the controls, in the order shown.
    List<String> detailKeys(HealthImportPlatform platform) => [
          ...writingKeys(platform),
          'health-sync-full-history-copy',
          'health-sync-revocation-copy',
        ];

    /// Every sentence the write screen shows: those from before the reorder,
    /// and the iPhone's list of what is written (Issue #1526).
    List<String> disclosures(HealthImportPlatform platform) =>
        platform == HealthImportPlatform.healthConnect
            ? [
                l10n.healthSyncWriteIntroHealthConnect,
                l10n.healthSyncWriteForwardOnlyHealthConnect,
                l10n.healthSyncWrittenTypesHealthConnect,
                l10n.healthSyncPeriodRecordNoteHealthConnect,
                l10n.healthSyncFlowCollapseNoteHealthConnect,
                l10n.settingsHealthSyncSymptomsAndroidLimitation,
                l10n.healthSyncRevocationNoteHealthConnect,
                l10n.healthSyncFullHistoryNote,
              ]
            : [
                l10n.healthSyncWriteIntro,
                l10n.healthSyncWriteForwardOnly,
                l10n.healthSyncWrittenTypes,
                l10n.healthSyncFlowCollapseNote,
                l10n.healthSyncWriteSymptoms,
                l10n.healthSyncRevocationNote,
                l10n.healthSyncFullHistoryNote,
              ];

    for (final platform in HealthImportPlatform.values) {
      final name = platform == HealthImportPlatform.healthConnect
          ? 'Android'
          : 'iPhone';

      testWidgets('$name: two paragraphs stand above the choice, and no '
          'more: the intro, and what is sent and when', (tester) async {
        await pumpScreen(
          tester,
          binding: HealthSyncBinding(FakeSettingsStore()),
          permissionProbe: buildPermissionProbe(),
          storePlatform: platform,
          viewport: const Size(800, 3200),
        );

        final sentences = disclosures(platform);
        expect(
          textsAbove(tester, 'health-sync-profile-eligible'),
          [sentences[0], sentences[1]],
        );
      });

      testWidgets('$name: nothing but the controls stands between the '
          'choice and the reference detail', (tester) async {
        await pumpScreen(
          tester,
          binding: await boundBinding(),
          importer: _FakeImporter(const HealthImportSummary(), platform: platform),
          permissionProbe: buildPermissionProbe(),
          storePlatform: platform,
          viewport: const Size(800, 3200),
        );

        // Every reference paragraph, and every heading over one, starts
        // below Stop syncing, the last control.
        final lastControl = rectOf(tester, 'health-sync-unbind-tile').bottom;
        for (final key in detailKeys(platform)) {
          expect(rectOf(tester, key).top, greaterThan(lastControl), reason: key);
        }
        for (final heading in ['Writing', 'Importing', 'Turning sync off']) {
          expect(
            tester.getRect(find.text(heading)).top,
            greaterThan(lastControl),
            reason: heading,
          );
        }
      });

      testWidgets('$name: the order is the intro, how it works, the choice, '
          'the access line, Import and its result, Stop syncing, and only '
          'then the reference detail', (tester) async {
        await pumpScreen(
          tester,
          binding: await boundBinding(),
          importer: _FakeImporter(
            const HealthImportSummary(samplesRead: 1, daysWritten: 1),
            platform: platform,
          ),
          permissionProbe: buildPermissionProbe(),
          storePlatform: platform,
          viewport: const Size(800, 3200),
        );
        await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
        await tester.pumpAndSettle();

        final tops = <double>[
          tester.getRect(find.text(disclosures(platform).first)).top,
          for (final key in [
            // What is sent and when, and that the import goes on in the
            // background: still read before anything can be chosen.
            'health-sync-forward-only-copy',
            'health-sync-profile-eligible',
            'health-sync-profile-minor',
            'health-sync-profile-other',
            'health-sync-permission-status',
            'health-sync-import-tile',
            'health-sync-import-summary',
            'health-sync-unbind-tile',
            ...detailKeys(platform),
          ])
            rectOf(tester, key).top,
        ];
        for (var i = 1; i < tops.length; i++) {
          expect(tops[i], greaterThan(tops[i - 1]), reason: 'item $i');
        }

        // Retire the completion SnackBar so no timer outlives the test.
        ScaffoldMessenger.of(tester.element(find.byType(Scaffold)))
            .removeCurrentSnackBar();
        await tester.pumpAndSettle();
      });

      testWidgets('$name: an import result already on screen does not move '
          'the page', (tester) async {
        // Tall enough that the controls and the result are all in view,
        // short enough that the list can scroll (the detail runs past it).
        const viewport = Size(800, 1000);
        await pumpScreen(
          tester,
          binding: await boundBinding(),
          importer: _FakeImporter(const HealthImportSummary(), platform: platform),
          permissionProbe: buildPermissionProbe(),
          storePlatform: platform,
          viewport: viewport,
        );
        final before = rectOf(tester, 'health-sync-import-tile').top;

        await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
        await tester.pumpAndSettle();

        final result = rectOf(tester, 'health-sync-import-summary');
        expect(result.top, greaterThanOrEqualTo(0));
        expect(result.bottom, lessThanOrEqualTo(viewport.height));
        expect(rectOf(tester, 'health-sync-import-tile').top, before);
        // The list really could have scrolled: it holds more than a screen.
        final position = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        expect(position.maxScrollExtent, greaterThan(0));
        expect(position.pixels, 0);
      });

      testWidgets('$name: every sentence the screen showed is still on it, '
          'unedited', (tester) async {
        await pumpScreen(
          tester,
          binding: await boundBinding(),
          importer: _FakeImporter(const HealthImportSummary(), platform: platform),
          permissionProbe: buildPermissionProbe(),
          storePlatform: platform,
          viewport: const Size(800, 3200),
        );

        for (final sentence in disclosures(platform)) {
          expect(find.text(sentence), findsOneWidget, reason: sentence);
        }
      });

      testWidgets('$name: each group of explanations has a heading, read '
          'out as one', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpScreen(
          tester,
          binding: HealthSyncBinding(FakeSettingsStore()),
          storePlatform: platform,
          viewport: const Size(800, 3200),
        );

        // Heading, then every paragraph that belongs under it.
        final groups = <String, List<String>>{
          'Writing': writingKeys(platform),
          'Importing': ['health-sync-full-history-copy'],
          'Turning sync off': ['health-sync-revocation-copy'],
        };
        final headings = groups.keys.toList();
        final tops = <double>[];
        for (final heading in headings) {
          expect(find.text(heading), findsOneWidget);
          expect(
            tester.getSemantics(find.text(heading)),
            matchesSemantics(label: heading, isHeader: true),
          );
          tops.add(tester.getRect(find.text(heading)).top);
        }
        for (var i = 0; i < headings.length; i++) {
          for (final key in groups[headings[i]]!) {
            final paragraph = rectOf(tester, key).top;
            expect(paragraph, greaterThan(tops[i]), reason: key);
            if (i + 1 < headings.length) {
              expect(paragraph, lessThan(tops[i + 1]), reason: key);
            }
          }
        }
        // The paragraph above the choice has no heading of its own: it is
        // the second thing on the screen.
        expect(
          rectOf(tester, 'health-sync-forward-only-copy').top,
          lessThan(tops.first),
        );
        handle.dispose();
      });
    }

    testWidgets('an import-only screen: its paragraph stays above the '
        'choice, and only the heading that applies is shown', (tester) async {
      await pumpScreen(
        tester,
        binding: HealthSyncBinding(FakeSettingsStore()),
        writeEnabled: false,
        storePlatform: HealthImportPlatform.healthConnect,
        viewport: const Size(800, 3200),
      );

      expect(find.text('Importing'), findsOneWidget);
      expect(find.text('Writing'), findsNothing);
      expect(find.text('Turning sync off'), findsNothing);
      expect(find.text(l10n.healthSyncImportIntro), findsOneWidget);
      expect(find.text(l10n.healthSyncImportOnly), findsOneWidget);
      expect(find.text(l10n.healthSyncFullHistoryNote), findsOneWidget);

      final tops = [
        tester.getRect(find.text(l10n.healthSyncImportIntro)).top,
        rectOf(tester, 'health-sync-import-only-copy').top,
        rectOf(tester, 'health-sync-profile-eligible').top,
        rectOf(tester, 'health-sync-profile-other').top,
        tester.getRect(find.text('Importing')).top,
        rectOf(tester, 'health-sync-full-history-copy').top,
      ];
      for (var i = 1; i < tops.length; i++) {
        expect(tops[i], greaterThan(tops[i - 1]), reason: 'item $i');
      }
    });

    testWidgets('each profile row carries a radio mark, filled for the '
        'profile that is bound', (tester) async {
      await pumpScreen(tester, binding: await boundBinding());

      ListTile tile(String id) => tester.widget<ListTile>(
            find.byKey(ValueKey('health-sync-profile-$id')),
          );
      Finder markIn(String id, IconData icon) => find.descendant(
            of: find.byKey(ValueKey('health-sync-profile-$id')),
            matching: find.byIcon(icon),
          );

      expect(markIn('eligible', Icons.radio_button_checked), findsOneWidget);
      expect(tile('eligible').selected, isTrue);
      for (final id in ['minor', 'other']) {
        expect(markIn(id, Icons.radio_button_unchecked), findsOneWidget);
        expect(markIn(id, Icons.radio_button_checked), findsNothing);
        expect(tile(id).selected, isFalse);
      }
      // A profile that cannot be chosen is still listed, greyed, with why.
      expect(tile('other').enabled, isFalse);
      expect(tile('other').subtitle, isNotNull);
    });

    testWidgets('with nothing bound no row is marked as chosen',
        (tester) async {
      await pumpScreen(tester, binding: HealthSyncBinding(FakeSettingsStore()));

      expect(find.byIcon(Icons.radio_button_checked), findsNothing);
      expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(3));
    });
  });
}
