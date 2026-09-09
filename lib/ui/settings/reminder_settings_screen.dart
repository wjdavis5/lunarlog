/// The per-profile local reminder configuration screen (Issue #136, R10,
/// R11): one enable toggle, lead-days, and time-of-day per reminder type,
/// plus an optional daily quiet-hours window — all device-local
/// (`ReminderConfigService`), all taking effect at the coordinator's next
/// replan. Reached from Settings' "Reminders" tile.
///
/// The profile picker at the top is what makes the configuration
/// per-profile (the issue's routing requirement): each active profile
/// holds its own schedule, defaulting to its care-mode preset until first
/// edited. Lock-screen copy is deliberately *not* configurable here
/// (KTD7) — only scheduling is.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/notifications/notification_preferences.dart'
    show QuietHours;
import 'package:lunarlog/domain/notifications/reminder_config.dart';
import 'package:lunarlog/domain/notifications/reminder_config_store.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:provider/provider.dart';

/// The screen's time-prompt seam: the Material picker in production, a
/// stub in tests.
typedef ReminderTimePicker = Future<TimeOfDay?> Function(
  BuildContext context,
  TimeOfDay initialTime,
);

Future<TimeOfDay?> _defaultTimePicker(
  BuildContext context,
  TimeOfDay initialTime,
) =>
    showTimePicker(context: context, initialTime: initialTime);

/// The lead-days choices the screen offers (the planner clamps to the
/// same bounds; the UI simply never offers out-of-range values).
const List<int> kLeadDayChoices = [0, 1, 2, 3, 4, 5, 6, 7];

/// The quiet-hours window a first-time toggle arms (22:00-07:00).
const QuietHours kDefaultQuietHours = QuietHours(
  startMinutes: 22 * 60,
  endMinutes: 7 * 60,
);

