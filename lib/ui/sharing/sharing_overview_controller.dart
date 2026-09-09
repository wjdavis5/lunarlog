/// Live per-profile sharing state for discoverability surfaces (Issue #126).
///
/// Watches the local guardian rows of every observed profile and exposes a
/// [SharingProfileInfo] per id, plus a badge epoch that outside screens
/// bump when returning from Manage Guardians so a cancelled invitation's
/// badge is refetched (pending invitations are never stored locally, so
/// the badge cannot observe them any other way).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lunarlog/data/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/sharing/sharing_overview.dart';

class SharingOverviewController extends ChangeNotifier {
  SharingOverviewController({
    required this.storage,
    required this.currentUserId,
  });

  final LunarLogStorage storage;

  /// The signed-in operator's id, or null when signed out or unknown.
  final String? currentUserId;

  final Map<String, SharingProfileInfo> _infos = {};
  final Map<String, StreamSubscription<List<ProfileGuardian>>> _subs = {};

  int _badgeEpoch = 0;

  /// Bumped by screens returning from Manage Guardians; badge widgets key
  /// their refetch off it.
  int get badgeEpoch => _badgeEpoch;

  /// Unknown until the profile's rows arrive — which [SharingProfileInfo]
  /// reads as owned, never shared.
  SharingProfileInfo infoFor(String profileId) =>
      _infos[profileId] ?? const SharingProfileInfo.unknown();

  /// Subscribes to every id in [profileIds], dropping ids no longer
  /// listed. Idempotent: calling it on every build is cheap.
  void observeProfiles(Iterable<String> profileIds) {
    final wanted = profileIds.toSet();
    for (final id in _subs.keys.toList()) {
      if (!wanted.contains(id)) {
        unawaited(_subs.remove(id)?.cancel());
        _infos.remove(id);
      }
    }
    final repository = ProfileGuardiansRepository(storage);
    for (final id in wanted) {
      if (_subs.containsKey(id)) continue;
      _infos[id] = const SharingProfileInfo.unknown();
      _subs[id] = repository.watchForProfile(id).listen(
        (rows) {
          _infos[id] = SharingProfileInfo.fromGuardians(rows, currentUserId);
          notifyListeners();
        },
        onError: (_) {},
      );
    }
  }

  /// Refetch outside badges (e.g. after a cancel inside Manage Guardians).
  void refreshBadges() {
    _badgeEpoch++;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final sub in _subs.values) {
      unawaited(sub.cancel());
    }
    _subs.clear();
    super.dispose();
  }
}
