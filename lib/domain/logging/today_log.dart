/// What is logged for one civil day, as the Today screen reads it (issue
/// #1489).
///
/// Today used to show the estimate and nothing about the day's own log, so
/// a day with cramps logged looked the same as a day with nothing logged.
/// [TodayLog] is the value the Today log card and the floating button's
/// label are both derived from, and [TodayLog.hasContent] is the one rule
/// for "is anything logged today" that the two share.
///
/// The rules for what the Today log may say about a day live here too, so
/// that the app's card and the browser version's card cannot say different
/// things: which flow the day reads as ([TodayLog.flowLine]) and which tags
/// are named, counted, or left for "and N more" ([todayLogTagsOf]). The
/// browser reaches them through `tool/web_domain/facade.dart`.
///
/// Pure Dart with no drift/Flutter imports (R14/R16).
library;

import '../models/day_entry.dart';
import '../models/flow_level.dart';
import '../models/observation.dart';
import '../models/observation_category.dart';
import '../tags.dart'
    show TagCategory, contextualDisplayForTag, flatDisplayForTag, tagByCode;
import 'custom_tag_registry.dart';
import 'day_sheet_reconciliation.dart' show manualMeasurementIn;

/// What the Today log says about a day's flow.
enum TodayLogFlow {
  /// A bleed level, read as "{level} flow". The level is the entry's own
  /// [DayEntry.flow].
  bleed,

  /// A spotting record with no bleed level: "Spotting".
  spotting,

  /// An explicit "not bleeding", with no spotting record: "Not bleeding".
  notBleeding,
}

/// One day's live entry and the observations attached to it.
class TodayLog {
  const TodayLog({this.entry, this.observations = const []});

  /// The day's live entry, or null when the day has none.
  final DayEntry? entry;

  /// The live observations attached to [entry]: spotting, and the BBT and
  /// weight readings the day sheet stores outside the entry row. Empty when
  /// there is no entry, or no observations seam to read them from.
  final List<Observation> observations;

  /// Whether the day has a note. Only the fact: nothing that reads a
  /// [TodayLog] for the Today screen is given the note's text.
  bool get hasNote => entry?.note?.trim().isNotEmpty ?? false;

  /// Whether the day carries a spotting record. Spotting is stored as its
  /// own observation, never as a flow level (issue #247), so the entry's
  /// flow alone reads "not bleeding" on a spotting day.
  bool get hasSpotting => observations.any(
        (observation) => observation.category == ObservationCategory.spotting,
      );

  /// The basal body temperature the day sheet shows for this day, if any.
  Observation? get bbt =>
      manualMeasurementIn(observations, ObservationCategory.bbt);

  /// The weight the day sheet shows for this day, if any.
  Observation? get weight =>
      manualMeasurementIn(observations, ObservationCategory.weight);

  /// Whether anything is logged for the day.
  ///
  /// No entry, a tombstoned entry, and an entry left with nothing on it all
  /// count as nothing logged — the day sheet autosaves, so opening it,
  /// picking a tag and taking it off again leaves a live row with no flow,
  /// no tags and no note. The PMS marker and a temperature or weight
  /// reading count as logged: each is something the person entered, and a
  /// day holding only one of them is not an empty day.
  ///
  /// So does a spotting record, whoever wrote it. The day sheet raises the
  /// flow to "not bleeding" when it records spotting, but the health import
  /// stores a spotting-only day with no flow at all, and that day is not
  /// empty either: the day sheet opens on it with Spotting chosen and the
  /// calendar marks it.
  bool get hasContent {
    final entry = this.entry;
    if (entry == null || entry.deletedAt != null) return false;
    return _entryHasContent(entry) ||
        hasSpotting ||
        bbt != null ||
        weight != null;
  }

  bool _entryHasContent(DayEntry entry) =>
      entry.flow != FlowLevel.none ||
      entry.tags.isNotEmpty ||
      entry.pms ||
      hasNote;

  /// What the Today log says about the day's flow, or null when the day
  /// records none.
  ///
  /// Bleed wins over spotting, as on the calendar (issue #761). Otherwise a
  /// spotting record reads as spotting — the entry's own flow says "not
  /// bleeding" on such a day, which is the one thing it was not — and an
  /// explicit "not bleeding" reads as itself.
  TodayLogFlow? get flowLine {
    final flow = entry?.flow ?? FlowLevel.none;
    if (isBleed(flow)) return TodayLogFlow.bleed;
    if (hasSpotting) return TodayLogFlow.spotting;
    return switch (flow) {
      FlowLevel.notBleeding => TodayLogFlow.notBleeding,
      // The alias a row stored before spotting became its own record
      // (issue #247) still means spotting.
      // ignore: deprecated_member_use_from_same_package
      FlowLevel.spotting => TodayLogFlow.spotting,
      _ => null,
    };
  }
}

