/// Profile UI state (KTD4: provider + ChangeNotifier over drift streams).
///
/// Owns nothing persistently itself: the profile list comes from
/// [ProfilesRepository.watch] and the active-profile pointer from
/// [SettingsKeys.lastActiveProfile]; derived getters decide what the home
/// gate renders. No drift types cross into `lib/ui` (R14/R16).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/models/profile_relationship.dart';
import 'package:lunarlog/domain/prediction/prediction.dart' show CycleFacts;
import 'package:lunarlog/domain/repositories/profile_modes_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';

class ProfileController extends ChangeNotifier {
  ProfileController({
    required ProfilesRepository profilesRepository,
    required SettingsStore settingsStore,
    ProfileModesRepository? profileModesRepository,
  })  : _profiles = profilesRepository,
        _settings = settingsStore,
        _profileModes = profileModesRepository;

  final ProfilesRepository _profiles;
  final SettingsStore _settings;

  /// Issue #218's persistence seam for the birth-control-method and
  /// goal/mode answers: #216's onboarding form (and the profile-settings
  /// editor) hand those answers to [createProfile]/[renameProfile], which
  /// write them through here into #188's `profile_modes` row so #233
  /// (PI-10)/#260 can consume them later without a second onboarding
  /// pass. Optional so existing tests/unconfigured trees keep compiling.
  final ProfileModesRepository? _profileModes;

  List<Profile> _live = const [];
  String? _storedActiveId;
  bool _loaded = false;
  bool _noticeShown = false;
  bool _pickerRequested = false;
  bool _disposed = false;
  StreamSubscription<List<Profile>>? _liveSub;
  StreamSubscription<String?>? _activeSub;

  bool get loaded => _loaded;

  /// Live (non-tombstoned), non-archived profiles in repository order
  /// (sort_order then id).
  List<Profile> get activeProfiles =>
      [for (final profile in _live) if (profile.archivedAt == null) profile];

  List<Profile> get archivedProfiles =>
      [for (final profile in _live) if (profile.archivedAt != null) profile];

  /// Zero live rows at all (archived included): first-run territory.
  bool get needsFirstRun => _loaded && _live.isEmpty;

  bool get firstRunNoticeShown => _noticeShown;

  /// The stored id resolved against the live list; archived or unknown ids
  /// resolve to null (picker), never a stale screen.
  Profile? get activeProfile {
    final id = _storedActiveId;
    if (id == null) return null;
    for (final profile in _live) {
      if (profile.id == id && profile.archivedAt == null) return profile;
    }
    return null;
  }

  bool get pickerVisible => _pickerRequested || activeProfile == null;

  /// Issue #206 (C-17): this future is fire-and-forget from the provider
  /// `create:` in `lib/app.dart`, and a device reset (`resetDevice`,
  /// `lib/app_lifecycle.dart`) deliberately unmounts the whole app subtree
  /// — disposing this controller — while an in-flight `load()` is still
  /// parked on one of the three storage reads below. Check `_disposed`
  /// after every `await` and bail before touching [notifyListeners] or the
  /// watch subscriptions; a subscription created anyway (disposal landing
  /// between the last await and the listens is impossible in single-threaded
  /// Dart, but a listener that disposes the controller during the final
  /// [notifyListeners] is not) is cancelled instead of stored where
  /// `dispose()` would never see it.
  Future<void> load() async {
    if (_disposed) return;
    _noticeShown =
        await _settings.get(SettingsKeys.firstRunNoticeShown) == 'true';
    if (_disposed) return;
    _live = await _profiles.list();
    if (_disposed) return;
    _storedActiveId = await _settings.get(SettingsKeys.lastActiveProfile);
    if (_disposed) return;
    _loaded = true;
    notifyListeners();
    final liveSub = _profiles.watch().listen((rows) {
      _live = rows;
      notifyListeners();
    });
    final activeSub =
        _settings.watch(SettingsKeys.lastActiveProfile).listen((value) {
      _storedActiveId = (value == null || value.isEmpty) ? null : value;
      notifyListeners();
    });
    if (_disposed) {
      unawaited(liveSub.cancel());
      unawaited(activeSub.cancel());
      return;
    }
    _liveSub = liveSub;
    _activeSub = activeSub;
  }

  Future<void> markFirstRunNoticeShown() {
    _noticeShown = true;
    notifyListeners();
    return _settings.set(SettingsKeys.firstRunNoticeShown, 'true');
  }

