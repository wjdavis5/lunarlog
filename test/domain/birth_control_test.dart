/// Unit tests for the birth-control vocabulary (Issue #260): the six
/// per-day intake categories, the canonical profile-level method ids
/// with tolerant/legacy reads, the pill adherence values, and the
/// in-effect resolver #233/#183/#152 consume.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/birth_control.dart';
import 'package:lunarlog/domain/models/local_date.dart';

void main() {
  group('category family (AC1)', () {
    test('carries exactly the six method categories', () {
      expect(kBirthControlCategories, hasLength(6));
      expect(
        kBirthControlCategories,
        containsAll([
          'birth_control_pill',
          'birth_control_shot',
          'birth_control_implant',
          'birth_control_patch',
          'birth_control_ring',
          'birth_control_iud',
        ]),
      );
      for (final category in kBirthControlCategories) {
        expect(category, startsWith(kBirthControlCategoryPrefix));
      }
    });

    test('isBirthControlCategory is a total membership test', () {
      expect(isBirthControlCategory('birth_control_pill'), isTrue);
      expect(isBirthControlCategory('birth_control_iud'), isTrue);
      expect(isBirthControlCategory('pain'), isFalse);
      expect(isBirthControlCategory(null), isFalse);
      expect(isBirthControlCategory('birth_control_other'), isFalse,
          reason: 'only the six tracked categories are in the family');
    });

    test('every tracked method maps to its intake category and back', () {
      expect(BirthControlMethod.pill.intakeCategory,
          kBirthControlPillCategory);
      expect(BirthControlMethod.shot.intakeCategory,
          kBirthControlShotCategory);
      expect(BirthControlMethod.implant.intakeCategory,
          kBirthControlImplantCategory);
      expect(BirthControlMethod.patch.intakeCategory,
          kBirthControlPatchCategory);
      expect(BirthControlMethod.ring.intakeCategory, kBirthControlRingCategory);
      expect(BirthControlMethod.hormonalIud.intakeCategory,
          kBirthControlIudCategory);
      expect(BirthControlMethod.copperIud.intakeCategory,
          kBirthControlIudCategory,
          reason: 'the IUD category deliberately covers both flavors');

      expect(
          BirthControlMethod.forIntakeCategory(kBirthControlPillCategory),
          BirthControlMethod.pill);
      expect(
          BirthControlMethod.forIntakeCategory(kBirthControlIudCategory),
          BirthControlMethod.hormonalIud,
          reason: 'the category cannot carry the flavor');
      expect(BirthControlMethod.forIntakeCategory('pain'), isNull);
      expect(BirthControlMethod.forIntakeCategory(null), isNull);
    });

    test('non-tracked answers carry no intake category', () {
      for (final method in [
        BirthControlMethod.none,
        BirthControlMethod.condom,
        BirthControlMethod.other,
        BirthControlMethod.unknown,
      ]) {
        expect(method.intakeCategory, isNull);
        expect(method.isTracked, isFalse);
      }
      for (final method in BirthControlMethod.values) {
        if (method.intakeCategory != null) {
          expect(method.isTracked, isTrue);
          expect(kBirthControlCategories, contains(method.intakeCategory));
        }
      }
    });
  });

  group('BirthControlMethod stored ids (AC3/AC5)', () {
    test('toDb emits the canonical snake_case ids', () {
      expect(BirthControlMethod.none.toDb(), 'none');
      expect(BirthControlMethod.pill.toDb(), 'pill');
      expect(BirthControlMethod.shot.toDb(), 'shot');
      expect(BirthControlMethod.implant.toDb(), 'implant');
      expect(BirthControlMethod.patch.toDb(), 'patch');
      expect(BirthControlMethod.ring.toDb(), 'ring');
      expect(BirthControlMethod.hormonalIud.toDb(), 'hormonal_iud');
      expect(BirthControlMethod.copperIud.toDb(), 'copper_iud');
      expect(BirthControlMethod.condom.toDb(), 'condom');
      expect(BirthControlMethod.other.toDb(), 'other');
    });

    test('toDb refuses to store an unknown method', () {
      expect(() => BirthControlMethod.unknown.toDb(), throwsStateError);
    });

    test('every canonical id round-trips through fromDb', () {
      for (final method in BirthControlMethod.values) {
        if (method == BirthControlMethod.unknown) continue;
        expect(BirthControlMethod.fromDb(method.toDb()), method);
      }
    });

    test('null/blank parses to null (never answered)', () {
      expect(BirthControlMethod.fromDb(null), isNull);
      expect(BirthControlMethod.fromDb(''), isNull);
    });

    test('an unrecognised value degrades to unknown, never throws', () {
      expect(BirthControlMethod.fromDb('diaphragm'),
          BirthControlMethod.unknown);
    });

    test('pre-#260 legacy stored values still parse', () {
      expect(BirthControlMethod.fromDb('Pill'), BirthControlMethod.pill);
      expect(BirthControlMethod.fromDb('Injection'), BirthControlMethod.shot);
      expect(
          BirthControlMethod.fromDb('injection'), BirthControlMethod.shot,
          reason: 'the pre-#260 draft id');
      expect(BirthControlMethod.fromDb('Hormonal IUD'),
          BirthControlMethod.hormonalIud);
      expect(BirthControlMethod.fromDb('Copper IUD'),
          BirthControlMethod.copperIud);
      expect(BirthControlMethod.fromDb('Implant'), BirthControlMethod.implant);
      expect(
          BirthControlMethod.fromDb('Vaginal ring'), BirthControlMethod.ring);
      expect(BirthControlMethod.fromDb('Patch'), BirthControlMethod.patch);
      expect(BirthControlMethod.fromDb('Condom'), BirthControlMethod.condom);
      expect(BirthControlMethod.fromDb('None'), BirthControlMethod.none);
      expect(BirthControlMethod.fromDb('Other'), BirthControlMethod.other);
    });
  });

  group('PillAdherence (AC2)', () {
    test('toDb emits the taken/late/missed wire strings', () {
      expect(PillAdherence.taken.toDb(), 'taken');
      expect(PillAdherence.late.toDb(), 'late');
      expect(PillAdherence.missed.toDb(), 'missed');
    });

    test('every value round-trips through fromDb', () {
      for (final adherence in PillAdherence.values) {
        expect(PillAdherence.fromDb(adherence.toDb()), adherence);
      }
    });

    test('an unrecognised/absent code degrades to null', () {
      expect(PillAdherence.fromDb('skipped'), isNull,
          reason: 'stored-never-rejected: an unrecognised intake code '
              'round-trips on the row but reads as no known adherence');
      expect(PillAdherence.fromDb(null), isNull);
    });
  });

  group('birthControlMethodInEffectOn (AC5 seam)', () {
    final day = LocalDate(2026, 9, 7);

    test('no recorded method resolves to null', () {
      expect(
        birthControlMethodInEffectOn(
            storedMethod: null, startedOn: null, stoppedOn: null, date: day),
        isNull,
      );
      expect(
        birthControlMethodInEffectOn(
            storedMethod: '', startedOn: null, stoppedOn: null, date: day),
        isNull,
      );
    });

    test('an affirmative none answer is not a tracked method', () {
      expect(
        birthControlMethodInEffectOn(
            storedMethod: 'none',
            startedOn: null,
            stoppedOn: null,
            date: day),
        isNull,
      );
    });

    test('an unparseable method is never acted on', () {
      expect(
        birthControlMethodInEffectOn(
            storedMethod: 'diaphragm',
            startedOn: null,
            stoppedOn: null,
            date: day),
        isNull,
      );
    });

    test('tracked methods resolve through with no dates set', () {
      expect(
        birthControlMethodInEffectOn(
            storedMethod: 'pill', startedOn: null, stoppedOn: null, date: day),
        BirthControlMethod.pill,
      );
      expect(
        birthControlMethodInEffectOn(
            storedMethod: 'copper_iud',
            startedOn: null,
            stoppedOn: null,
            date: day),
        BirthControlMethod.copperIud,
      );
    });

    test('non-tracked answers (condom/other/unknown) resolve to null', () {
      for (final stored in ['condom', 'other']) {
        expect(
          birthControlMethodInEffectOn(
              storedMethod: stored,
              startedOn: null,
              stoppedOn: null,
              date: day),
          isNull,
        );
      }
    });

    test('start day is inclusive', () {
      expect(
        birthControlMethodInEffectOn(
          storedMethod: 'pill',
          startedOn: '2026-09-07',
          stoppedOn: null,
          date: day,
        ),
        BirthControlMethod.pill,
      );
      expect(
        birthControlMethodInEffectOn(
          storedMethod: 'pill',
          startedOn: '2026-09-08',
          stoppedOn: null,
          date: day,
        ),
        isNull,
        reason: 'the day before the start date the method is not yet in effect',
      );
    });

    test('stop day is exclusive', () {
      expect(
        birthControlMethodInEffectOn(
          storedMethod: 'pill',
          startedOn: null,
          stoppedOn: '2026-09-07',
          date: day,
        ),
        isNull,
        reason: 'on the stop date itself the method is no longer in effect',
      );
      expect(
        birthControlMethodInEffectOn(
          storedMethod: 'pill',
          startedOn: null,
          stoppedOn: '2026-09-08',
          date: day,
        ),
        BirthControlMethod.pill,
      );
    });

    test('a window excluding the date resolves to null', () {
      expect(
        birthControlMethodInEffectOn(
          storedMethod: 'ring',
          startedOn: '2026-08-01',
          stoppedOn: '2026-08-22',
          date: day,
        ),
        isNull,
      );
      expect(
        birthControlMethodInEffectOn(
          storedMethod: 'ring',
          startedOn: '2026-08-01',
          stoppedOn: '2026-09-08',
          date: day,
        ),
        BirthControlMethod.ring,
      );
    });
  });
}
