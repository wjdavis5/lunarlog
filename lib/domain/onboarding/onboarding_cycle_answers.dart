/// Domain seam for the onboarding cycle questions (Issue #216, U3).
///
/// Issue #216 is UI-scoped by its own assumption ("Cycle questions are
/// scoped as UI-only in this issue; the domain meaning ... belongs to
/// #218"), so this model deliberately carries **all five** answers while
/// the shipped recorder persists only the two that have landed storage
/// (Issue #188's `profile_modes`: the life-stage mode and the
/// birth-control method). The remaining three — last period start date
/// and the two typical lengths — ride on this seam for #218 (provisional
/// prediction seeding, blocked on #213) to consume without a second
/// onboarding pass, exactly as #218's own acceptance criteria expect
/// ("captured and persisted ... must not throw the answers away" is
/// #218's cross-referenced obligation once its storage design lands).
///
/// Pure Dart with no drift/Flutter imports (R14/R16) —
/// `test/architecture/layering_test.dart` enforces that.
library;

import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/local_date.dart';

/// Inclusive sanity bounds for the two numeric onboarding questions.
/// Advisory-only today (the answers are seam-carried until #218), but
/// they keep garbage out of any future consumer, and the UI mirrors
/// them in its validators and error copy.
const int kMinTypicalCycleLengthDays = 10;
const int kMaxTypicalCycleLengthDays = 90;
const int kMinTypicalPeriodLengthDays = 1;
const int kMaxTypicalPeriodLengthDays = 14;

/// The five onboarding cycle answers (Issue #216's table), each
/// individually skippable — every field is nullable/optional except the
/// goal, whose "unanswered" state is the neutral default
/// [LifecycleMode.tracking] (matching `profile_modes`' lazy-row
/// contract: an absent row means `tracking`).
class OnboardingCycleAnswers {
  const OnboardingCycleAnswers({
    this.lastPeriodStart,
    this.typicalCycleLengthDays,
    this.typicalPeriodLengthDays,
    this.birthControlMethod,
    this.lifecycleMode = LifecycleMode.tracking,
  });

  /// Civil date the last period started on, or null when skipped.
  final LocalDate? lastPeriodStart;

  /// Typical cycle length in days, or null when skipped.
  final int? typicalCycleLengthDays;

  /// Typical period length in days, or null when skipped.
  final int? typicalPeriodLengthDays;

  /// Free-text birth-control method label (see
  /// `lib/ui/profiles/birth_control_choices.dart` for the UI selector's
  /// closed list; #260 owns the canonical tracked-method vocabulary),
  /// or null when skipped / "Not answered".
  final String? birthControlMethod;

  /// Life-stage goal/mode answer (Issue #188's axis — the Clue-style
  /// goal question; #131's care-mode axis is collected separately on
  /// the name form and the two are never merged).
  final LifecycleMode lifecycleMode;

  /// Whether [record] has anything at all to persist: a non-default
  /// life-stage mode or a birth-control answer. With everything
  /// skipped/default this is false and the recorder must not create a
  /// `profile_modes` row (the server's lazy-default contract).
  bool get hasPersistableAnswers =>
      lifecycleMode != LifecycleMode.tracking || birthControlMethod != null;
}

/// The seam #216 leaves for #218: the first-run flow (and the profile
/// edit dialog, for the two editable answers) hands the whole answer
/// set to a recorder. The drift implementation
/// (`lib/data/repositories/drift_onboarding_cycle_answers_recorder.dart`)
/// persists what has landed storage; #218 extends or replaces it to
/// seed provisional predictions without touching the UI again.
abstract class OnboardingCycleAnswersRecorder {
  Future<void> record(String profileId, OnboardingCycleAnswers answers);
}