  /// Issue #218's one-call onboarding seam (#216's form calls this after
  /// its cycle-questions step): [facts] are the three skippable cycle
  /// answers stored on the profile (feeding the provisional prediction
  /// seed), and [lifecycleMode]/[birthControlMethod] are the goal/mode and
  /// birth-control answers persisted into the `profile_modes` row —
  /// captured and never thrown away, even though their downstream
  /// consumers (#233 (PI-10)/#260) are separate issues. A null mode keeps
  /// the lazy default (`tracking`); a null method stays unset.
  Future<Profile> createProfile({
    required String displayName,
    required bool isMinor,
    ProfileMode mode = ProfileMode.standard,
    int? birthYear,
    ProfileRelationship? relationship,
    CycleFacts? facts,
    LifecycleMode? lifecycleMode,
    String? birthControlMethod,
  }) async {
    final profile = await _profiles.create(
      displayName: _validated(displayName),
      isMinor: isMinor,
      mode: mode,
      birthYear: birthYear,
      relationship: relationship,
      lastPeriodStart: facts?.lastPeriodStart,
      typicalCycleLengthDays: facts?.typicalCycleLengthDays,
      typicalPeriodLengthDays: facts?.typicalPeriodLengthDays,
    );
    await _saveModeAnswer(
      profileId: profile.id,
      lifecycleMode: lifecycleMode,
      birthControlMethod: birthControlMethod,
    );
    return profile;
  }

  /// The profile-settings edit seam for the same answers (Issue #218:
  /// "editable later from profile settings, not just at onboarding").
  /// [facts] rides the ordinary profile update; a null [facts] keeps the
  /// profile's current answers (pass [CycleFacts.empty] to clear them) —
  /// unlike [birthYear]/[relationship], whose callers have always passed
  /// the current value explicitly. [lifecycleMode]/[birthControlMethod],
  /// when non-null, rewrite the mode row.
  Future<void> renameProfile(
    Profile profile, {
    required String displayName,
    required bool isMinor,
    ProfileMode? mode,
    int? birthYear,
    ProfileRelationship? relationship,
    CycleFacts? facts,
    LifecycleMode? lifecycleMode,
    String? birthControlMethod,
  }) async {
    final effectiveFacts = facts ??
        CycleFacts(
          lastPeriodStart: profile.lastPeriodStart,
          typicalCycleLengthDays: profile.typicalCycleLengthDays,
          typicalPeriodLengthDays: profile.typicalPeriodLengthDays,
        );
    await _profiles.update(profile.copyWith(
      displayName: _validated(displayName),
      isMinor: isMinor,
      mode: mode ?? profile.mode,
      birthYear: birthYear,
      relationship: relationship,
      lastPeriodStart: effectiveFacts.lastPeriodStart,
      typicalCycleLengthDays: effectiveFacts.typicalCycleLengthDays,
      typicalPeriodLengthDays: effectiveFacts.typicalPeriodLengthDays,
    ));
    await _saveModeAnswer(
      profileId: profile.id,
      lifecycleMode: lifecycleMode,
      birthControlMethod: birthControlMethod,
    );
  }

  /// Writes the mode/birth-control half of an onboarding or settings edit
  /// (issue #218): only when both a repository is wired and at least one
  /// answer is non-null — a row written with every field null would be a
  /// no-op that still marks data dirty for sync.
  Future<void> _saveModeAnswer({
    required String profileId,
    LifecycleMode? lifecycleMode,
    String? birthControlMethod,
  }) async {
    final modes = _profileModes;
    if (modes == null || (lifecycleMode == null && birthControlMethod == null)) {
      return;
    }
    await modes.save(
      profileId: profileId,
      mode: lifecycleMode ?? LifecycleMode.tracking,
      birthControlMethod: birthControlMethod,
    );
  }

  Future<void> selectProfile(String id) async {
    _pickerRequested = false;
    notifyListeners();
    await _settings.set(SettingsKeys.lastActiveProfile, id);
  }

  /// Returns to the picker for this session only; the stored pointer is kept
  /// so a relaunch reopens the profile.
  void openPicker() {
    _pickerRequested = true;
    notifyListeners();
  }

  Future<void> archiveProfile(String id) => _profiles.setArchived(id, true);

  Future<void> unarchiveProfile(String id) => _profiles.setArchived(id, false);

  String _validated(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'displayName', 'name cannot be empty');
    }
    return trimmed;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_liveSub?.cancel());
    unawaited(_activeSub?.cancel());
    super.dispose();
  }
}
