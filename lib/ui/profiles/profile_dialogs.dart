/// Shared dialogs and validators for profile create/edit/archive (R2).
///
/// Copy is privacy-sensitive: fertility vocabulary is absent today (it
/// arrives with #143/#144), and the archive confirmation states explicitly
/// that data is retained (archive must not read as data loss while export
/// is deferred).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/domain/limits.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/models/profile_relationship.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/profiles/birth_control_choices.dart';
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
}

Future<ProfileEditResult?> showProfileEditDialog(
  BuildContext context, {
  Profile? existing,
}) {
  return showDialog<ProfileEditResult>(
    context: context,
    routeSettings: const RouteSettings(name: kRouteProfileEditDialog),
    builder: (dialogContext) => _ProfileEditDialog(existing: existing),
  );
}

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

  /// The two #216 onboarding answers that are editable here (Issue #188
  /// storage). Loaded asynchronously from the profile's `profile_modes`
  /// row; until it resolves (or on a tree with no storage wired) the
  /// defaults render — `tracking` / not answered, exactly what an absent
  /// row means.
  LifecycleMode _lifecycleMode = LifecycleMode.tracking;
  BirthControlChoice _birthControl = BirthControlChoice.notAnswered;

  @override
  void initState() {
    super.initState();
    _loadProfileModeRow();
  }

  Future<void> _loadProfileModeRow() async {
    final existing = widget.existing;
    if (existing == null) return;
    final storage = Provider.of<LunarLogStorage?>(context, listen: false);
    if (storage == null) return;
    final row = await storage.getProfileMode(existing.id);
    if (!mounted || row == null) return;
    setState(() {
      _lifecycleMode = LifecycleMode.fromDb(row.mode);
      _birthControl = birthControlChoiceForStored(
          row.birthControlMethod, AppLocalizations.of(context));
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _birthYear.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    return AlertDialog(
      title: Text(existing == null ? 'Add profile' : 'Rename profile'),
      // The mode picker plus its hint line make the form taller than a
      // small viewport's dialog inset; scroll rather than overflow.
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
                maxLength: kMaxDisplayNameLength,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                validator: validateProfileName,
              ),
              CheckboxListTile(
                value: _isMinor,
                onChanged: (value) => setState(() => _isMinor = value ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text('This profile is for a minor'),
              ),
              const SizedBox(height: 12),
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
                onChanged: (value) =>
                    setState(() => _mode = value ?? ProfileMode.standard),
                items: [
                  for (final mode in ProfileMode.values)
                    DropdownMenuItem<ProfileMode>(
                      value: mode,
                      child: Text(mode.label),
                    ),
                ],
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
                controller: _birthYear,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Birth year (optional)',
                ),
                validator: validateBirthYear,
              ),
              const SizedBox(height: 12),
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
                onChanged: (value) => setState(() => _relationship = value),
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
              const SizedBox(height: 12),
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
                onChanged: (value) => setState(
                    () => _lifecycleMode = value ?? LifecycleMode.tracking),
                items: [
                  for (final mode in LifecycleMode.values)
                    DropdownMenuItem<LifecycleMode>(
                      value: mode,
                      child: Text(mode.label),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  AppLocalizations.of(context).firstRunCycleBirthControlLabel,
                  key: const ValueKey('edit-birth-control-label'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              DropdownButton<BirthControlChoice>(
                key: const ValueKey('edit-birth-control-dropdown'),
                value: _birthControl,
                isExpanded: true,
                onChanged: (value) => setState(() =>
                    _birthControl = value ?? BirthControlChoice.notAnswered),
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final trimmedBirthYear = _birthYear.text.trim();
              Navigator.of(context).pop(
                ProfileEditResult(
                  _name.text,
                  _isMinor,
                  mode: _mode,
                  birthYear: trimmedBirthYear.isEmpty
                      ? null
                      : int.tryParse(trimmedBirthYear),
                  relationship: _relationship,
                  lifecycleMode: _lifecycleMode,
                  birthControlChoice: _birthControl,
                ),
              );
            }
          },
          child: Text(existing == null ? 'Create' : 'Save'),
        ),
      ],
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
      content: const Text(
        'The profile moves to the archived list and out of everyday use. '
        'Its history stays on this device and can be restored at any time.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Archive'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
