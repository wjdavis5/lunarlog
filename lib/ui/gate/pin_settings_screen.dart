/// "App PIN" settings screen (issue #271): status, set/change, and turn
/// off. Pushed from `SettingsScreen`'s "App PIN" tile whenever
/// [GateController.pinAvailable] is true (i.e. a [PinCredentialService] was
/// configured — every native build today, see `main.dart`).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lunarlog/gate_controller.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/gate/pin_authorization_dialog.dart';
import 'package:lunarlog/ui/gate/pin_entry_form_screen.dart';

class PinSettingsScreen extends StatefulWidget {
  const PinSettingsScreen({super.key, required this.gate});

  final GateController gate;

  @override
  State<PinSettingsScreen> createState() => _PinSettingsScreenState();
}

class _PinSettingsScreenState extends State<PinSettingsScreen> {
  bool? _hasPin;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final hasPin = await widget.gate.isPinSet();
    if (mounted) setState(() => _hasPin = hasPin);
  }

  Future<void> _create() async {
    final pin = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        settings: const RouteSettings(name: kRoutePinSetScreen),
        builder: (_) =>
            const PinEntryFormScreen(mode: PinEntryFormMode.create),
      ),
    );
    if (pin == null) return;
    await widget.gate.setPin(pin);
    if (mounted) setState(() => _hasPin = true);
  }

  /// #271: "changing ... requires the current PIN or device auth" —
  /// [showPinAuthorizationDialog] is that gate, run before either the
  /// change form or the turn-off confirmation below.
  Future<void> _change() async {
    final authorized = await showPinAuthorizationDialog(context, widget.gate);
    if (!authorized || !mounted) return;
    final pin = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        settings: const RouteSettings(name: kRoutePinChangeScreen),
        builder: (_) =>
            const PinEntryFormScreen(mode: PinEntryFormMode.change),
      ),
    );
    if (pin == null) return;
    await widget.gate.setPin(pin);
  }

  Future<void> _turnOff() async {
    final authorized = await showPinAuthorizationDialog(context, widget.gate);
    if (!authorized || !mounted) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      routeSettings: const RouteSettings(name: kRoutePinRemoveConfirmDialog),
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.pinRemoveConfirmTitle),
        content: Text(l10n.pinRemoveConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('pin-remove-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.pinRemoveConfirmButton),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.gate.clearPin();
    if (mounted) setState(() => _hasPin = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasPin = _hasPin;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.pinSettingsSectionTitle)),
      body: hasPin == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(children: _tiles(l10n, hasPin)),
    );
  }

  List<Widget> _tiles(AppLocalizations l10n, bool hasPin) => hasPin
      ? [
          ListTile(
            key: const ValueKey('pin-change-tile'),
            leading: const Icon(Icons.pin_outlined),
            title: Text(l10n.pinChangeScreenTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: _change,
          ),
          ListTile(
            key: const ValueKey('pin-remove-tile'),
            leading: const Icon(Icons.lock_open_outlined),
            title: Text(l10n.pinRemoveConfirmButton),
            onTap: _turnOff,
          ),
        ]
      : [
          ListTile(
            key: const ValueKey('pin-create-tile'),
            leading: const Icon(Icons.pin_outlined),
            title: Text(l10n.pinSetScreenTitle),
            subtitle: Text(l10n.pinSettingsToggleSubtitleOff),
            trailing: const Icon(Icons.chevron_right),
            onTap: _create,
          ),
        ];
}
