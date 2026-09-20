/// Issue #844 release guard: the reminder action-button labels render on an
/// expanded lock-screen notification, so they are held to the same KTD7
/// "generic copy only" bar the title and body already are. Before #844 the
/// `Spotting` label put a health word in front of anyone holding the phone,
/// directly contradicting the "#184 editor copy" promise that lunarlog adds
/// no health detail to notification text.
///
/// The scan below is the real deliverable: a label may be re-edited by
/// anyone, but reintroducing a health word now fails a release test. The
/// action **ids** are pinned too, because the labels are display-only — the
/// id `spotting` is what makes "A little" still log spotting, so the ids must
/// not change alongside the copy.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/notifications/reminder_payload.dart';

/// Every health word a lock-screen label must never contain. Matched as a
/// case-insensitive substring, so a stem like `menstrua` also catches
/// `menstrual`/`menstruation`.
const List<String> kHealthDenyList = [
  'spotting',
  'period',
  'flow',
  'bleed',
  'cramp',
  'cycle',
  'menstrua',
  'ovulation',
  'fertile',
  'pregnan',
  'symptom',
  'discharge',
];

/// True when [text] names any health detail in [kHealthDenyList]. Kept as a
/// named, directly-testable predicate so the guard's own non-vacuity is
/// proven below (a guard that never fires is worse than none).
bool namesHealthDetail(String text) {
  final lower = text.toLowerCase();
  return kHealthDenyList.any(lower.contains);
}

void main() {
  group(
    'reminder action labels stay neutral on a lock screen (issue #844)',
    () {
      test('the labels are the new neutral strings', () {
        expect(kReminderActionStartedLabel, 'Yes');
        expect(kReminderActionSpottingLabel, 'A little');
        expect(kReminderActionNotYetLabel, 'Not yet');
      });

      test('no rendered action label names a health detail', () {
        const labels = [
          kReminderActionStartedLabel,
          kReminderActionSpottingLabel,
          kReminderActionNotYetLabel,
        ];
        for (final label in labels) {
          expect(
            namesHealthDetail(label),
            isFalse,
            reason: 'the lock-screen label "$label" must stay generic (KTD7)',
          );
        }
      });

      test('the deny-list guard fails when a health word is reintroduced', () {
        // The regression that matters: an edit that puts "Spotting" (or any
        // other health word) back into a label must be caught. Prove the scan
        // is not vacuous by feeding it the old label and every deny-list word.
        expect(namesHealthDetail('Spotting'), isTrue);
        expect(namesHealthDetail('Started'), isFalse);
        for (final word in kHealthDenyList) {
          expect(namesHealthDetail(word), isTrue, reason: 'missed "$word"');
        }
      });

      test('the action ids are unchanged (labels are display-only)', () {
        // Tapping "A little" must still decode as the spotting action; the
        // neutral copy is the only thing that changed.
        expect(kReminderActionStarted, 'started');
        expect(kReminderActionSpotting, 'spotting');
        expect(kReminderActionNotYet, 'not_yet');
        expect(kReminderActionIds, const ['started', 'spotting', 'not_yet']);
      });
    },
  );
}
