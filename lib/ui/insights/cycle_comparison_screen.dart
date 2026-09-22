/// The pushed screen wrapper around [CycleComparisonView] (Issue #235):
/// owns the live data this comparison needs (day entries, and the
/// cycle_overrides-backed exclusion set) so the view itself stays a pure
/// presentation widget. Watches both streams the same way `AnalysisTab`
/// watches its own entries stream, so an edit made elsewhere while this
/// screen is open (e.g. backing out to fix a logged day, then returning)
/// is reflected rather than frozen at push time.
///
/// Read-only by construction (see `cycle_comparison_view.dart`'s doc
/// comment) -- reachable from both the Analysis tab (the active profile)
/// and the archived `ProfileDetailScreen` mount of `CycleHistorySection`,
/// and from a viewer-role guardian, with no separate gating needed here.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/episodes/episodes.dart';
import '../../domain/insights/cycle_comparison.dart';
import '../../domain/models/day_entry.dart';
import '../../domain/models/local_date.dart';
import '../../domain/prediction/cycle_history.dart' show CycleExclusionList;
import '../../domain/repositories/day_entries_repository.dart';
import '../../domain/sharing/guardian_lens.dart';
import '../../observability/route_names.dart';
import 'cycle_comparison_view.dart';

import 'package:lunarlog/l10n/app_localizations.dart';

class CycleComparisonScreen extends StatefulWidget {
  const CycleComparisonScreen({
    super.key,
    required this.profileId,
    required this.cycleAStart,
    required this.cycleBStart,
    this.todayProvider = LocalDate.today,
    this.dayEntriesRepository,
    this.exclusions,
    this.lens = GuardianLens.subject,
  });

  final String profileId;
  final LocalDate cycleAStart;
  final LocalDate cycleBStart;

  /// "Today" as the device-local civil date; injectable for tests.
  final LocalDate Function() todayProvider;

  /// Injectable for tests; falls back to `context.read<DayEntriesRepository?>()`
  /// like `AnalysisTab.dayEntriesRepository` does.
  final DayEntriesRepository? dayEntriesRepository;

  /// Injectable for tests; falls back to `context.read<CycleExclusionList?>()`.
  final CycleExclusionList? exclusions;

  /// Which lens the reader is viewing the profile through (issue #850, U8):
  /// forwarded to [CycleComparisonView]'s empty-state body. Defaults to the
  /// subject lens, so pre-#850 callers are unchanged.
  final GuardianLens lens;

  static MaterialPageRoute<void> route({
    required String profileId,
    required LocalDate cycleAStart,
    required LocalDate cycleBStart,
    LocalDate Function() todayProvider = LocalDate.today,
    GuardianLens lens = GuardianLens.subject,
  }) =>
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: kRouteCycleComparisonScreen),
        builder: (_) => CycleComparisonScreen(
          profileId: profileId,
          cycleAStart: cycleAStart,
          cycleBStart: cycleBStart,
          todayProvider: todayProvider,
          lens: lens,
        ),
      );

  @override
  State<CycleComparisonScreen> createState() => _CycleComparisonScreenState();
}

class _CycleComparisonScreenState extends State<CycleComparisonScreen> {
  StreamSubscription<List<DayEntry>>? _entriesSub;
  StreamSubscription<Set<LocalDate>>? _exclusionsSub;
  List<DayEntry> _entries = const [];
  Set<LocalDate> _excluded = const {};

  @override
  void initState() {
    super.initState();
    _watchEntries();
    _watchExclusions();
  }

  void _watchEntries() {
    final repository =
        widget.dayEntriesRepository ?? context.read<DayEntriesRepository?>();
    if (repository == null) return;
    _entriesSub = repository.watchForProfile(widget.profileId).listen((
      entries,
    ) {
      if (!mounted) return;
      setState(() => _entries = entries);
    });
  }

  void _watchExclusions() {
    final exclusions = widget.exclusions ?? context.read<CycleExclusionList?>();
    if (exclusions == null) return;
    _exclusionsSub = exclusions.watch(widget.profileId).listen((excluded) {
      if (!mounted) return;
      setState(() => _excluded = excluded);
    });
  }

  @override
  void dispose() {
    unawaited(_entriesSub?.cancel());
    unawaited(_exclusionsSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final episodes = deriveEpisodes(bleedDatesOf(_entries));
    final data = deriveCycleComparison(
      episodes: episodes,
      entries: _entries,
      today: widget.todayProvider(),
      cycleAStart: widget.cycleAStart,
      cycleBStart: widget.cycleBStart,
      excludedCycleStarts: _excluded,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).cycleComparisonScreenTitle),
      ),
      body: SafeArea(child: CycleComparisonView(data: data, lens: widget.lens)),
    );
  }
}
