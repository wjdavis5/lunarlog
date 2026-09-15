/// Settings entry point for the optional in-app PIN (issue #271
/// acceptance criterion: "A settings option lets a user enable an
/// app-specific PIN"). Self-hiding when no [GateController] with
/// [GateController.pinAvailable] is provided, so `SettingsScreen`'s own
/// diff for this feature is a single tile insertion.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/gate_controller.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/gate/pin_settings_screen.dart';
import 'package:provider/provider.dart';

class PinSettingsTile extends StatefulWidget {
  const PinSettingsTile({super.key});

  @override
  State<PinSettingsTile> createState() => _PinSettingsTileState();
}

class _PinSettingsTileState extends State<PinSettingsTile> {
  @override
  Widget build(BuildContext context) {
    final gate = context.watch<GateController?>();
    if (gate == null || !gate.pinAvailable) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<bool>(
      future: gate.isPinSet(),
      builder: (context, snapshot) {
        final hasPin = snapshot.data ?? false;
        return ListTile(
          key: const ValueKey('pin-settings-tile'),
          leading: const Icon(Icons.pin_outlined),
          title: Text(l10n.pinSettingsToggleTitle),
          subtitle: Text(hasPin
              ? l10n.pinSettingsToggleSubtitleOn
              : l10n.pinSettingsToggleSubtitleOff),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              settings: const RouteSettings(name: kRoutePinSettingsScreen),
              builder: (_) => PinSettingsScreen(gate: gate),
            ),
          ),
        );
      },
    );
  }
}
