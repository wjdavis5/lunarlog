/// Unit tests for the reminder payload codec (Issue #136): the JSON
/// payload a scheduled reminder carries, the legacy plain-profileId
/// payload, and the defensive decode of an action id.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/notifications/reminder_payload.dart';
import 'package:lunarlog/domain/notifications/reminder_config.dart'
    show ReminderKind;

void main() {
  test('encode then decode round-trips profile and kind', () {
    for (final kind in ReminderKind.values) {
      final payload =
          encodeReminderPayload(profileId: 'p1', kind: kind);
      final launch = decodeReminderLaunch(payload);
      expect(launch, isNotNull);
      expect(launch!.profileId, 'p1');
      expect(launch.kind, kind);
      expect(launch.isAction, isFalse);
    }
  });

  test('an action id decodes only for the known actions', () {
    final payload =
        encodeReminderPayload(profileId: 'p1', kind: ReminderKind.late);
    expect(
      decodeReminderLaunch(payload, actionId: kReminderActionStarted)!
          .actionId,
      kReminderActionStarted,
    );
    expect(
      decodeReminderLaunch(payload, actionId: kReminderActionSpotting)!
          .actionId,
      kReminderActionSpotting,
    );
    expect(
      decodeReminderLaunch(payload, actionId: kReminderActionNotYet)!.actionId,
      kReminderActionNotYet,
    );
    expect(
      decodeReminderLaunch(payload, actionId: 'not-a-real-action')!.actionId,
      isNull,
      reason: 'an unknown action degrades to a plain tap, never a write',
    );
  });

  test('a legacy plain-profileId payload decodes with no kind and no '
      'action (pre-#136 reminders keep working after an update)', () {
    final launch = decodeReminderLaunch('p9');
    expect(launch, isNotNull);
    expect(launch!.profileId, 'p9');
    expect(launch.kind, isNull);
    expect(launch.actionId, isNull);
    expect(launch.isAction, isFalse);
  });

  test('unusable payloads decode to null, never guess', () {
    expect(decodeReminderLaunch(null), isNull);
    expect(decodeReminderLaunch(''), isNull);
    expect(decodeReminderLaunch('{"v":1'), isNull,
        reason: 'starts like JSON but does not parse');
    expect(decodeReminderLaunch('{"v":1}'), isNull,
        reason: 'no profile id');
    expect(decodeReminderLaunch('{"v":1,"p":""}'), isNull,
        reason: 'an empty profile id acts on nothing');
    expect(decodeReminderLaunch('{"v":1,"p":123}'), isNull,
        reason: 'a non-string profile id acts on nothing');
    expect(decodeReminderLaunch('{"v":1,"p":null}'), isNull);
  });

  test('a non-JSON string is a legacy plain payload (a profile id)', () {
    // A pre-#136 payload is exactly the profile id, so anything that does
    // not look like JSON is one — an id that matches no profile simply
    // falls through the home gate.
    expect(decodeReminderLaunch('not json {')!.profileId, 'not json {');
  });

  test('an unrecognised kind degrades to a kindless launch of the right '
      'profile', () {
    final launch = decodeReminderLaunch('{"v":1,"p":"p1","k":"mystery"}');
    expect(launch, isNotNull);
    expect(launch!.profileId, 'p1');
    expect(launch.kind, isNull);
  });

  test('the payload carries no free text that could reach a lock screen '
      '(KTD7)', () {
    final payload =
        encodeReminderPayload(profileId: 'p1', kind: ReminderKind.upcoming);
    expect(payload.contains(' Started'), isFalse);
    // The only rendered strings stay the generic constants.
    expect(kReminderActionIds, hasLength(3));
  });

  test('ReminderLaunch equality is field-wise', () {
    const a = ReminderLaunch(
        profileId: 'p1', kind: ReminderKind.late, actionId: 'started');
    expect(a, a);
    expect(a, const ReminderLaunch(
        profileId: 'p1', kind: ReminderKind.late, actionId: 'started'));
    expect(
      a,
      isNot(const ReminderLaunch(
          profileId: 'p2', kind: ReminderKind.late, actionId: 'started')),
    );
    expect(
      a,
      isNot(const ReminderLaunch(
          profileId: 'p1', kind: ReminderKind.upcoming, actionId: 'started')),
    );
    expect(
      a,
      isNot(const ReminderLaunch(
          profileId: 'p1', kind: ReminderKind.late, actionId: 'not_yet')),
    );
    expect(a.hashCode,
        const ReminderLaunch(
                profileId: 'p1', kind: ReminderKind.late, actionId: 'started')
            .hashCode);
  });
}
