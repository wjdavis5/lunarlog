/// The home-screen widget's render state (issue #141) and the exact payload
/// that crosses the app-group boundary.
///
/// ## Why this file exists
///
/// A home-screen widget renders outside the device-credential gate
/// (`lib/ui/gate/`): it is drawn by the OS on the home screen, and no gate
/// ever runs before it renders. It also reads from a shared container (the
/// iOS App Group / the Android `HomeWidgetPreferences` store via the
/// `home_widget` plugin), which is **outside the app's encrypted Drift
/// store** — whatever is written there has left every protection the store
/// has. Issue #141's design constraints therefore require:
///
/// * a **discreet default render** — no profile name, no flow level, no
///   symptom, no health word, no date; a neutral state indicator at most.
///   This is also how the widget reconciles with the app-switcher snapshot
///   suppression (the opaque cover plus Android's `FLAG_SECURE`,
///   `lib/app_lifecycle.dart` / `MainActivity.kt`): those protect the app's
///   *own windows*, a surface the gate controls. A widget is the launcher's
///   window — `FLAG_SECURE` cannot apply to it and the gate never sees it —
///   so the only way to honor the same privacy investment is to never put
///   sensitive content on that surface in the first place. This render state
///   is that design: the numbers below are the whole story.
/// * a **minimal, documented boundary** — the field table below is the
///   complete, exhaustive set of keys the app ever writes to the widget
///   container ([encodeWidgetPayload] is the only writer). Nothing else may
///   be added without its own row in this header and a privacy review.
///
/// ## The render state itself
///
/// [WidgetCycleState] is derived purely from a [CyclePrediction] plus the
/// operator's logging role, so the same unit tests that cover the predictor
/// drive it. The render vocabulary is deliberately numeric-only:
///
/// * [WidgetCycleStateKind.cycleDay] renders as "Day 14" — a bare count,
///   no name, no phase word. During a logged episode the count simply
///   keeps counting; the widget never renders the word "period".
/// * the days-until-next estimate renders as "≈7 d" — a relative count,
///   never a calendar date.
/// * [WidgetCycleStateKind.noData], [WidgetCycleStateKind.suppressed] and
///   [WidgetCycleStateKind.off] all render as an em dash — "nothing to
///   show" is indistinguishable across the three, because the *reason*
///   (thin history, birth control, a lifecycle mode, predictions turned
///   off) is itself health context.
///
/// ## The boundary field table
///
/// Written by [WidgetCycleStatePayload.encode], the only writer:
///
/// | Key | Value | Why it crosses |
/// |-----|-------|----------------|
/// | `ll_widget_state` | `day`/`no_data`/`suppressed`/`off` | the render |
/// | `ll_widget_cycle_day` | stringified int | the "Day 14" count |
/// | `ll_widget_days_until_next` | stringified int | the "≈7 d" countdown |
/// | `ll_widget_can_quick_log` | `1`/`0` | whether the button renders |
/// | `ll_widget_profile_id` | opaque ULID | routes the gated write; never rendered |
/// | `ll_widget_as_of` | `yyyy-MM-dd` | lets native roll the count forward |
library;

import '../models/local_date.dart';
import '../prediction/prediction.dart';

/// The widget's coarse render state. Deliberately small: each member maps
/// to one neutral native render, and the mapping lives in the platform
/// widget code (Swift/Kotlin), keyed on [WidgetCycleStatePayload.keyState].
enum WidgetCycleStateKind {
  /// Not enough history for any estimate: renders as an em dash.
  noData,

  /// A live cycle: renders "Day N" (plus the estimate count when one is
  /// active). Covers an in-progress logged episode too — the count keeps
  /// counting, no phase word is ever rendered.
  cycleDay,

  /// Predictions exist but are suppressed (a continuous birth-control
  /// method or a pregnancy/postpartum/perimenopause lifecycle mode):
  /// renders as an em dash, indistinguishable from [noData] on purpose —
  /// *why* predictions are suppressed is health context.
  suppressed,

  /// The operator turned predictions off (issue #225): renders as an em
  /// dash, indistinguishable from [noData] on purpose.
  off,
}

/// The discreet render state for one profile (see the library doc for the
/// privacy posture). Every field is a number or a bool — never a name, a
/// date, a flow level, or a symptom.
class WidgetCycleState {
  const WidgetCycleState({
    required this.kind,
    this.cycleDay = 0,
    this.daysUntilNext,
    this.canQuickLog = false,
  });

  /// Builds the state from a prediction plus the logging-role answer.
  ///
  /// [canQuickLog] is the role gate: `true` only when the operator's
  /// accepted role on this profile may log (every role except `viewer`).
  /// Unknown roles fail open exactly like the day sheet and the overview
  /// do (`acceptedGuardianFor`'s null-vs-empty discipline): a local-only
  /// operator with no guardian rows keeps the action; a **known viewer
  /// never gets it**.
  factory WidgetCycleState.fromPrediction(
    CyclePrediction prediction, {
    required bool canQuickLog,
  }) {
    switch (prediction) {
      case NotEnoughHistory():
        // Thin history still gets the quick-log affordance — logging is
        // exactly how the history accumulates (issue #141's motivation).
        return WidgetCycleState(
          kind: WidgetCycleStateKind.noData,
          canQuickLog: canQuickLog,
        );
      case PredictionsSuppressed():
        return WidgetCycleState(
          kind: WidgetCycleStateKind.suppressed,
          canQuickLog: canQuickLog,
        );
      case PredictionsDisabled():
        return WidgetCycleState(
          kind: WidgetCycleStateKind.off,
          canQuickLog: canQuickLog,
        );
      case ActivePrediction(:final cycleDay, :final daysUntilNextStart):
        return WidgetCycleState(
          kind: WidgetCycleStateKind.cycleDay,
          cycleDay: cycleDay,
          daysUntilNext: daysUntilNextStart,
          canQuickLog: canQuickLog,
        );
    }
  }

