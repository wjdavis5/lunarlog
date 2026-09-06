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
import 'package:lunarlog/observability/route_names.dart';

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

class ProfileEditResult {
  const ProfileEditResult(this.displayName, this.isMinor);

  final String displayName;
  final bool isMinor;
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
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.displayName ?? '');
  late bool _isMinor = widget.existing?.isMinor ?? false;

  @override
  void dispose() {
    _name.dispose();
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
              Navigator.of(context)
                  .pop(ProfileEditResult(_name.text, _isMinor));
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
