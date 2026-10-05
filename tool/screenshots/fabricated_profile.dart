/// The deterministic fabricated data behind every screenshot (issue
/// #1104).
///
/// Everything the renderer draws — profile names, cycle history, tags,
/// notes, dates — comes from this file, which is a pure function of
/// [kScreenshotToday]. No real person's data exists anywhere in the
/// pipeline, and the tool *fails to start* if a profile name ever drifts
/// off the seed generator's list ([kSeedProfileNames],
/// `tool/seed_test_accounts/payload_generator.dart`): the allowlist is
/// imported, not restated, and [requireFabricatedNames] throws on anything
/// the generator does not itself fabricate. Same rule for the one
/// guardian label the sharing screenshot shows ([kFabricatedGuardianLabels]).
///
/// The two profiles mirror the seeder's standard layout (#710): the adult
/// subject ("Maya") carries six completed steady cycles, so the Today tab
/// shows the `high`-confidence exact-date estimate; the teen daughter
/// ("Riley") carries three completed cycles with a little spread, so her
/// Today tab shows the `learning` tier's range estimate — the two
/// estimate framings the site wants to show ("estimates with their
/// confidence tiers", issue #1104).
library;

import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';

import '../seed_test_accounts/payload_generator.dart';
import '../seed_test_accounts/seeder.dart';

/// The fixed clock every screenshot is rendered against. Never
/// `DateTime.now()` — two runs on the same commit must be byte-identical,
/// and that starts with the data being frozen to this date.
final LocalDate kScreenshotToday = LocalDate(2026, 9, 28);

/// The fabricated profile names the screenshots may use — exactly the
/// seed generator's own list. Never edited here; edit the generator and
/// this follows.
final List<String> kFabricatedProfileNames = kSeedProfileNames;

/// The fabricated guardian display label the sharing screenshot shows —
/// the seeder's own partner label, single-sourced the same way.
final List<String> kFabricatedGuardianLabels = [kSeedPartnerGuardianLabel];

/// Thrown when a name is about to reach a screenshot without being on the
/// generator's fabricated list. The renderer treats this as fatal: a
/// screenshot tool that can render a real name is the exact failure mode
/// issue #1104 exists to foreclose.
class FabricatedNameError extends Error {
  FabricatedNameError(this.offenders, this.allowlist);

  /// The names that failed the check.
  final List<String> offenders;

  /// The allowlist they were checked against.
  final List<String> allowlist;

  @override
  String toString() =>
      'FabricatedNameError: name(s) not on the generator\'s fabricated '
      'list: ${offenders.join(', ')}. Allowed: ${allowlist.join(', ')}. '
      'Screenshots render fabricated data only (issue #1104) — add the '
      'name to tool/seed_test_accounts/payload_generator.dart (or '
      'seeder.dart) first, never to this tool.';
}

/// Throws [FabricatedNameError] unless every name in [names] is on
/// [allowlist]. Called by the data builder for every profile name it
/// emits and by the renderer before the first frame, so a violation can
/// never reach a pixel.
void requireFabricatedNames(
  Iterable<String> names,
  List<String> allowlist,
) {
  final offenders =
      names.where((n) => !allowlist.contains(n)).toList(growable: false);
  if (offenders.isNotEmpty) {
    throw FabricatedNameError(offenders, allowlist);
  }
}

/// One fabricated logged day: the bleed (or its absence), tags, and an
/// optional note drawn from the generator's pool.
class FabricatedDay {
  const FabricatedDay({
    required this.date,
    required this.flow,
    this.tags = const [],
    this.note,
  });

  final LocalDate date;
  final FlowLevel flow;
  final List<String> tags;
  final String? note;
}

/// One fabricated profile and the day entries the renderer seeds for it.
class FabricatedProfile {
  const FabricatedProfile({
    required this.name,
    required this.isMinor,
    required this.birthYear,
    required this.days,
  });

  final String name;
  final bool isMinor;
  final int birthYear;
  final List<FabricatedDay> days;
}

LocalDate _episode(LocalDate today, int daysAgo) => today.addDays(-daysAgo);

/// The single source of fabricated screenshot data. Deterministic by
/// construction — fixed dates relative to [kScreenshotToday], fixed tags,
/// fixed notes (indexes into the generator's pool) — and self-validating:
/// building it throws if a profile name is not on the generator's list.
FabricatedProfile mayaScreenshotProfile() {
  const name = 'Maya';
  requireFabricatedNames([name], kFabricatedProfileNames);
  final today = kScreenshotToday;

  // Seven 28-day episodes, the last starting 25 days ago: six completed
  // valid cycles at zero spread -> the full kAverageWindowCycles window ->
  // the `high` tier, estimate today+3 (cycle day 26 today, nothing late).
  final starts = [for (var i = 6; i >= 0; i--) _episode(today, 25 + 28 * i)];
  final days = <FabricatedDay>[
    for (final start in starts)
      for (var i = 0; i < 4; i++)
        FabricatedDay(
          date: start.addDays(i),
          flow: FlowLevel.medium,
        ),
    // A couple of mid-cycle symptom days so the calendar's dot layer and
    // the legend read as lived-in, not synthetic.
    FabricatedDay(
      date: starts.last.addDays(10),
      flow: FlowLevel.notBleeding,
      tags: const ['cramps', 'headache'],
      note: kSeedDayNotePool[4],
    ),
    FabricatedDay(
      date: starts.last.addDays(15),
      flow: FlowLevel.notBleeding,
      tags: const ['bloating'],
      note: kSeedDayNotePool[2],
    ),
    // Today (cycle day 26): the day the "Log a day" screenshot opens on —
    // a pre-period day with the note field filled from the same pool. It
    // is also what the Today capture's log card shows (issue #1489): "Not
    // bleeding", the two tags, and "Note added" — never the note's text.
    // The site's alt text for that capture describes this card, so change
    // the two together.
    FabricatedDay(
      date: today,
      flow: FlowLevel.notBleeding,
      tags: const ['cramps', 'fatigue'],
      note: kSeedDayNotePool[0],
    ),
  ];
  return FabricatedProfile(
    name: name,
    isMinor: false,
    birthYear: 1988,
    days: days,
  );
}

/// The teen profile: four episodes of slightly varying length (28, 32, 30
/// days), the last starting 29 days ago — three completed valid cycles
/// (below the six-cycle window) and a nonzero spread, so the estimate is
/// the `learning` tier's two-date range: tomorrow ±2 days.
FabricatedProfile rileyScreenshotProfile() {
  const name = 'Riley';
  requireFabricatedNames([name], kFabricatedProfileNames);
  final today = kScreenshotToday;

  final first = _episode(today, 119);
  final starts = [first, first.addDays(28), first.addDays(60), first.addDays(90)];
  final days = <FabricatedDay>[
    for (final start in starts)
      for (var i = 0; i < 4; i++)
        FabricatedDay(
          date: start.addDays(i),
          flow: i < 2 ? FlowLevel.heavy : FlowLevel.medium,
        ),
    FabricatedDay(
      date: starts.last.addDays(8),
      flow: FlowLevel.notBleeding,
      tags: const ['mood_swings'],
      note: kSeedDayNotePool[8],
    ),
  ];
  return FabricatedProfile(
    name: name,
    isMinor: true,
    birthYear: 2012,
    days: days,
  );
}

/// Both profiles, built and name-validated in one call — the renderer's
/// only data entry point.
List<FabricatedProfile> fabricatedScreenshotProfiles() => [
      mayaScreenshotProfile(),
      rileyScreenshotProfile(),
    ];
