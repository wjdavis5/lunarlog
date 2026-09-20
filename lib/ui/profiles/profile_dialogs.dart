/// Shared dialogs and validators for profile create/edit/archive (R2).
///
/// Copy is privacy-sensitive: fertility vocabulary is absent today (it
/// arrives with #143/#144), and the archive confirmation states explicitly
/// that data is retained (archive must not read as data loss while export
/// is deferred).
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:lunarlog/domain/limits.dart';
import 'package:lunarlog/domain/logging/day_entry_policy.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/models/profile_relationship.dart';
import 'package:lunarlog/domain/prediction/prediction.dart'
    show ActivePrediction;
import 'package:lunarlog/domain/prediction/prediction_service.dart'
    show CyclePredictionService;
import 'package:lunarlog/domain/pregnancy.dart'
    show estimatedDueDateFromLastPeriod;
import 'package:lunarlog/domain/repositories/profile_modes_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/components/destructive_button.dart';
import 'package:lunarlog/ui/components/responsive_body.dart';
import 'package:lunarlog/ui/l10n/dates.dart' as dates;
import 'package:lunarlog/ui/profiles/birth_control_choices.dart';
import 'package:lunarlog/ui/theme/tokens.dart';
import 'package:provider/provider.dart';

/// Shared profile-name validation: non-blank, and no longer than the
/// server accepts ([kMaxDisplayNameLength], mirrored from its CHECK).
String? validateProfileName(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Name cannot be empty';
  }
  if (value.trim().length > kMaxDisplayNameLength) {
    return 'Name is too long ($kMaxDisplayNameLength characters max)';
  }
  return null;
}

/// Inclusive bounds mirrored exactly from the server's
/// `profiles_birth_year_check` CHECK constraint (Issue #4 R1).
const int kMinBirthYear = 1900;
const int kMaxBirthYear = 2200;

/// Issue #861: the accepted value of a picked Postpartum birth date, or
/// null when it fails [DayEntryPolicy]'s shared date bounds — a date more
/// than a day in the future, or one whose year precedes the profile's known
/// birth year. The dialog's picker already bounds the future and the far
/// past; this reuses #848's one validator rather than writing a second one
/// (and is the seam its unit tests drive directly).
String? acceptedPostpartumBirthDate(
  LocalDate date, {
  required LocalDate today,
  int? birthYear,
}) =>
    DayEntryPolicy.validateDate(date, today: today, birthYear: birthYear)
            .isValid
        ? date.iso
        : null;

/// Shared birth-year validation: optional (an empty value always validates,
/// R2), otherwise an integer within [kMinBirthYear]-[kMaxBirthYear]
/// inclusive, matching the server's CHECK constraint exactly.
String? validateBirthYear(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  final parsed = int.tryParse(value.trim());
  if (parsed == null) {
    return 'Enter a valid year';
  }
  if (parsed < kMinBirthYear || parsed > kMaxBirthYear) {
    return 'Enter a year between $kMinBirthYear and $kMaxBirthYear';
  }
  return null;
}

class ProfileEditResult {
  const ProfileEditResult(
    this.displayName,
    this.isMinor, {
    this.mode = ProfileMode.standard,
    this.birthYear,
    this.relationship,
    this.lifecycleMode = LifecycleMode.tracking,
    this.birthControlChoice = BirthControlChoice.notAnswered,
    this.estimatedDueDate,
    this.postpartumBirthDate,
  });

  final String displayName;
  final bool isMinor;

  /// Care mode (Issue #131): presentation only — vocabulary, logging
  /// defaults, and reminder presets. Never a permission.
  final ProfileMode mode;

  /// Optional birth year of the profile subject (Issue #4 R1). Display and
  /// context only (R2).
  final int? birthYear;

  /// Optional closed-set relationship of the subject to the profile
  /// creator (R3).
  final ProfileRelationship? relationship;

