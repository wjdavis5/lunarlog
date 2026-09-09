/// UI-local closed list for the birth-control-method selector (Issue
/// #216's cycle questions, reused by the profile edit dialog for AC
/// editability).
///
/// Deliberately *not* a domain enum and deliberately stored as free
/// text: the server column is `profile_modes.birth_control_method`
/// (free text bounded by `kMaxBirthControlMethodLength`), and #260 owns
/// the canonical tracked-method vocabulary — this list only feeds the
/// onboarding/edit selector until that lands. Labels are localized in
/// the ARB (`birthControl*`), so the list needs the resolved
/// [AppLocalizations] to render or to map a stored value back to a
/// choice.
library;

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

/// What [choice] persists into `birth_control_method`: the localized
/// label, or null for the not-answered state.
String? birthControlStoredValue(
        BirthControlChoice choice, AppLocalizations l10n) =>
    choice == BirthControlChoice.notAnswered
        ? null
        : birthControlChoiceLabel(choice, l10n);

/// Reverse mapping for loading a stored value back into the selector.
/// A value this build's list does not produce (e.g. written by a future
/// #260 vocabulary) degrades to [BirthControlChoice.notAnswered] rather
/// than crashing — the dropdown never lies about selecting it, and #260
/// owns the surface that will represent it properly.
BirthControlChoice birthControlChoiceForStored(
    String? stored, AppLocalizations l10n) {
  if (stored == null) return BirthControlChoice.notAnswered;
  final labels = birthControlChoiceLabels(l10n);
  for (final entry in labels.entries) {
    if (entry.key != BirthControlChoice.notAnswered &&
        entry.value == stored) {
      return entry.key;
    }
  }
  return BirthControlChoice.notAnswered;
}
