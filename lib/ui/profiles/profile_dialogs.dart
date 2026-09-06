/// Shared dialogs and validators for profile create/edit/archive (R2).
///
/// Copy is privacy-sensitive by house rule: no fertility vocabulary, and the
/// archive confirmation states explicitly that data is retained (archive
/// must not read as data loss while export is deferred).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:lunarlog/domain/limits.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_relationship.dart';

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
    this.birthYear,
    this.relationship,
  });

  final String displayName;
  final bool isMinor;

  /// Optional birth year of the profile subject (Issue #4 R1). Display and
  /// context only (R2).
  final int? birthYear;

  /// Optional closed-set relationship of the subject to the profile
  /// creator (R3).
  final ProfileRelationship? relationship;
}

Future<ProfileEditResult?> showProfileEditDialog(
  BuildContext context, {
  Profile? existing,
}) {
  return showDialog<ProfileEditResult>(
    context: context,
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
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.displayName ?? '');
  late bool _isMinor = widget.existing?.isMinor ?? false;
  late final TextEditingController _birthYear = TextEditingController(
      text: widget.existing?.birthYear?.toString() ?? '');
  late ProfileRelationship? _relationship = widget.existing?.relationship;

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
      content: Form(
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
            TextFormField(
              controller: _birthYear,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Birth year (optional)'),
              validator: validateBirthYear,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Relationship', style: Theme.of(context).textTheme.bodySmall),
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
          ],
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
              Navigator.of(context).pop(ProfileEditResult(
                _name.text,
                _isMinor,
                birthYear: trimmedBirthYear.isEmpty
                    ? null
                    : int.tryParse(trimmedBirthYear),
                relationship: _relationship,
              ));
            }
          },
          child: Text(existing == null ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}

Future<bool> confirmArchiveProfile(BuildContext context, Profile profile) async {
  final confirmed = await showDialog<bool>(
    context: context,
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
