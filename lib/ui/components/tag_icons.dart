/// Per-option icon vocabulary for the taxonomy tag chips (Issue #818).
///
/// Category headers have carried a Material icon since Issue #234
/// (`category_picker.dart`'s `_kCategoryIcons`), but the option chips under
/// them were text-only — roughly a hundred identical pills on the app's
/// primary input surface. This file gives an option a leading icon **only
/// where a Material glyph reads unambiguously as that option**, so the grid
/// becomes recognisable at a glance (recognition instead of recall) without
/// forcing a vague glyph onto options that have none.
///
/// Deliberately sparse, and deliberately not a placeholder. An option with
/// no entry here renders text-only — never `Icons.label_outline` or any
/// other generic stand-in. A vague glyph on half the chips adds visual
/// noise without adding meaning, which is worse than plain text (the
/// owner's documented fallback for Issue #818). The exclusions are as much
/// a decision as the inclusions:
///
/// * **Moods/feelings** (`happy`, `sad`, `irritable`, ...) — a smiley reads
///   as a rating, not a feeling, and the sentiment set flattens nuance.
/// * **Abstract gradations** — energy (`tired`/`exhausted`), sleep duration
///   buckets, stool, skin/hair ("good"/"oily"/"dry"), vaginal dryness: every
///   option in the family would get the same glyph, which is a placeholder
///   in disguise.
/// * **"Great"** (`great_digestion`, `great_stool`) — a positive assertion
///   with no distinctive symbol; `pain_free`'s check-circle is reserved for
///   the affirmative "none today" assertion, not "it was good".
/// * **Collection method, discharge, sex life, medication, tests,
///   supplements, appointments** — no glyph actually identifies the option
///   (all pills look alike; there is no pad/cup/tampon icon), and the
///   sensitive vocabularies are left to their text labels.
/// * **Head pain beyond `headache`** (`migraine`,
///   `migraine_with_aura`, `back_pain`) — `Icons.psychology_alt` is the one
///   head glyph Flutter's built-in set ships; repeating it three ways would
///   make the three chips indistinguishable.
///
/// The day sheet's flow-level `ChoiceChip`s are also intentionally left
/// text-only: flow is a magnitude scale, and a single droplet repeated
/// across None/Light/Medium/Heavy/Super heavy would be the same placeholder
/// this file exists to avoid (see the PR for the full list).
library;

import 'package:flutter/material.dart';

/// The leading icon for the taxonomy option identified by [code], or null
/// when no unambiguous Material glyph exists — in which case the chip
/// renders text-only and must not substitute a generic placeholder.
///
/// A plain table lookup (not a `switch`), so the mapping stays data and the
/// method stays trivially under the CRAP gate.
IconData? tagOptionIcon(String code) => _kTagOptionIcons[code];

/// Option code -> icon. Keys are the stable [TagCode.code] strings in
/// `lib/domain/tags.dart` — never displays, which are locale-dependent —
/// and every key is pinned to a real taxonomy code by
/// `test/ui/components/category_picker_test.dart`.
const Map<String, IconData> _kTagOptionIcons = {
  // Physical pain
  'cramps': Icons.bolt,
  // `psychology_alt` (a head silhouette), used here for the one head-pain
  // option Flutter's set can actually carry — `neurology`/`headache` are
  // not shipped by the pinned Flutter version.
  'headache': Icons.psychology_alt,
  'breast_tenderness': Icons.favorite_border,
  'ovulation': Icons.egg_outlined,
  'pain_free': Icons.check_circle_outline,

  // Sleep
  'sleep_trouble': Icons.bedtime_outlined,

  // Digestion
  'bloating': Icons.bubble_chart,
  'nausea': Icons.sick_outlined,
  'gassy': Icons.air,

  // Cravings
  'sweet': Icons.icecream_outlined,
  'salty': Icons.grain,
  'carbs': Icons.rice_bowl_outlined,
  'chocolate': Icons.cookie_outlined,

  // Hot flashes / perimenopause
  'hot_flashes': Icons.local_fire_department_outlined,
  'brain_fog': Icons.foggy,

  // Partying
  'drinks': Icons.local_bar_outlined,
  'cigarettes': Icons.smoking_rooms,
  'big_night': Icons.celebration_outlined,

  // Exercise
  'running': Icons.directions_run,
  'yoga': Icons.self_improvement,
  'biking': Icons.directions_bike,
  'swimming': Icons.pool,
  'walking': Icons.directions_walk,
  'rest_day': Icons.hotel_outlined,

  // Ailments
  'injury': Icons.personal_injury_outlined,
  'fever': Icons.thermostat,
};
