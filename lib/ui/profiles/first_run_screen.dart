/// First-run flow (F1): with zero profiles the gate forces profile creation
/// before anything else — no skip. A one-time-per-install key-loss notice
/// precedes the name form (persisted via [SettingsKeys.firstRunNoticeShown]).
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/profiles/profile_dialogs.dart';
import 'package:provider/provider.dart';

class FirstRunScreen extends StatefulWidget {
  const FirstRunScreen({super.key});

  @override
  State<FirstRunScreen> createState() => _FirstRunScreenState();
}

class _FirstRunScreenState extends State<FirstRunScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _noticePending = true;
  bool _isMinor = false;

  @override
  void initState() {
    super.initState();
    _noticePending = !context.read<ProfileController>().firstRunNoticeShown;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _acknowledgeNotice() async {
    final controller = context.read<ProfileController>();
    await controller.markFirstRunNoticeShown();
    if (mounted) {
      setState(() => _noticePending = false);
    }
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    final controller = context.read<ProfileController>();
    await controller.createProfile(
      displayName: _nameController.text,
      isMinor: _isMinor,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_noticePending) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Data lives only on this device. If the device is lost or '
                  'reset, the history cannot be recovered — there is no '
                  'backup in v1.',
                  style: TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _acknowledgeNotice,
                  child: const Text('I understand'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Create a profile')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: validateProfileName,
              ),
              CheckboxListTile(
                value: _isMinor,
                onChanged: (value) =>
                    setState(() => _isMinor = value ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text('This profile is for a minor'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _create,
                child: const Text('Create profile'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