  /// Life-stage mode (Issue #188's axis, collected by #216's onboarding
  /// and editable here — #216's "answers are editable later" AC). The
  /// default matches the lazy-row contract: absent means `tracking`.
  final LifecycleMode lifecycleMode;

  /// Birth-control method answer (Issue #216; free-text storage owned by
  /// #260's future vocabulary). `notAnswered` stores null.
  final BirthControlChoice birthControlChoice;

  /// Issue #192: the estimated due date (`yyyy-MM-dd`) collected when the
  /// life-stage answer is `pregnancy` — pre-filled with the derived
  /// estimate (last recorded period start + 280 days) when that start is
  /// known, manually overridable through a date picker, and null when it
  /// was neither derivable nor picked. Rides the recorder seam into
  /// `profile_modes.estimated_due_date`.
  final String? estimatedDueDate;

  /// Issue #861: the optional Postpartum-mode birth date (`yyyy-MM-dd`)
  /// collected when the life-stage answer is `postpartum` — manually
  /// picked, optional, and null when skipped. Rides the recorder seam into
  /// `profile_modes.postpartum_birth_date`; the day counter counts from it
  /// when present, and falls back to the mode-start surrogate when null.
  final String? postpartumBirthDate;
}

Future<ProfileEditResult?> showProfileEditDialog(
  BuildContext context, {
  Profile? existing,
}) {
  return showModalBottomSheet<ProfileEditResult>(
    context: context,
    isScrollControlled: true,
    routeSettings: const RouteSettings(name: kRouteProfileEditDialog),
    builder: (dialogContext) => _ProfileEditDialog(existing: existing),
  );
}

/// Sheet alias for [showProfileEditDialog] following the dialog/sheet rule (Issue #250).
Future<ProfileEditResult?> showProfileEditSheet(
  BuildContext context, {
  Profile? existing,
}) =>
    showProfileEditDialog(context, existing: existing);

class _ProfileEditDialog extends StatefulWidget {
  const _ProfileEditDialog({this.existing});

  final Profile? existing;

  @override
  State<_ProfileEditDialog> createState() => _ProfileEditDialogState();
}

