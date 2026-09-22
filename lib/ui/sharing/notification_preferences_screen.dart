/// Caregiver alert preferences screen (Issue #5, U8; R1, R3, R4, R17).
/// Reached from Manage guardians' Notifications tile. Every control writes
/// through [NotificationPreferencesService.save] optimistically; a failure
/// surfaces [notificationPreferencesFailureCopy] in a snackbar, matching
/// `lib/ui/sharing/invite_guardian_dialog.dart`'s behavior.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/l10n/notification_preferences_failure_copy.dart';

import '../../domain/models/profile.dart';
import '../../domain/notifications/notification_preferences.dart';
import '../../domain/notifications/notification_preferences_service.dart';
import '../../domain/util/timezone.dart';
import '../components/inline_error.dart';

/// Default quiet-hours window offered the first time a guardian sets one.
const int _kDefaultQuietStartMinutes = 22 * 60; // 22:00
const int _kDefaultQuietEndMinutes = 7 * 60; // 07:00

/// Mirrors the server-side digest fallback (08:00 local) shown in the UI
/// before the guardian picks an explicit time (Issue #125).
const int _kDefaultDigestMinutes = 8 * 60; // 08:00

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
  // LLA-083: an initial-load failure (as opposed to a save failure, which
  // `_timeZoneError`/the snackbar already cover) used to be swallowed --
  // `_loaded` stayed false forever and the screen spun. This makes that
  // failure an explicit, retryable state instead.
  bool _loadFailed = false;
  StreamSubscription<CaregiverAlertPreferences>? _sub;
  NotificationPreferencesInvalidTimeZoneFailure? _timeZoneError;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  /// Starts (or restarts, for a retry) watching preferences. The service's
  /// `watchFor` fetches fresh on every call (LLA-083), so re-invoking this
  /// after canceling the previous subscription is a genuine reload, not a
  /// no-op replay of a stale value.
  void _subscribe() {
    _sub = widget.preferencesService
        .watchFor(widget.profile.id)
        .listen(_onPrefsLoaded, onError: _onLoadError);
  }

  void _onPrefsLoaded(CaregiverAlertPreferences prefs) {
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _loaded = true;
      _loadFailed = false;
    });
  }

  void _onLoadError(Object error) {
    if (!mounted) return;
    setState(() => _loadFailed = true);
  }

  /// Synchronous, matching `activity_feed_screen.dart`'s `_retryFeed`
  /// precedent: the old subscription's `cancel()` need not be awaited
  /// before starting the new one -- it stops delivering to `_sub` the
  /// instant it is called, and awaiting it here left `pumpAndSettle` (whose
  /// loop only waits out a *scheduled frame*, not an arbitrary unrelated
  /// Future) free to return before the retry's own fetch had run.
  void _retryLoad() {
    unawaited(_sub?.cancel());
    setState(() => _loadFailed = false);
    _subscribe();
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
    setState(() {
      _prefs = next;
      _timeZoneError = null;
    });
    try {
      await widget.preferencesService.save(widget.profile.id, next);
    } catch (error) {
      if (!mounted) return;
      if (error is NotificationPreferencesInvalidTimeZoneFailure) {
        setState(() => _timeZoneError = error);
        return;
      }
      final l10n = AppLocalizations.of(context);
      final message = error is NotificationPreferencesFailure
          ? notificationPreferencesFailureCopy(l10n, error)
          : l10n.notificationPreferencesFailureOther;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _retrySave() => _apply((p) => p);

  Future<void> _confirmSaveWithoutTimeZone() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.sharingNotificationPreferencesSaveWithoutTzTitle),
        content: Text(l10n.sharingNotificationPreferencesSaveWithoutTzBody),
        actions: [
          TextButton(
            key: const ValueKey('timezone-fallback-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.sharingNotificationPreferencesCancel),
          ),
          FilledButton(
            key: const ValueKey('timezone-fallback-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.sharingNotificationPreferencesSaveWithoutTz),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() => _timeZoneError = null);
      await _apply((p) => p.copyWith(clearTimeZone: true));
    }
  }

  void _setAlertOnLog(bool value) => _apply((p) => p.copyWith(
        alertOnLog: value,
        // Turning the parent off also clears the narrowings, so re-enabling
        // later starts from a clean slate rather than silently reviving a
        // stale narrowing the guardian never re-confirmed.
        alertOnCycleStartOnly: value ? p.alertOnCycleStartOnly : false,
        alertOnHighSeverity: value ? p.alertOnHighSeverity : false,
        // Same clean-slate rule for the per-kind cadences (Issue #125):
        // re-enabling starts immediate, the pre-#125 behaviour.
        logCadence: value ? p.logCadence : AlertCadence.immediate,
        cycleStartCadence: value ? p.cycleStartCadence : AlertCadence.immediate,
        highSeverityCadence:
            value ? p.highSeverityCadence : AlertCadence.immediate,
      ));

  /// Applies [update] only when a cadence was actually chosen (the
  /// dropdown also emits null while rebuilding; a null selection is a
  /// no-op, not a save).
  void _setCadence(
    AlertCadence? value,
    CaregiverAlertPreferences Function(CaregiverAlertPreferences) update,
  ) {
    if (value == null) return;
    unawaited(_apply(update));
  }

  Future<void> _pickDigestTime() async {
    final initialMinutes = _prefs.digestTimeMinutes ?? _kDefaultDigestMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: initialMinutes ~/ 60,
        minute: initialMinutes % 60,
      ),
    );
    if (picked == null || !mounted) return;
    await _apply((p) =>
        p.copyWith(digestTimeMinutes: picked.hour * 60 + picked.minute));
  }

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
          timeZone: resolveCurrentTimeZoneSync(),
        ));
  }

  /// #554: was a hand-rolled, always-12h ("2:30 PM") formatter that ignored
  /// `MediaQuery.alwaysUse24HourFormat` -- the opposite hard-coded
  /// convention from `reminder_settings_screen.dart`'s old always-24h one.
  /// `TimeOfDay.format(context)` follows the device's actual setting.
  String _formatMinutes(int minutes) {
    final time = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
    return time.format(context);
  }

  /// One per-kind cadence selector (Issue #125). [onSelect] is dropped to
  /// null (the dropdown renders disabled) unless [enabled] -- the parent
  /// alert toggle, plus the matching narrowing for the cycle-start and
  /// high-severity kinds, gates each one exactly like the switches above.
  Widget _cadenceTile({
    required String tileKey,
    required String dropdownKey,
    required String title,
    String? subtitle,
    required AlertCadence value,
    required bool enabled,
    ValueChanged<AlertCadence?>? onSelect,
  }) =>
      ListTile(
        key: ValueKey(tileKey),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: DropdownButton<AlertCadence>(
          key: ValueKey(dropdownKey),
          value: value,
          onChanged: enabled ? onSelect : null,
          items: AlertCadence.values
              .map((c) => DropdownMenuItem(
                    value: c,
                    child: Text(c.label),
                  ))
              .toList(),
        ),
      );

  String _digestTimeLabel(CaregiverAlertPreferences prefs) =>
      _formatMinutes(prefs.digestTimeMinutes ?? _kDefaultDigestMinutes);

  /// The Issue #125 delivery section: one cadence selector per alert kind,
  /// plus the digest time. Spread into the settings list below.
  List<Widget> _deliverySection(CaregiverAlertPreferences prefs) => [
        const Divider(),
        _cadenceTile(
          tileKey: 'log-cadence-tile',
          dropdownKey: 'log-cadence-dropdown',
          title: AppLocalizations.of(context)
              .sharingNotificationPreferencesLogDeliveryTitle,
          subtitle: AppLocalizations.of(context)
              .sharingNotificationPreferencesLogDeliverySubtitle,
          value: prefs.logCadence,
          enabled: prefs.alertOnLog,
          onSelect: (value) =>
              _setCadence(value, (p) => p.copyWith(logCadence: value)),
        ),
        _cadenceTile(
          tileKey: 'cycle-start-cadence-tile',
          dropdownKey: 'cycle-start-cadence-dropdown',
          title: AppLocalizations.of(context)
              .sharingNotificationPreferencesCycleStartDelivery,
          value: prefs.cycleStartCadence,
          enabled: prefs.alertOnLog && prefs.alertOnCycleStartOnly,
          onSelect: (value) =>
              _setCadence(value, (p) => p.copyWith(cycleStartCadence: value)),
        ),
        _cadenceTile(
          tileKey: 'high-severity-cadence-tile',
          dropdownKey: 'high-severity-cadence-dropdown',
          title: AppLocalizations.of(context)
              .sharingNotificationPreferencesHighSeverityDelivery,
          value: prefs.highSeverityCadence,
          enabled: prefs.alertOnLog && prefs.alertOnHighSeverity,
          onSelect: (value) =>
              _setCadence(value, (p) => p.copyWith(highSeverityCadence: value)),
        ),
        ListTile(
          key: const ValueKey('digest-time-tile'),
          title: Text(
            AppLocalizations.of(context)
                .sharingNotificationPreferencesDigestTimeTitle,
          ),
          subtitle: Text(
            AppLocalizations.of(context)
                .sharingNotificationPreferencesDigestTimeSubtitle,
          ),
          trailing: Text(_digestTimeLabel(prefs)),
          onTap: _pickDigestTime,
        ),
        const Divider(),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).sharingNotificationPreferencesTitle),
      ),
      body: _buildBody(context),
    );
  }

  /// Review fix (CRAP gate): the three-way load-state selection this
  /// screen's body always started with -- pulled out of [build] so that
  /// method stays a single Scaffold construction and every branch below
  /// gets its own small, independently-measured method instead of all of
  /// them counting against one large one.
  Widget _buildBody(BuildContext context) {
    if (!_loaded && _loadFailed) {
      return Center(
        child: InlineError(
          key: const ValueKey('load-error'),
          message: AppLocalizations.of(context)
              .sharingNotificationPreferencesLoadError,
          onRetry: _retryLoad,
        ),
      );
    }
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return _buildSettingsList(context);
  }

  Widget _buildSettingsList(BuildContext context) {
    final prefs = _prefs;
    final l10n = AppLocalizations.of(context);
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            key: const ValueKey('discretion-copy'),
            l10n.sharingNotificationPreferencesDiscretion,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        SwitchListTile(
          key: const ValueKey('alert-on-log-toggle'),
          title: Text(
            l10n.sharingNotificationPreferencesNotifyOnLog(
              widget.profile.displayName,
            ),
          ),
          value: prefs.alertOnLog,
          onChanged: _setAlertOnLog,
        ),
        SwitchListTile(
          key: const ValueKey('alert-cycle-start-only-toggle'),
          title: Text(l10n.sharingNotificationPreferencesCycleStartOnly),
          value: prefs.alertOnLog && prefs.alertOnCycleStartOnly,
          onChanged: prefs.alertOnLog
              ? (value) =>
                  _apply((p) => p.copyWith(alertOnCycleStartOnly: value))
              : null,
        ),
        SwitchListTile(
          key: const ValueKey('alert-high-severity-toggle'),
          title: Text(l10n.sharingNotificationPreferencesHighSeverity),
          value: prefs.alertOnLog && prefs.alertOnHighSeverity,
          onChanged: prefs.alertOnLog
              ? (value) =>
                  _apply((p) => p.copyWith(alertOnHighSeverity: value))
              : null,
        ),
        ..._deliverySection(prefs),
        ListTile(
          key: const ValueKey('missed-entry-threshold-tile'),
          title: Text(l10n.sharingNotificationPreferencesMissedEntryTitle),
          subtitle:
              Text(l10n.sharingNotificationPreferencesMissedEntrySubtitle),
          trailing: DropdownButton<MissedEntryThreshold>(
            key: const ValueKey('missed-entry-threshold-dropdown'),
            value: prefs.missedEntryThreshold,
            onChanged: (value) {
              if (value != null) {
                unawaited(
                    _apply((p) => p.copyWith(missedEntryThreshold: value)));
              }
            },
            items: [
              DropdownMenuItem(
                  value: MissedEntryThreshold.off,
                  child: Text(l10n.sharingNotificationPreferencesOff)),
              DropdownMenuItem(
                  value: MissedEntryThreshold.oneDay,
                  child: Text(l10n.sharingNotificationPreferencesOneDay)),
              DropdownMenuItem(
                  value: MissedEntryThreshold.twoDays,
                  child: Text(l10n.sharingNotificationPreferencesTwoDays)),
              DropdownMenuItem(
                  value: MissedEntryThreshold.threeDays,
                  child: Text(l10n.sharingNotificationPreferencesThreeDays)),
            ],
          ),
        ),
        const Divider(),
        ..._aheadOfTimeSection(prefs),
        ..._quietHoursSection(prefs.quietHours),
        ..._timeZoneErrorSection(context),
      ],
    );
  }

  /// The Issue #851 "Ahead of time" group: three independent opt-ins for the
  /// server-side period_soon / restock_due / pms_soon alerts. Each is
  /// governed solely by its own boolean (there is no entry-alert master
  /// switch for these), so each toggle is always enabled and writes through
  /// the same optimistic [NotificationPreferencesService.save] path as every
  /// other control. The server copy stays the fixed generic line; nothing
  /// kind-specific is rendered here or in the notification.
  List<Widget> _aheadOfTimeSection(CaregiverAlertPreferences prefs) => [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            AppLocalizations.of(context)
                .sharingNotificationPreferencesAheadOfTimeHeader,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        SwitchListTile(
          key: const ValueKey('alert-period-soon-toggle'),
          title: Text(
            AppLocalizations.of(context)
                .sharingNotificationPreferencesPeriodSoon,
          ),
          subtitle: Text(
            AppLocalizations.of(context)
                .sharingNotificationPreferencesPeriodSoonSubtitle,
          ),
          value: prefs.aheadOfTimeAlerts.periodSoon,
          onChanged: (value) => _apply((p) => p.copyWith(
                aheadOfTimeAlerts:
                    p.aheadOfTimeAlerts.copyWith(periodSoon: value),
              )),
        ),
        SwitchListTile(
          key: const ValueKey('alert-restock-toggle'),
          title: Text(
            AppLocalizations.of(context).sharingNotificationPreferencesRestock,
          ),
          subtitle: Text(
            AppLocalizations.of(context)
                .sharingNotificationPreferencesRestockSubtitle,
          ),
          value: prefs.aheadOfTimeAlerts.restock,
          onChanged: (value) => _apply((p) => p.copyWith(
                aheadOfTimeAlerts:
                    p.aheadOfTimeAlerts.copyWith(restock: value),
              )),
        ),
        SwitchListTile(
          key: const ValueKey('alert-pms-soon-toggle'),
          title: Text(
            AppLocalizations.of(context).sharingNotificationPreferencesPmsSoon,
          ),
          subtitle: Text(
            AppLocalizations.of(context)
                .sharingNotificationPreferencesPmsSoonSubtitle,
          ),
          value: prefs.aheadOfTimeAlerts.pmsSoon,
          onChanged: (value) => _apply((p) => p.copyWith(
                aheadOfTimeAlerts:
                    p.aheadOfTimeAlerts.copyWith(pmsSoon: value),
              )),
        ),
      ];

  /// The quiet-hours start/end tiles plus the "Clear quiet hours" tile
  /// that only appears once a window is set. Split out of
  /// [_buildSettingsList] (review fix, CRAP gate) -- its two label
  /// ternaries and one conditional tile are exactly the kind of small,
  /// self-contained branching this file's own convention asks to be its
  /// own method rather than adding to a larger one.
  List<Widget> _quietHoursSection(QuietHours? quietHours) => [
        ListTile(
          key: const ValueKey('quiet-hours-start-tile'),
          title: Text(
            AppLocalizations.of(context).sharingNotificationPreferencesQuietStart,
          ),
          trailing: Text(
            quietHours == null
                ? AppLocalizations.of(context).sharingNotificationPreferencesOff
                : _formatMinutes(quietHours.startMinutes),
          ),
          onTap: () => _pickTime(isStart: true),
        ),
        ListTile(
          key: const ValueKey('quiet-hours-end-tile'),
          title: Text(
            AppLocalizations.of(context).sharingNotificationPreferencesQuietEnd,
          ),
          trailing: Text(
            quietHours == null
                ? AppLocalizations.of(context).sharingNotificationPreferencesOff
                : _formatMinutes(quietHours.endMinutes),
          ),
          onTap: () => _pickTime(isStart: false),
        ),
        if (quietHours != null)
          ListTile(
            key: const ValueKey('clear-quiet-hours-tile'),
            title: Text(
              AppLocalizations.of(context)
                  .sharingNotificationPreferencesClearQuietHours,
            ),
            onTap: () => _apply((p) => p.copyWith(
                  clearQuietHours: true,
                  clearTimeZone: true,
                )),
          ),
      ];

  /// The inline time-zone-fallback error block, present only while
  /// [_timeZoneError] is set. Split out of [_buildSettingsList] (review
  /// fix, CRAP gate) for the same reason as [_quietHoursSection] --
  /// returns no widgets at all rather than null, so the caller can spread
  /// it straight into the ListView's children like every other section.
  List<Widget> _timeZoneErrorSection(BuildContext context) {
    final error = _timeZoneError;
    if (error == null) return const [];
    return [
      Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InlineError(
              key: const ValueKey('timezone-inline-error'),
              message: notificationPreferencesFailureCopy(
                  AppLocalizations.of(context), error),
              onRetry: _retrySave,
            ),
            TextButton(
              key: const ValueKey('timezone-fallback-button'),
              onPressed: _confirmSaveWithoutTimeZone,
              child: Text(
                AppLocalizations.of(context)
                    .sharingNotificationPreferencesSaveWithoutTz,
              ),
            ),
          ],
        ),
      ),
    ];
  }
}