String _formatTimeOfDay(int minutes) {
  final hour = (minutes ~/ 60).toString().padLeft(2, '0');
  final minute = (minutes % 60).toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _kindLabel(ReminderKind kind) => switch (kind) {
      ReminderKind.upcoming => 'Period due',
      ReminderKind.pms => 'PMS watch',
      ReminderKind.late => 'Late nudge',
      ReminderKind.log => 'Daily log nudge',
    };

String _kindSubtitle(ReminderKind kind) => switch (kind) {
      ReminderKind.upcoming =>
        'A heads-up before the predicted period starts',
      ReminderKind.pms => 'An earlier heads-up for pre-period days',
      ReminderKind.late => 'A daily nudge while the cycle runs late',
      ReminderKind.log => 'A daily prompt to log the day',
    };

class ReminderSettingsScreen extends StatefulWidget {
  const ReminderSettingsScreen({
    super.key,
    this.timePicker = _defaultTimePicker,
  });

  final ReminderTimePicker timePicker;

  @override
  State<ReminderSettingsScreen> createState() => _ReminderSettingsScreenState();
}

class _ReminderSettingsScreenState extends State<ReminderSettingsScreen> {
  /// The profile id the operator picked (null = follow the active
  /// profile); resolved against the live list in [build], so a profile
  /// arriving after the screen opened selects itself without extra
  /// lifecycle hooks.
  String? _selectedId;

  /// The config currently shown; null until the selected profile's load
  /// resolves.
  ReminderConfig? _config;

  /// Which profile id [_config] belongs to — the dedupe key that keeps
  /// [build]'s "ensure loaded" kick from re-running on every rebuild.
  String? _loadedForId;

  @override
  void initState() {
    super.initState();
    // Prefer the active profile from the start, when the controller
    // already has it; [build] falls back to the first profile otherwise.
    final controller = context.read<ProfileController>();
    _selectedId = controller.activeProfile?.id;
  }

  /// Kicks the async load for [profile] when the selected profile changed
  /// since the last load. Called from [build] (field mutation only — no
  /// setState on the build path); the completion setState lands in a
  /// microtask, after the frame.
  void _ensureLoaded(Profile profile) {
    final service = context.read<ReminderConfigService>();
    _selectedId = profile.id;
    _loadedForId = profile.id;
    _config = null;
    unawaited(() async {
      final stored = await service.load(profile.id);
      if (!mounted) return;
      setState(() {
        _config = stored ?? ReminderConfig.fromMode(profile.mode);
      });
    }());
  }

  /// The profile the screen is editing: the operator's pick, else the
  /// active profile, else the first active profile.
  Profile? get _profile {
    final profiles = context.read<ProfileController>().activeProfiles;
    for (final profile in profiles) {
      if (profile.id == _selectedId) return profile;
    }
    return profiles.isEmpty ? null : profiles.first;
  }

  void _selectProfile(Profile profile) {
    if (profile.id == _selectedId) return;
    setState(() {
      _selectedId = profile.id;
      _loadedForId = null;
      _config = null;
    });
  }

  void _update(ReminderConfig config) {
    final profile = _profile;
    if (profile == null) return;
    setState(() => _config = config);
    // Fire-and-forget save: the coordinator replans from the service's
    // `changes` stream, never from this screen.
    unawaited(context.read<ReminderConfigService>().save(profile.id, config));
  }

  Future<void> _pickTime(ReminderKind kind) async {
    final config = _config;
    if (config == null) return;
    final picked = await widget.timePicker(
      context,
      _timeOfDay(config.typeConfig(kind).timeOfDayMinutes),
    );
    if (picked == null) return;
    _update(config.withTypeConfig(
      kind,
      config.typeConfig(kind).copyWith(
            timeOfDayMinutes: picked.hour * 60 + picked.minute,
          ),
    ));
  }

  Future<void> _pickQuietBoundary({required bool start}) async {
    final config = _config;
    if (config == null) return;
    final quiet = config.quietHours ?? kDefaultQuietHours;
    final initial = start ? quiet.startMinutes : quiet.endMinutes;
    final picked = await widget.timePicker(context, _timeOfDay(initial));
    if (picked == null) return;
    _update(config.copyWith(
      quietHours: _withQuietBoundary(
        quiet,
        start: start,
        minutes: picked.hour * 60 + picked.minute,
      ),
    ));
  }

  static TimeOfDay _timeOfDay(int minutes) =>
      TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

  /// Replaces one boundary of [quiet], keeping the other as-is (or its
  /// default, when [quiet] had none).
  static QuietHours _withQuietBoundary(
    QuietHours quiet, {
    required bool start,
    required int minutes,
  }) =>
      QuietHours(
        startMinutes: start ? minutes : quiet.startMinutes,
        endMinutes: start ? quiet.endMinutes : minutes,
      );

  @override
  Widget build(BuildContext context) {
    final profiles = context.watch<ProfileController>().activeProfiles;
    final profile = _resolve(profiles);
    if (profile != null && (profile.id != _loadedForId || _config == null)) {
      _ensureLoaded(profile);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      body: _body(profiles, profile),
    );
  }

  Widget _body(List<Profile> profiles, Profile? profile) {
    if (profiles.isEmpty || profile == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Create a profile to set up reminders.'),
        ),
      );
    }
    final config = _config;
    if (config == null) return const Center(child: CircularProgressIndicator());
    return ListView(
      children: [
        _profileTile(profiles, profile),
        const Divider(),
        for (final kind in ReminderKind.values) ...[
          _typeTile(kind, config),
          if (kind == ReminderKind.upcoming || kind == ReminderKind.pms)
            _leadTile(kind, config),
          _timeTile(kind, config),
          const Divider(),
        ],
        ..._quietTiles(config),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Reminders never show a name, date, or any health '
            'detail on the lock screen. Logging from a notification '
            'waits until the app is unlocked.',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }

  /// The profile the screen is editing, resolved against [profiles].
  Profile? _resolve(List<Profile> profiles) {
    for (final profile in profiles) {
      if (profile.id == _selectedId) return profile;
    }
    final controller = context.read<ProfileController>();
    return controller.activeProfile ??
        (profiles.isEmpty ? null : profiles.first);
  }

  Widget _profileTile(List<Profile> profiles, Profile profile) {
    return ListTile(
      key: const ValueKey('reminder-profile-tile'),
      title: const Text('Profile'),
      subtitle: Text(profile.displayName),
      trailing: profiles.length > 1
          ? DropdownButton<String>(
              key: const ValueKey('reminder-profile-dropdown'),
              value: profile.id,
              items: [
                for (final p in profiles)
                  DropdownMenuItem(value: p.id, child: Text(p.displayName)),
              ],
              onChanged: (id) => _selectById(id, profiles),
            )
          : null,
    );
  }

  void _selectById(String? id, List<Profile> profiles) {
    for (final profile in profiles) {
      if (profile.id == id) {
        _selectProfile(profile);
        return;
      }
    }
  }

  Widget _typeTile(ReminderKind kind, ReminderConfig config) {
    final typeConfig = config.typeConfig(kind);
    return SwitchListTile(
      key: ValueKey('reminder-${kind.name}-switch'),
      title: Text(_kindLabel(kind)),
      subtitle: Text(_kindSubtitle(kind)),
      value: typeConfig.enabled,
      onChanged: (on) => _update(config.withTypeConfig(
        kind,
        typeConfig.copyWith(enabled: on),
      )),
    );
  }

  Widget _leadTile(ReminderKind kind, ReminderConfig config) {
    final typeConfig = config.typeConfig(kind);
    return ListTile(
      key: ValueKey('reminder-${kind.name}-lead'),
      title: Text(kind == ReminderKind.upcoming
          ? 'Days before predicted start'
          : 'Days before predicted PMS window'),
      trailing: DropdownButton<int>(
        key: ValueKey('reminder-${kind.name}-lead-dropdown'),
        value: typeConfig.effectiveLeadDays(kUpcomingDefaultLeadDays),
        items: [
          for (final days in kLeadDayChoices)
            DropdownMenuItem(value: days, child: Text('$days')),
        ],
        onChanged: typeConfig.enabled
            ? (days) {
                if (days != null) {
                  _update(config.withTypeConfig(
                    kind,
                    typeConfig.copyWith(leadDays: days),
                  ));
                }
              }
            : null,
      ),
    );
  }

  Widget _timeTile(ReminderKind kind, ReminderConfig config) {
    final typeConfig = config.typeConfig(kind);
    return ListTile(
      key: ValueKey('reminder-time-${kind.name}'),
      title: const Text('Time'),
      trailing:
          Text(_formatTimeOfDay(typeConfig.timeOfDayMinutes)),
      onTap:
          typeConfig.enabled ? () => _pickTime(kind) : null,
    );
  }

  /// The quiet-hours switch, plus its two boundary rows when armed.
  List<Widget> _quietTiles(ReminderConfig config) {
    final quiet = config.quietHours;
    return [
      SwitchListTile(
        key: const ValueKey('reminder-quiet-switch'),
        title: const Text('Quiet hours'),
        subtitle: const Text(
            'A reminder that lands inside the window waits until it ends'),
        value: quiet != null,
        onChanged: (on) => _update(on
            ? config.copyWith(quietHours: kDefaultQuietHours)
            : config.copyWith(clearQuietHours: true)),
      ),
      if (quiet != null) ...[
        ListTile(
          key: const ValueKey('reminder-quiet-start'),
          title: const Text('Starts'),
          trailing: Text(_formatTimeOfDay(quiet.startMinutes)),
          onTap: () => _pickQuietBoundary(start: true),
        ),
        ListTile(
          key: const ValueKey('reminder-quiet-end'),
          title: const Text('Ends'),
          trailing: Text(_formatTimeOfDay(quiet.endMinutes)),
          onTap: () => _pickQuietBoundary(start: false),
        ),
      ],
    ];
  }
}
