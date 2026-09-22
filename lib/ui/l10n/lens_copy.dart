/// Lens-aware ARB copy (Issue #850, U8).
///
/// `docs/product/voice-and-copy.md` rule 2: "You" is whoever is looking at
/// the screen, and the person whose cycle is logged is named or referred to
/// in the third person. Most strings already satisfy that tuple, but the
/// handful below were written subject-first ("your cycle estimate") and are
/// reachable by a guardian. Each mapper returns the base ARB string
/// byte-for-byte under [GuardianLens.subject], so a subject's view is
/// unchanged, and the `…Guardian` variant only under [GuardianLens.guardian].
///
/// The variants deliberately say "this profile" rather than the subject's
/// first name: they cover surfaces (stream-error messages, the shared
/// predictions-off and comparison empty states, the day sheet's early-cycle
/// dialog) whose call sites do not all carry a display name, and "the
/// profile" is the glossary's own word for the logged person's record.
///
/// Select the lens with `guardianLensFor` at the call site — exactly the
/// lens the surrounding surface already resolves — so the copy can never
/// disagree with which front page is rendered.
library;

import 'package:lunarlog/domain/sharing/guardian_lens.dart';
import 'package:lunarlog/l10n/app_localizations.dart';

/// The Overview panel's `AsyncSnapshotView` error message.
String lensOverviewEstimateLoadError(
  AppLocalizations l10n,
  GuardianLens lens,
) =>
    lens == GuardianLens.guardian
        ? l10n.overviewEstimateLoadErrorGuardian
        : l10n.overviewEstimateLoadError;

/// The Analysis tab's `AsyncSnapshotView` error message.
String lensAnalysisLoadError(AppLocalizations l10n, GuardianLens lens) =>
    lens == GuardianLens.guardian
        ? l10n.analysisLoadErrorGuardian
        : l10n.analysisLoadError;

/// The shared `PredictionsDisabledCard` body.
String lensPredictionsDisabledBody(AppLocalizations l10n, GuardianLens lens) =>
    lens == GuardianLens.guardian
        ? l10n.predictionsDisabledBodyGuardian
        : l10n.predictionsDisabledBody;

/// The cycle-comparison screen's "nothing to compare" empty-state body.
String lensCycleComparisonNotEnoughBody(
  AppLocalizations l10n,
  GuardianLens lens,
) =>
    lens == GuardianLens.guardian
        ? l10n.cycleComparisonNotEnoughBodyGuardian
        : l10n.cycleComparisonNotEnoughBody;

/// The day sheet's early-cycle-start confirmation body.
String lensDaySheetCycleStartDialogBody(
  AppLocalizations l10n,
  GuardianLens lens,
  int cycleDay,
  String flow,
  int cycleLength,
) =>
    lens == GuardianLens.guardian
        ? l10n.daySheetCycleStartDialogBodyGuardian(cycleDay, flow, cycleLength)
        : l10n.daySheetCycleStartDialogBody(cycleDay, flow, cycleLength);
