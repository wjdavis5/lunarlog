/// Settings screen (U7 v1): exactly one control — the inactivity
/// auto-relock toggle (default on, fixed 2-minute timeout), persisted via
/// [SettingsKeys.relockEnabled]. Backgrounding always re-locks regardless
/// of this toggle. Reachable from the profile picker.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:provider/provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _relock = true;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    final store = context.read<SettingsStore>();
    () async {
      final value = await store.get(SettingsKeys.relockEnabled);
      if (!mounted) return;
      setState(() {
        _relock = value != 'false';
        _loaded = true;
      });
    }();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            key: const ValueKey('relock-toggle'),
            title: const Text('Relock after inactivity'),
            subtitle: const Text(
              'Locks the app after 2 minutes without input. '
              'Backgrounding always relocks.',
            ),
            value: _relock,
            onChanged: _loaded
                ? (value) {
                    setState(() => _relock = value);
                    context
                        .read<SettingsStore>()
                        .set(SettingsKeys.relockEnabled, value ? 'true' : 'false');
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
