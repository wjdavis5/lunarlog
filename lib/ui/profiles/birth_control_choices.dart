/// UI-local closed list for the birth-control-method selector (Issue
/// #216's cycle questions, reused by the profile edit dialog for AC
/// editability).
///
/// Since Issue #260 the canonical vocabulary lives in the domain
/// (`lib/domain/birth_control.dart`'s [BirthControlMethod]); the selector
/// stores those canonical ids into
/// `profile_modes.birth_control_method` and parses stored values back
/// through [BirthControlMethod.fromDb]'s total read (so labels written by
/// the pre-#260 builds keep loading). This list remains the *picker
/// order*, richer than the six tracked methods: the IUD question
/// distinguishes hormonal vs copper, which the six-method tracking model
/// deliberately does not.
library;

import 'package:lunarlog/domain/birth_control.dart';
import 'package:lunarlog/l10n/app_localizations.dart';

/// The selector's options. [notAnswered] is the "skipped" state and
/// stores nothing (null).
enum BirthControlChoice {
  notAnswered,
  none,
  pill,
  hormonalIud,
  copperIud,
  implant,
  injection,
  ring,
  patch,
  condom,
  other,
}

/// Localized label for each choice. A map (not a switch) keeps the
/// per-choice complexity out of the CRAP gate's reach — one literal per
/// option, exercised exhaustively by the direct unit test.
Map<BirthControlChoice, String> birthControlChoiceLabels(
        AppLocalizations l10n) =>
    {
      BirthControlChoice.notAnswered: l10n.birthControlNotAnswered,
      BirthControlChoice.none: l10n.birthControlNone,
      BirthControlChoice.pill: l10n.birthControlPill,
      BirthControlChoice.hormonalIud: l10n.birthControlHormonalIud,
      BirthControlChoice.copperIud: l10n.birthControlCopperIud,
      BirthControlChoice.implant: l10n.birthControlImplant,
      BirthControlChoice.injection: l10n.birthControlInjection,
      BirthControlChoice.ring: l10n.birthControlRing,
      BirthControlChoice.patch: l10n.birthControlPatch,
      BirthControlChoice.condom: l10n.birthControlCondom,
      BirthControlChoice.other: l10n.birthControlOther,
    };

/// Localized label for the dropdown item.
String birthControlChoiceLabel(
        BirthControlChoice choice, AppLocalizations l10n) =>
    birthControlChoiceLabels(l10n)[choice]!;

/// What [choice] persists into `birth_control_method`: the canonical
/// #260 id ([BirthControlMethod.toDb]), or null for the not-answered
/// state. Before Issue #260 this returned the localized label — legacy
/// rows keep parsing via [BirthControlMethod.fromDb]'s legacy table.
String? birthControlStoredValue(BirthControlChoice choice) {
  final method = _choiceToMethod[choice];
  if (method == null) return null; // notAnswered stores nothing.
  return method.toDb();
}

/// Reverse mapping for loading a stored value back into the selector.
/// Parsing goes through [BirthControlMethod.fromDb]'s total read
/// (canonical ids, pre-#260 labels, legacy ids); a value that still does
/// not map onto a choice this build offers degrades to
/// [BirthControlChoice.notAnswered] rather than crashing — the dropdown
/// never lies about selecting it.
BirthControlChoice birthControlChoiceForStored(String? stored) {
  final method = BirthControlMethod.fromDb(stored);
  return _methodToChoice[method] ?? BirthControlChoice.notAnswered;
}

/// Selector choice -> canonical method. Both IUD flavors and every
/// non-tracked answer keep their own member so a stored answer never
/// degrades on reload.
const Map<BirthControlChoice, BirthControlMethod?> _choiceToMethod = {
  BirthControlChoice.notAnswered: null,
  BirthControlChoice.none: BirthControlMethod.none,
  BirthControlChoice.pill: BirthControlMethod.pill,
  BirthControlChoice.hormonalIud: BirthControlMethod.hormonalIud,
  BirthControlChoice.copperIud: BirthControlMethod.copperIud,
  BirthControlChoice.implant: BirthControlMethod.implant,
  BirthControlChoice.injection: BirthControlMethod.shot,
  BirthControlChoice.ring: BirthControlMethod.ring,
  BirthControlChoice.patch: BirthControlMethod.patch,
  BirthControlChoice.condom: BirthControlMethod.condom,
  BirthControlChoice.other: BirthControlMethod.other,
};

/// Canonical method -> the selector choice that represents it. The two
/// IUD flavors map to their own choices; [BirthControlMethod.unknown] has
/// none (the dropdown cannot offer an option it cannot name).
const Map<BirthControlMethod?, BirthControlChoice> _methodToChoice = {
  null: BirthControlChoice.notAnswered,
  BirthControlMethod.none: BirthControlChoice.none,
  BirthControlMethod.pill: BirthControlChoice.pill,
  BirthControlMethod.hormonalIud: BirthControlChoice.hormonalIud,
  BirthControlMethod.copperIud: BirthControlChoice.copperIud,
  BirthControlMethod.implant: BirthControlChoice.implant,
  BirthControlMethod.shot: BirthControlChoice.injection,
  BirthControlMethod.ring: BirthControlChoice.ring,
  BirthControlMethod.patch: BirthControlChoice.patch,
  BirthControlMethod.condom: BirthControlChoice.condom,
  BirthControlMethod.other: BirthControlChoice.other,
};
