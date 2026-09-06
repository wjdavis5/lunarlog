/// Caregiver alert preferences screen (Issue #5, U8; R1, R3, R4, R17).
/// Reached from Manage guardians' Notifications tile. Every control writes
/// through [NotificationPreferencesService.save] optimistically; a failure
/// surfaces its `userFacingMessage` in a snackbar, matching
/// `lib/ui/sharing/invite_guardian_dialog.dart`'s behavior.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/models/profile.dart';
import '../../domain/notifications/notification_preferences.dart';
import '../../domain/notifications/notification_preferences_service.dart';
import '../../domain/util/timezone.dart';

/// Default quiet-hours window offered the first time a guardian sets one.
const int _kDefaultQuietStartMinutes = 22 * 60; // 22:00
const int _kDefaultQuietEndMinutes = 7 * 60; // 07:00

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({
    super.key,
    required this.profile,
    required this.preferencesService,
  });

  final Profile profile;
  final NotificationPreferencesService preferencesService;

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  CaregiverAlertPreferences _prefs = CaregiverAlertPreferences.off;
  bool _loaded = false;
  StreamSubscription<CaregiverAlertPreferences>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.preferencesService
        .watchFor(widget.profile.id)
        .listen((prefs) {
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  Future<void> _apply(
    CaregiverAlertPreferences Function(CaregiverAlertPreferences) transform,
  ) async {
    final next = transform(_prefs);
    setState(() => _prefs = next);
    try {
      await widget.preferencesService.save(widget.profile.id, next);
    } catch (error) {
      if (!mounted) return;
      final message = error is NotificationPreferencesFailure
          ? error.userFacingMessage
          : 'Failed to save notification preferences. Please try again.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _setAlertOnLog(bool value) => _apply((p) => p.copyWith(
        alertOnLog: value,
        // Turning the parent off also clears the narrowings, so re-enabling
        // later starts from a clean slate rather than silently reviving a
        // stale narrowing the guardian never re-confirmed.
        alertOnCycleStartOnly: value ? p.alertOnCycleStartOnly : false,
        alertOnHighSeverity: value ? p.alertOnHighSeverity : false,
      ));

  Future<void> _pickTime({required bool isStart}) async {
    final current = _prefs.quietHours ??
        const QuietHours(
          startMinutes: _kDefaultQuietStartMinutes,
          endMinutes: _kDefaultQuietEndMinutes,
        );
    final initialMinutes = isStart ? current.startMinutes : current.endMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: initialMinutes ~/ 60,
        minute: initialMinutes % 60,
      ),
    );
    if (picked == null || !mounted) return;
    final minutes = picked.hour * 60 + picked.minute;
    final next = isStart
        ? current.copyWith(startMinutes: minutes)
        : current.copyWith(endMinutes: minutes);
    await _apply((p) => p.copyWith(
          quietHours: next,
          timeZone: resolveCurrentTimeZone(),
        ));
  }

  String _formatMinutes(int minutes) {
    final time = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final prefs = _prefs;
    final quietHours = prefs.quietHours;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    key: const ValueKey('discretion-copy'),
                    'Alerts never show what was logged - just a generic '
                    'reminder to open Lunarlog.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                SwitchListTile(
                  key: const ValueKey('alert-on-log-toggle'),
                  title:
                      Text('Notify me when ${widget.profile.displayName} logs an entry'),
                  value: prefs.alertOnLog,
                  onChanged: _setAlertOnLog,
                ),
                SwitchListTile(
                  key: const ValueKey('alert-cycle-start-only-toggle'),
                  title: const Text('Only notify on cycle start'),
                  value: prefs.alertOnLog && prefs.alertOnCycleStartOnly,
                  onChanged: prefs.alertOnLog
                      ? (value) =>
                          _apply((p) => p.copyWith(alertOnCycleStartOnly: value))
                      : null,
                ),
                SwitchListTile(
                  key: const ValueKey('alert-high-severity-toggle'),
                  title: const Text('Notify on high-severity days'),
                  value: prefs.alertOnLog && prefs.alertOnHighSeverity,
                  onChanged: prefs.alertOnLog
                      ? (value) =>
                          _apply((p) => p.copyWith(alertOnHighSeverity: value))
                      : null,
                ),
                const Divider(),
                ListTile(
                  key: const ValueKey('missed-entry-threshold-tile'),
                  title: const Text('Missed-entry reminder'),
                  subtitle: const Text(
                      'Check in when no entry has been logged for a while'),
                  trailing: DropdownButton<MissedEntryThreshold>(
                    key: const ValueKey('missed-entry-threshold-dropdown'),
                    value: prefs.missedEntryThreshold,
                    onChanged: (value) {
                      if (value != null) {
                        _apply((p) => p.copyWith(missedEntryThreshold: value));
                      }
                    },
                    items: const [
                      DropdownMenuItem(
                          value: MissedEntryThreshold.off, child: Text('Off')),
                      DropdownMenuItem(
                          value: MissedEntryThreshold.oneDay,
                          child: Text('1 day')),
                      DropdownMenuItem(
                          value: MissedEntryThreshold.twoDays,
                          child: Text('2 days')),
                      DropdownMenuItem(
                          value: MissedEntryThreshold.threeDays,
                          child: Text('3 days')),
                    ],
                  ),
                ),
                const Divider(),
                ListTile(
                  key: const ValueKey('quiet-hours-start-tile'),
                  title: const Text('Quiet hours start'),
                  trailing: Text(
                    quietHours == null
                        ? 'Off'
                        : _formatMinutes(quietHours.startMinutes),
                  ),
                  onTap: () => _pickTime(isStart: true),
                ),
                ListTile(
                  key: const ValueKey('quiet-hours-end-tile'),
                  title: const Text('Quiet hours end'),
                  trailing: Text(
                    quietHours == null
                        ? 'Off'
                        : _formatMinutes(quietHours.endMinutes),
                  ),
                  onTap: () => _pickTime(isStart: false),
                ),
                if (quietHours != null)
                  ListTile(
                    key: const ValueKey('clear-quiet-hours-tile'),
                    title: const Text('Clear quiet hours'),
                    onTap: () => _apply((p) => p.copyWith(
                          clearQuietHours: true,
                          clearTimeZone: true,
                        )),
                  ),
              ],
            ),
    );
  }
}