/// The most tags the Today log names before it says "and N more".
const int kTodayLogMaxTags = 6;

/// The tag categories the Today log counts without naming: sex life and
/// test results. Today is the screen the app opens on, read at a glance and
/// often with someone else in the room. A custom tag has no category and is
/// named like any other, once the profile's registry says what it is
/// called.
const Set<TagCategory> kTodayLogUnnamedCategories = {
  TagCategory.sexLife,
  TagCategory.tests,
};

/// Categories whose options say what they are without their heading
/// ("Bloating", "Nausea"), so the Today log does not prefix them the way
/// the clinical export does ("Digestion: Bloating").
const Set<TagCategory> _kSelfDescribingOnToday = {TagCategory.digestion};

/// Whether [code] is a tag the Today log counts without naming: a curated
/// tag in [kTodayLogUnnamedCategories], or a code that neither the curated
/// taxonomy nor [customTags] (the profile's own registry) knows.
///
/// The second kind matters because an unknown code has no label to show,
/// only itself, and what it stands for cannot be told from here: a later
/// version of the app may add a sex-life or test tag that this build would
/// otherwise print on the screen the app opens on. The day sheet keeps its
/// own rule, that an unknown code is shown rather than dropped
/// ([tagDisplayLabel]); here it is counted rather than dropped.
///
/// A custom tag is therefore counted until its registry row is in hand
/// (the registry has not answered yet, or has not synced to this device),
/// and named from then on.
bool isUnnamedOnToday(String code, Iterable<CustomTag> customTags) {
  final curated = tagByCode(code);
  if (curated != null) {
    return kTodayLogUnnamedCategories.contains(curated.category);
  }
  return !customTags.any((tag) => tag.code == code);
}

/// A tag's label for the Today log, which shows no category headings. A
/// curated tag takes the label the app already uses where headings are
/// absent ([contextualDisplayForTag]): "Sticky" becomes "Vaginal discharge:
/// Sticky", "Normal" becomes "Stool: Normal" and the medication tag "Pain"
/// becomes "Took pain medication", none of which the bare word says. A
/// self-describing category (digestion) keeps its own word, with only a
/// true clash resolved ("Great (digestion)", [flatDisplayForTag]). A custom
/// tag reads by the name its registry row gives it, as on the day sheet
/// ([tagDisplayLabel]).
///
/// Only for a code [isUnnamedOnToday] lets through: a code that is neither
/// curated nor in [customTags] has no label, and comes back as itself.
String todayTagLabel(String code, Iterable<CustomTag> customTags) {
  final curated = tagByCode(code);
  if (curated == null) return tagDisplayLabel(code, customTags);
  return _kSelfDescribingOnToday.contains(curated.category)
      ? flatDisplayForTag(curated)
      : contextualDisplayForTag(curated);
}

/// A day's tags as the Today log says them: labels and counts only, never a
/// tag code.
class TodayLogTags {
  const TodayLogTags({this.named = const [], this.unnamedCount = 0});

  /// The label of every tag the log may name, in the order the entry stores
  /// them. The log shows the first [kTodayLogMaxTags] ([shown]) and counts
  /// the rest.
  final List<String> named;

  /// How many of the day's tags are counted without being named: those in
  /// [kTodayLogUnnamedCategories], and any code this build does not know.
  final int unnamedCount;

  /// The labels the log shows: the first [kTodayLogMaxTags] of [named].
  List<String> get shown => named.take(kTodayLogMaxTags).toList();

  /// How many tags the log counts instead of naming: the named ones past
  /// the limit, and the unnamed ones. "and N more" after [shown], or
  /// "N other entries" when nothing is shown.
  int get moreCount {
    final overflow = named.length - kTodayLogMaxTags;
    return (overflow > 0 ? overflow : 0) + unnamedCount;
  }
}

/// The Today log's reading of a day's tag [codes], given the profile's own
/// registry [customTags]: which are named and by what label
/// ([todayTagLabel]), and how many are only counted ([isUnnamedOnToday]).
TodayLogTags todayLogTagsOf(
  Iterable<String> codes,
  Iterable<CustomTag> customTags,
) {
  final named = <String>[];
  var unnamedCount = 0;
  for (final code in codes) {
    if (isUnnamedOnToday(code, customTags)) {
      unnamedCount++;
    } else {
      named.add(todayTagLabel(code, customTags));
    }
  }
  return TodayLogTags(named: named, unnamedCount: unnamedCount);
}