class _ProfileEditDialogState extends State<_ProfileEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.displayName ?? '',
  );
  late bool _isMinor = widget.existing?.isMinor ?? false;
  late ProfileMode _mode = widget.existing?.mode ?? ProfileMode.standard;
  late final TextEditingController _birthYear = TextEditingController(
    text: widget.existing?.birthYear?.toString() ?? '',
  );
  late ProfileRelationship? _relationship = widget.existing?.relationship;

  /// #165: the dialog's two text fields' explicit focus chain — "next" on
  /// the name field advances to the birth-year field.
  final _nameFocus = FocusNode();
  final _birthYearFocus = FocusNode();

  /// The two #216 onboarding answers that are editable here (Issue #188
  /// storage). Loaded asynchronously from the profile's `profile_modes`
  /// row; until it resolves (or on a tree with no storage wired) the
  /// defaults render — `tracking` / not answered, exactly what an absent
  /// row means.
  LifecycleMode _lifecycleMode = LifecycleMode.tracking;
  BirthControlChoice _birthControl = BirthControlChoice.notAnswered;

  /// Issue #192: the pregnancy due-date answer. Null until the mode is
  /// switched to `pregnancy` (which derives the default — see
  /// [_onLifecycleModeChanged]) or a date is picked manually. `_dueDateDerived`
  /// tracks whether the shown value is the derived estimate (a fresh
  /// derivation) or something the user chose/edited.
  String? _estimatedDueDate;
  bool _dueDateDerived = false;
  bool _derivingDueDate = false;

  /// Issue #861: the Postpartum-mode birth-date answer. Null until a date is
  /// picked — the field is optional, and a blank value keeps the existing
  /// mode-start day-count surrogate rather than forcing a date into a flow
  /// that works without one.
  String? _postpartumBirthDate;

  @override
  void initState() {
    super.initState();
    // Issue #820: the "is this a minor" control flips between an editable
    // checkbox (no birth year) and a derived, read-only display (birth year
    // present) as the operator types, so the field needs to drive rebuilds.
    _birthYear.addListener(_onBirthYearChanged);
    unawaited(_loadProfileModeRow());
  }

  void _onBirthYearChanged() {
    if (mounted) setState(() {});
  }

  /// The parsed, in-range birth year currently in the field, or null when
  /// blank or not yet valid. Drives both the derived-minor display and the
  /// stored flag emitted on submit.
  int? get _parsedBirthYear {
    final text = _birthYear.text.trim();
    if (text.isEmpty) return null;
    final parsed = int.tryParse(text);
    if (parsed == null || parsed < kMinBirthYear || parsed > kMaxBirthYear) {
      return null;
    }
    return parsed;
  }

  /// Whether a birth year is present, in which case minor status is derived
  /// and the independent checkbox is replaced by a read-only display.
  bool get _hasBirthYear => _parsedBirthYear != null;

  Future<void> _loadProfileModeRow() async {
    final existing = widget.existing;
    if (existing == null) return;
    final repository =
        Provider.of<ProfileModesRepository?>(context, listen: false);
    if (repository == null) return;
    final row = await repository.find(existing.id);
    if (!mounted || row == null) return;
    setState(() {
      _lifecycleMode = row.mode;
      _birthControl = birthControlChoiceForStored(row.birthControlMethod);
      if (row.mode == LifecycleMode.pregnancy) {
        // An already-pregnant profile edits with its stored due date
        // pre-filled (not a fresh derivation — it is a chosen value).
        _estimatedDueDate = row.estimatedDueDate;
        _dueDateDerived = false;
      }
      if (row.mode == LifecycleMode.postpartum) {
        // An already-postpartum profile edits with its stored birth date
        // pre-filled, if one was supplied (Issue #861).
        _postpartumBirthDate = row.postpartumBirthDate;
      }
    });
  }

  /// Issue #192 AC1: switching the mode to `pregnancy` derives the
  /// estimated due date — last recorded period start + 280 days,
  /// Naegele's rule. The "last recorded period start" prefers the last
  /// logged episode start (the prediction service's
  /// `lastEpisodeStart`, the same derivation basis every estimate in the
  /// app uses) and falls back to the profile's stored onboarding fact;
  /// when neither exists the field stays empty for a manual pick. Runs
  /// once per entry into `pregnancy` (a re-edit keeps whatever is shown).
  Future<void> _onLifecycleModeChanged(LifecycleMode? value) async {
    final mode = value ?? LifecycleMode.tracking;
    final wasPregnancy = _lifecycleMode == LifecycleMode.pregnancy;
    setState(() => _lifecycleMode = mode);
    if (mode != LifecycleMode.pregnancy || wasPregnancy) return;
    setState(() => _derivingDueDate = true);
    final derived = await _deriveDueDate();
    if (!mounted) return;
    setState(() {
      _derivingDueDate = false;
      _estimatedDueDate = derived?.iso;
      _dueDateDerived = derived != null;
    });
  }

  /// The derived default: the last logged episode start when the
  /// prediction service can produce one, else the profile's stored
  /// `lastPeriodStart` fact, else null (manual pick only — the issue's
  /// "manual override when unknown/imported").
  Future<LocalDate?> _deriveDueDate() async {
    final existing = widget.existing;
    final service = Provider.of<CyclePredictionService?>(context,
        listen: false);
    if (existing != null && service != null) {
      try {
        final prediction = await service.current(existing.id);
        if (prediction is ActivePrediction) {
          return estimatedDueDateFromLastPeriod(prediction.lastEpisodeStart);
        }
      } on Exception {
        // Fall through to the stored fact — a derivation failure must not
        // block the mode switch.
      }
    }
    final fact = existing?.lastPeriodStart;
    if (fact != null) return estimatedDueDateFromLastPeriod(fact);
    return null;
  }

  /// Manual override: the date picker bound to the derived default.
  Future<void> _pickDueDate() async {
    final today = LocalDate.today();
    final initial = _estimatedDueDate == null
        ? null
        : DateTime.tryParse(_estimatedDueDate!);
    final picked = await showDatePicker(
      context: context,
      initialDate:
          initial ?? today.addDays(280 - 40).toDateTime(),
      firstDate: today.addMonths(-12).toDateTime(),
      lastDate: today.addMonths(24).toDateTime(),
      helpText: AppLocalizations.of(context).pregnancyDueDateLabel,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _estimatedDueDate = LocalDate.fromDateTime(picked).iso;
      _dueDateDerived = false;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _birthYear.dispose();
    _nameFocus.dispose();
    _birthYearFocus.dispose();
    super.dispose();
  }

  /// The Create/Save action, shared by the button and the birth-year
  /// field's "done" (#165): validate, then pop with the collected result.
  void _submit() {
    if (_formKey.currentState!.validate()) {
      final birthYear = _parsedBirthYear;
      Navigator.of(context).pop(
        ProfileEditResult(
          _name.text,
          // Issue #820: a present birth year is authoritative; the stored
          // flag is kept only as the fallback when no year is supplied.
          deriveMinorStatus(
            storedIsMinor: _isMinor,
            birthYear: birthYear,
            currentYear: DateTime.now().year,
          ),
          mode: _mode,
          birthYear: birthYear,
          relationship: _relationship,
          lifecycleMode: _lifecycleMode,
          birthControlChoice: _birthControl,
          estimatedDueDate: _lifecycleMode == LifecycleMode.pregnancy
              ? _estimatedDueDate
              : null,
          postpartumBirthDate: _lifecycleMode == LifecycleMode.postpartum
              ? _postpartumBirthDate
              : null,
        ),
      );
    }
  }

  /// Issue #820: the minor control. With no birth year it is the editable
  /// fallback checkbox (the pre-#820 behavior, preserving every existing
  /// profile's classification). The moment a valid birth year is present it
  /// becomes a read-only, derived display — the operator can no longer set
  /// a flag that disagrees with the age.
  Widget _minorControl(BuildContext context) {
    if (!_hasBirthYear) {
      return CheckboxListTile(
        key: const ValueKey('edit-minor-checkbox'),
        value: _isMinor,
        onChanged: (value) => setState(() => _isMinor = value ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        title: const Text('This profile is for a minor'),
      );
    }
    final isMinor = deriveMinorStatus(
      storedIsMinor: _isMinor,
      birthYear: _parsedBirthYear,
      currentYear: DateTime.now().year,
    );
    final theme = Theme.of(context);
    return ListTile(
      key: const ValueKey('edit-minor-derived'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        isMinor ? Icons.verified_user_outlined : Icons.person_outline,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(isMinor
          ? 'Counts as a minor (derived from birth year)'
          : 'Counts as an adult (derived from birth year)'),
    );
  }

  /// Issue #192: the estimated-due-date field shown only while the
  /// life-stage mode is Pregnancy — the derived value (or a manual pick,
  /// or an explicit empty state when nothing is derivable) plus the hint
  /// naming which of the three it is.
  Widget _dueDateField(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dueIso = _estimatedDueDate;
    final LocalDate? due = dueIso == null ? null : _tryParseIso(dueIso);
    final valueText = due == null
        ? (_derivingDueDate ? '…' : '—')
        : dates.formatLocalDateMonthDayYear(
            due,
            locale: dates.calendarLocale(context),
          );
    final hint = _dueDateDerived
        ? l10n.pregnancyDueDateDerivedHint
        : (dueIso == null ? l10n.pregnancyDueDateManualHint : null);
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: const ValueKey('edit-due-date-field'),
            onTap: _pickDueDate,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: l10n.pregnancyDueDateLabel,
              ),
              child: Text(
                valueText,
                key: const ValueKey('edit-due-date-value'),
              ),
            ),
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                hint,
                key: const ValueKey('edit-due-date-hint'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
        ],
      ),
    );
  }

  static LocalDate? _tryParseIso(String iso) {
    try {
      return LocalDate.fromIso(iso);
    } on ArgumentError {
      return null;
    }
  }

  /// Issue #861: the Postpartum birth-date field — optional, blank by
  /// default, opening a date picker on tap. The picker is bounded to the
  /// last 24 months (no future date, nothing absurdly far past), and the
  /// picked value is re-checked against the shared [DayEntryPolicy] bounds
  /// (#848) so a date before the profile's birth year is refused with an
  /// honest message rather than stored.
  Widget _postpartumBirthDateField(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final iso = _postpartumBirthDate;
    final LocalDate? birth = iso == null ? null : _tryParseIso(iso);
    final valueText = birth == null
        ? '—'
        : dates.formatLocalDateMonthDayYear(
            birth,
            locale: dates.calendarLocale(context),
          );
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: const ValueKey('edit-postpartum-birth-date-field'),
            onTap: _pickPostpartumBirthDate,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: l10n.postpartumBirthDateLabel,
              ),
              child: Text(
                valueText,
                key: const ValueKey('edit-postpartum-birth-date-value'),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.postpartumBirthDateHint,
              key: const ValueKey('edit-postpartum-birth-date-hint'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  /// Issue #861: picks the optional Postpartum birth date. Bounded to the
  /// last 24 months so the future and the absurdly far past are unreachable
  /// in the picker itself; the picked value is then passed through
  /// [acceptedPostpartumBirthDate] (the shared [DayEntryPolicy] bounds,
  /// #848) so a date before the profile's known birth year is refused too —
  /// an invalid pick leaves the shown value unchanged.
  Future<void> _pickPostpartumBirthDate() async {
    final today = LocalDate.today();
    final initial = _postpartumBirthDate == null
        ? null
        : DateTime.tryParse(_postpartumBirthDate!);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? today.toDateTime(),
      firstDate: today.addMonths(-24).toDateTime(),
      lastDate: today.toDateTime(),
      helpText: AppLocalizations.of(context).postpartumBirthDateLabel,
    );
    if (picked == null || !mounted) return;
    final accepted = acceptedPostpartumBirthDate(
      LocalDate.fromDateTime(picked),
      today: today,
      birthYear: widget.existing?.birthYear,
    );
    setState(() => _postpartumBirthDate = accepted ?? _postpartumBirthDate);
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final theme = Theme.of(context);
    return SafeArea(
      child: ResponsiveBody(
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              existing == null
                  ? 'Add profile'
                  : AppLocalizations.of(context).editProfileAction,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: LLSpace.space3),
            Flexible(
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: _name,
                        focusNode: _nameFocus,
                        autofocus: true,
                        decoration: const InputDecoration(labelText: 'Name'),
                        maxLength: kMaxDisplayNameLength,
                        maxLengthEnforcement: MaxLengthEnforcement.enforced,
                        validator: validateProfileName,
                        // #165: `name` is the honest hint; "next" moves to
                        // the birth-year field below.
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) => _birthYearFocus.requestFocus(),
                        autofillHints: const [AutofillHints.name],
                      ),
                      _minorControl(context),
                      const SizedBox(height: LLSpace.space3),
                      // #557: MergeSemantics folds the label into the dropdown's
                      // own announcement, so a screen reader hears "Care mode,
                      // <value>" instead of just the bare value.
                      MergeSemantics(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Care mode',
                                key: const ValueKey('care-mode-label'),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            DropdownButton<ProfileMode>(
                              key: const ValueKey('care-mode-dropdown'),
                              value: _mode,
                              isExpanded: true,
                              onChanged: (value) => setState(
                                  () => _mode = value ?? ProfileMode.standard),
                              items: [
                                for (final mode in ProfileMode.values)
                                  DropdownMenuItem<ProfileMode>(
                                    value: mode,
                                    child: Text(mode.label),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 8),
                        child: Text(
                          _mode.hint,
                          key: const ValueKey('care-mode-hint'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ),
                      TextFormField(
                        key: const ValueKey('edit-birth-year-field'),
                        controller: _birthYear,
                        focusNode: _birthYearFocus,
                        keyboardType: TextInputType.number,
                        // #165: the dialog's last text field — "done" is
                        // the Create/Save action.
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(
                          labelText: 'Birth year (optional)',
                        ),
                        validator: validateBirthYear,
                      ),
                      const SizedBox(height: LLSpace.space3),
                      MergeSemantics(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Relationship',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            DropdownButton<ProfileRelationship?>(
                              value: _relationship,
                              isExpanded: true,
                              onChanged: (value) =>
                                  setState(() => _relationship = value),
                              items: [
                                const DropdownMenuItem<ProfileRelationship?>(
                                  child: Text('None'),
                                ),
                                for (final relationship in ProfileRelationship.values)
                                  DropdownMenuItem<ProfileRelationship?>(
                                    value: relationship,
                                    child: Text(relationship.label),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: LLSpace.space3),
                      MergeSemantics(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                AppLocalizations.of(context).lifeStageModeLabel,
                                key: const ValueKey('edit-lifecycle-label'),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            DropdownButton<LifecycleMode>(
                              key: const ValueKey('edit-lifecycle-dropdown'),
                              value: _lifecycleMode,
                              isExpanded: true,
                              onChanged: _onLifecycleModeChanged,
                              items: [
                                for (final mode in LifecycleMode.values)
                                  DropdownMenuItem<LifecycleMode>(
                                    value: mode,
                                    child: Text(mode.label),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Issue #192 AC1: entering Pregnancy mode collects (or
                      // derives) an estimated due date. The field appears
                      // only for that mode, pre-filled with the derived
                      // estimate when the last recorded period start is
                      // known; tapping it opens a date picker for a manual
                      // override.
                      if (_lifecycleMode == LifecycleMode.pregnancy) ...[
                        const SizedBox(height: LLSpace.space2),
                        _dueDateField(context),
                      ],
                      // Issue #861: entering Postpartum mode optionally
                      // collects the birth date the day counter runs from.
                      // Blank keeps the existing mode-start surrogate.
                      if (_lifecycleMode == LifecycleMode.postpartum) ...[
                        const SizedBox(height: LLSpace.space2),
                        _postpartumBirthDateField(context),
                      ],
                      const SizedBox(height: LLSpace.space3),
                      MergeSemantics(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                AppLocalizations.of(context)
                                    .firstRunCycleBirthControlLabel,
                                key: const ValueKey('edit-birth-control-label'),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            DropdownButton<BirthControlChoice>(
                              key: const ValueKey('edit-birth-control-dropdown'),
                              value: _birthControl,
                              isExpanded: true,
                              onChanged: (value) => setState(() => _birthControl =
                                  value ?? BirthControlChoice.notAnswered),
                              items: [
                                for (final choice in BirthControlChoice.values)
                                  DropdownMenuItem<BirthControlChoice>(
                                    value: choice,
                                    child: Text(birthControlChoiceLabel(
                                        choice, AppLocalizations.of(context))),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: LLSpace.space3),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: LLSpace.space2,
              overflowSpacing: LLSpace.space2,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: _submit,
                  child: Text(existing == null ? 'Create' : 'Save'),
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }
}

Future<bool> confirmArchiveProfile(
  BuildContext context,
  Profile profile,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    routeSettings: const RouteSettings(name: kRouteProfileArchiveDialog),
    builder: (dialogContext) => AlertDialog(
      title: Text('Archive ${profile.displayName}?'),
      content: const SingleChildScrollView(
        child: Text(
          'The profile moves to the archived list and out of everyday use. '
          'Its history stays on this device and can be restored at any time.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        DestructiveButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Archive'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
