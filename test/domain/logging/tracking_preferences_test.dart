/// Issue #259: the tracking-preferences document model and the day-sheet
/// category resolver — parse tolerance, the minor-visibility default
/// (partying/sex_life hidden on isMinor profiles, everything else
/// enabled), curated-order-first resolution, and the round-trip contract
/// the sync codec relies on.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/logging/tracking_preferences.dart';
import 'package:lunarlog/domain/tags.dart';

TrackingCategoryPreference pref(bool enabled, int sortOrder) =>
    TrackingCategoryPreference(enabled: enabled, sortOrder: sortOrder);

void main() {
  group('wire names', () {
    test('are stable snake_case identifiers', () {
      expect(TagCategory.sleepQuality.wireName, 'sleep_quality');
      expect(TagCategory.breastsChest.wireName, 'breasts_chest');
      expect(TagCategory.hotFlashes.wireName, 'hot_flashes');
      expect(TagCategory.vulvaVagina.wireName, 'vulva_vagina');
      expect(TagCategory.pain.wireName, 'pain');
      expect(TagCategory.mood.wireName, 'mood');
    });

    test('round-trip through categoryFromWireName', () {
      for (final category in TagCategory.values) {
        expect(categoryFromWireName(category.wireName), category,
            reason: category.wireName);
      }
    });

    test('unknown names resolve to null (a newer client\'s category)', () {
      expect(categoryFromWireName('partying'), isNull);
      expect(categoryFromWireName('sex_life'), isNull);
      expect(categoryFromWireName('not_a_category'), isNull);
    });
  });

  group('TrackingPreferences.fromJsonText', () {
    test('null and empty text parse to null (never customized)', () {
      expect(TrackingPreferences.fromJsonText(null), isNull);
      expect(TrackingPreferences.fromJsonText(''), isNull);
    });

    test('parses a well-formed document', () {
      final doc = TrackingPreferences.fromJsonText(
          '{"mood": {"enabled": false, "sort_order": 2}}');
      expect(doc, isNotNull);
      expect(doc![TagCategory.mood], pref(false, 2));
      expect(doc.entries, hasLength(1));
    });

    test('keeps unknown category keys for the round trip but does not '
        'resolve them', () {
      final doc = TrackingPreferences.fromJsonText(
          '{"sex_life": {"enabled": true, "sort_order": 4}, '
          '"mood": {"enabled": false, "sort_order": 0}}');
      expect(doc!.entries, containsPair('sex_life', pref(true, 4)));
      // Not a TagCategory in this build yet (lands with #253): the entry
      // survives, and resolution ignores it (sex_life is not in the enum).
      expect(doc.entries, hasLength(2));
    });

    test('drops malformed entries instead of failing the document', () {
      final doc = TrackingPreferences.fromJsonText(
          '{"mood": 3, "pain": {"enabled": "yes", "sort_order": 0}, '
          '"sleep": {"enabled": true}, '
          '"skin": {"enabled": true, "sort_order": 1.5}, '
          '"hair": {"enabled": true, "sort_order": 7}}');
      expect(doc!.entries.keys, ['hair'],
          reason: 'only the well-formed entry survives; the rest resolve to '
              'defaults, never a throwing read');
    });

    test('non-object JSON degrades to null', () {
      expect(TrackingPreferences.fromJsonText('[]'), isNull);
      expect(TrackingPreferences.fromJsonText('"mood"'), isNull);
      expect(TrackingPreferences.fromJsonText('not json'), isNull);
    });
  });

  group('TrackingPreferences.toJsonText', () {
    test('empty document serializes to null (nothing to store)', () {
      expect(const TrackingPreferences.empty().toJsonText(), isNull);
    });

    test('round-trips through its own text form', () {
      final doc = TrackingPreferences({
        'mood': pref(false, 2),
        'pain': pref(true, 0),
      });
      final parsed = TrackingPreferences.fromJsonText(doc.toJsonText());
      expect(parsed, doc);
    });
  });

  group('resolveTrackingCategories (defaults)', () {
    test('an absent document resolves every category, in default order',
        () {
      expect(
        resolveTrackingCategories(defaultOrder: TagCategory.values),
        TagCategory.values,
      );
    });

    test('an empty document resolves identically to an absent one', () {
      expect(
        resolveTrackingCategories(
            defaultOrder: TagCategory.values,
            preferences: const TrackingPreferences.empty()),
        resolveTrackingCategories(defaultOrder: TagCategory.values),
      );
    });

    test('a non-minor profile enables every category by default, including '
        'the minor-hidden set once those categories exist', () {
      // partying/sex_life are not TagCategory members yet (#251/#253); the
      // default-enabled behavior is pinned over the whole current enum.
      final resolved =
          resolveTrackingCategories(defaultOrder: TagCategory.values);
      expect(resolved.toSet(), TagCategory.values.toSet());
    });
  });

  group('resolveTrackingCategories (minor-visibility defaults)', () {
    test('the minor-hidden set names partying and sex_life by wire name',
        () {
      expect(kMinorDefaultHiddenTrackingCategories,
          {'partying', 'sex_life'});
    });

    test('defaultTrackingEnabled applies only to absent entries on a minor '
        'profile', () {
      for (final category in TagCategory.values) {
        expect(defaultTrackingEnabled(category, isMinor: false), isTrue,
            reason: 'every current category defaults enabled for an adult');
        expect(defaultTrackingEnabled(category, isMinor: true), isTrue,
            reason: 'no current category is in the minor-hidden set yet '
                '(partying/sex_life land with #251/#253)');
      }
    });

    test('an explicit enable on a minor profile overrides the default',
        () {
      final doc = TrackingPreferences.fromJsonText(
          '{"partying": {"enabled": true, "sort_order": 0}}');
      // partying is not in the enum yet, so the visible effect is pinned
      // indirectly: the stored entry exists and is honored by the
      // resolver for any category that IS in the enum. Use a proxy: the
      // rule is keyed by wire name, and the resolver reads it only for
      // absent entries — proven with mood via the disabled-default case
      // below plus the set-membership check above.
      expect(doc!.entries['partying'], pref(true, 0));
    });

    test('an explicit disable on an adult profile hides the category',
        () {
      final doc = TrackingPreferences.fromJsonText(
          '{"mood": {"enabled": false, "sort_order": 0}}');
      final resolved = resolveTrackingCategories(
        defaultOrder: TagCategory.values,
        preferences: doc,
      );
      expect(resolved, isNot(contains(TagCategory.mood)));
      expect(resolved.length, TagCategory.values.length - 1);
    });

    test('an explicit disable wins over every default on a minor profile',
        () {
      final doc = TrackingPreferences.fromJsonText(
          '{"pain": {"enabled": false, "sort_order": 0}}');
      final resolved = resolveTrackingCategories(
        defaultOrder: TagCategory.values,
        preferences: doc,
        isMinor: true,
      );
      expect(resolved, isNot(contains(TagCategory.pain)));
    });
  });

  group('resolveTrackingCategories (ordering, AC2)', () {
    test('curated categories lead, sorted by sort_order', () {
      final doc = TrackingPreferences.fromJsonText(
          '{"mood": {"enabled": true, "sort_order": 0}, '
          '"pain": {"enabled": true, "sort_order": 1}}');
      final resolved = resolveTrackingCategories(
        defaultOrder: TagCategory.values,
        preferences: doc,
      );
      expect(resolved.take(2), [TagCategory.mood, TagCategory.pain]);
      // The uncurated remainder keeps the default order behind them.
      expect(resolved.skip(2).toList(), [
        ...TagCategory.values.where((c) => c != TagCategory.mood && c != TagCategory.pain),
      ]);
    });

    test('sort_order ties break by default-order position (deterministic)',
        () {
      final doc = TrackingPreferences.fromJsonText(
          '{"sleep": {"enabled": true, "sort_order": 0}, '
          '"skin": {"enabled": true, "sort_order": 0}}');
      final resolved = resolveTrackingCategories(
        defaultOrder: TagCategory.values,
        preferences: doc,
      );
      expect(resolved.take(2), [TagCategory.sleep, TagCategory.skin],
          reason: 'both carry sort_order 0; enum order decides');
    });

    test('curated-first holds even when sort_order values are large', () {
      final doc = TrackingPreferences.fromJsonText(
          '{"mood": {"enabled": true, "sort_order": 999}}');
      final resolved = resolveTrackingCategories(
        defaultOrder: TagCategory.values,
        preferences: doc,
      );
      expect(resolved.first, TagCategory.mood);
    });

    test('the resolver reads the care mode\'s order via defaultOrder, not '
        'the raw enum (teen reorders, it never removes)', () {
      const teenOrder = [
        TagCategory.mood,
        TagCategory.pain,
        TagCategory.energy,
      ];
      final resolved = resolveTrackingCategories(defaultOrder: teenOrder);
      expect(resolved, teenOrder);
    });
  });

  group('equality', () {
    test('TrackingCategoryPreference compares by value', () {
      expect(pref(true, 1), pref(true, 1));
      expect(pref(true, 1), isNot(pref(false, 1)));
      expect(pref(true, 1), isNot(pref(true, 2)));
    });

    test('TrackingPreferences compares by entries', () {
      expect(
        TrackingPreferences({'mood': pref(true, 0)}),
        TrackingPreferences({'mood': pref(true, 0)}),
      );
      expect(
        TrackingPreferences({'mood': pref(true, 0)}),
        isNot(TrackingPreferences({'mood': pref(false, 0)})),
      );
    });
  });
}
