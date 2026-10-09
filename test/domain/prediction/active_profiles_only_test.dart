/// Issue #1727: `activeProfilesOnly` is the filter every prediction-driven
/// background consumer takes its input through — `ProfilesRepository
/// .watch()` includes archived profiles for display consumers, but an
/// archive must read as an *absence* to the coordinator and the two
/// publishers (the publishers retract their server-side snapshot on a
/// removal; the coordinator drops the profile's subscriptions).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';

Profile _profile(String id, {DateTime? archivedAt}) => Profile(
      id: id,
      displayName: 'Profile $id',
      isMinor: false,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      archivedAt: archivedAt,
    );

void main() {
  test('drops archived profiles and keeps live ones, order intact', () async {
    final live1 = _profile('live-1');
    final archived = _profile('archived', archivedAt: DateTime.utc(2026, 9, 1));
    final live2 = _profile('live-2');

    final filtered = await activeProfilesOnly(
      Stream.value([live1, archived, live2]),
    ).first;

    expect(filtered, [live1, live2]);
  });

  test('an all-archived list becomes an empty list (the removal every '
      'consumer sees)', () async {
    final filtered = await activeProfilesOnly(
      Stream.value([_profile('archived', archivedAt: DateTime.utc(2026))]),
    ).first;

    expect(filtered, isEmpty);
  });
}
