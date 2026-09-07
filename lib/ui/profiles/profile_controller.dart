/// Profile UI state (KTD4: provider + ChangeNotifier over drift streams).
///
/// Owns nothing persistently itself: the profile list comes from
/// [ProfilesRepository.watch] and the active-profile pointer from
/// [SettingsKeys.lastActiveProfile]; derived getters decide what the home
/// gate renders. No drift types cross into `lib/ui` (R14/R16).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_relationship.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';

class ProfileController extends ChangeNotifier {
  ProfileController({
    required ProfilesRepository profilesRepository,
    required SettingsStore settingsStore,
  })  : _profiles = profilesRepository,
        _settings = settingsStore;

  final ProfilesRepository _profiles;
  final SettingsStore _settings;

  List<Profile> _live = const [];
  String? _storedActiveId;
  bool _loaded = false;
  bool _noticeShown = false;
  bool _pickerRequested = false;
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

  Future<void> load() async {
    _noticeShown =
        await _settings.get(SettingsKeys.firstRunNoticeShown) == 'true';
    _live = await _profiles.list();
    _storedActiveId = await _settings.get(SettingsKeys.lastActiveProfile);
    _loaded = true;
    notifyListeners();
    _liveSub = _profiles.watch().listen((rows) {
      _live = rows;
      notifyListeners();
    });
    _activeSub = _settings.watch(SettingsKeys.lastActiveProfile).listen((value) {
      _storedActiveId = (value == null || value.isEmpty) ? null : value;
      notifyListeners();
    });
  }

  Future<void> markFirstRunNoticeShown() {
    _noticeShown = true;
    notifyListeners();
    return _settings.set(SettingsKeys.firstRunNoticeShown, 'true');
  }

  Future<Profile> createProfile({
    required String displayName,
    required bool isMinor,
    int? birthYear,
    ProfileRelationship? relationship,
  }) =>
      _profiles.create(
        displayName: _validated(displayName),
        isMinor: isMinor,
        birthYear: birthYear,
        relationship: relationship,
      );

  Future<void> renameProfile(
    Profile profile, {
    required String displayName,
    required bool isMinor,
    int? birthYear,
    ProfileRelationship? relationship,
  }) =>
      _profiles.update(profile.copyWith(
        displayName: _validated(displayName),
        isMinor: isMinor,
        birthYear: birthYear,
        relationship: relationship,
      ));

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
    unawaited(_liveSub?.cancel());
    unawaited(_activeSub?.cancel());
    super.dispose();
  }
}