  /// The coarse render kind (see the enum's doc).
  final WidgetCycleStateKind kind;

  /// 1-based day of the current cycle. Meaningful only when [kind] is
  /// [WidgetCycleStateKind.cycleDay].
  final int cycleDay;

  /// Whole days until the estimated next period start, when an estimate is
  /// active (an [ActivePrediction]); null when no estimate exists. A bare
  /// relative count — the native render never expands it into a date.
  final int? daysUntilNext;

  /// Whether the quick-log affordance is offered. Rendered as a button on
  /// the widget surface only when true; the write itself is still gated and
  /// re-verified in the app (`WidgetQuickLogExecutor`) — this flag only
  /// decides what the widget shows.
  final bool canQuickLog;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WidgetCycleState &&
          other.kind == kind &&
          other.cycleDay == cycleDay &&
          other.daysUntilNext == daysUntilNext &&
          other.canQuickLog == canQuickLog;

  @override
  int get hashCode => Object.hash(kind, cycleDay, daysUntilNext, canQuickLog);

  @override
  String toString() =>
      'WidgetCycleState(${kind.name}, day: $cycleDay, '
      'next: $daysUntilNext, canQuickLog: $canQuickLog)';
}

/// The exact keys the app writes to the shared widget container. This list
/// is the privacy boundary (issue #141's AC: "documented and minimal") —
/// every key carries its justification inline, and the App Store / Play
/// privacy declarations reference this same set (PRIVACY.md §11).
abstract final class WidgetCycleStatePayload {
  /// The coarse state, one of `day` / `no_data` / `suppressed` / `off`.
  ///
  /// Why it crosses: it is the render. Nothing more specific than the four
  /// neutral states above.
  static const String keyState = 'll_widget_state';

  /// The 1-based cycle-day count, as a stringified int (`"14"`).
  ///
  /// Why it crosses: the "Day 14" count. A bare number — it names no event,
  /// no phase, and (without a calendar on the same surface) not even a date.
  static const String keyCycleDay = 'll_widget_cycle_day';

  /// The days-until-next-estimate count, as a stringified int (`"7"`).
  /// Absent when no estimate is active.
  ///
  /// Why it crosses: the "≈7 d" countdown. Relative days only — never the
  /// underlying date, whose weekday pattern would itself be cycle detail.
  static const String keyDaysUntilNext = 'll_widget_days_until_next';

  /// `"1"` when the quick-log affordance is offered, `"0"` otherwise.
  ///
  /// Why it crosses: the widget has to know whether to draw the button.
  /// Render-only — the write path re-verifies the role against the live
  /// repositories before anything is saved, so a stale or tampered value
  /// here cannot widen who can write.
  static const String keyCanQuickLog = 'll_widget_can_quick_log';

  /// The profile id the widget's quick-log action routes to (an opaque
  /// ULID). Never rendered anywhere.
  ///
  /// Why it crosses: the widget builds the `lunarlog://` intent itself, so
  /// the id must be readable by native code. It is a random identifier,
  /// not a name and not health data; the render never displays it.
  static const String keyProfileId = 'll_widget_profile_id';

  /// The app-local civil date (`yyyy-MM-dd`) the counts above are anchored
  /// to, so the native timeline can roll "Day 14" forward by whole days
  /// without the app running. It is the publishing day — the same fact the
  /// device's own clock shows — not health data.
  static const String keyAsOf = 'll_widget_as_of';

  /// Encodes [state] into the container's key set. [encodeWidgetPayload]'s
  /// output is the *complete* write: exactly the six keys above, nothing
  /// else. All values are strings (the lowest common type across both
  /// platforms' stores).
  static Map<String, String> encode({
    required WidgetCycleState state,
    required String profileId,
    required LocalDate asOf,
  }) {
    final payload = <String, String>{
      keyState: switch (state.kind) {
        WidgetCycleStateKind.noData => 'no_data',
        WidgetCycleStateKind.cycleDay => 'day',
        WidgetCycleStateKind.suppressed => 'suppressed',
        WidgetCycleStateKind.off => 'off',
      },
      keyCanQuickLog: state.canQuickLog ? '1' : '0',
      keyProfileId: profileId,
      keyAsOf: asOf.iso,
    };
    if (state.kind == WidgetCycleStateKind.cycleDay) {
      payload[keyCycleDay] = '${state.cycleDay}';
      final daysUntilNext = state.daysUntilNext;
      if (daysUntilNext != null) {
        payload[keyDaysUntilNext] = '$daysUntilNext';
      }
    }
    return payload;
  }
}
