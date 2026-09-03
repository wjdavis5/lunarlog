/// Settings screen: the inactivity auto-relock toggle (default on, fixed
/// 2-minute timeout, persisted via [SettingsKeys.relockEnabled];
/// backgrounding always re-locks regardless) and, when the build provides
/// an [AuthController], the Account section (U6). Reachable from the
/// profile picker.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/ui/account/account_section.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
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
    final hasAccount = Provider.of<AuthController?>(context) != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          if (hasAccount) ...[
            const AccountSection(),
            const Divider(),
          ],
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
          const Divider(),
          ListTile(
            key: const ValueKey('privacy-policy-tile'),
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Privacy policy'),
            subtitle: const Text('Local-first, encrypted, zero tracking'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showPrivacyPolicy(context),
          ),
        ],
      ),
    );
  }

  void _showPrivacyPolicy(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('LunarLog Privacy Policy'),
        content: const SingleChildScrollView(
          child: Text(
            'LunarLog is a privacy-first, local-first cycle tracker.\n\n'
            '• Local & Encrypted: All cycle data is encrypted on your device '
            'behind biometric authentication.\n'
            '• Optional Sync: Cloud accounts (Supabase) are optional. No data is '
            'uploaded without your explicit consent.\n'
            '• Zero Ads & Tracking: We do not track you, sell data, or use ads.\n'
            '• Privacy-Scrubbed Telemetry: Crash reports (Sentry) strip all health '
            'and personal details on-device.\n'
            '• Family Custodianship: Minor profiles are managed directly by adult '
            'guardians with identical privacy protections.\n\n'
            'Canonical policy: https://github.com/wjdavis5/lunarlog/blob/main/PRIVACY.md',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
