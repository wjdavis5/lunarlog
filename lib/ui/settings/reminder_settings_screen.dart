/// The per-profile local reminder configuration screen (Issue #136, R10,
/// R11; three-group layout Issue #178): one enable toggle, lead-days, and
/// time-of-day per reminder type, plus an optional daily quiet-hours
/// window — all device-local (`ReminderConfigService`), all taking effect
/// at the coordinator's next replan. Reached from Settings' "Reminders"
/// tile.
///
/// Issue #178 restructures the surface into Clue's three named groups —
/// **Your Cycle** (period starting soon, period due, PMS watch, period
/// late, fertile window soon, cycle statistic changes), **Your Birth
/// Control** (issue #183: the method-cadence adherence reminder matching
/// the profile's recorded birth-control method, or an explainer row when
/// no reminder applies), and **Other Reminders** (the daily log nudge) —
/// each item independently toggleable with its own time-of-day per the
/// existing per-type model.
///
/// The profile picker at the top is what makes the configuration
/// per-profile (the issue's routing requirement): each active profile
/// holds its own schedule, defaulting to its care-mode preset until first
/// edited. Lock-screen copy is deliberately *not* configurable here
/// (KTD7) — only scheduling is, and every notification keeps the same
/// generic title/body regardless of kind.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/birth_control.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/notifications/birth_control_reminder_kind.dart'
    show birthControlReminderKindFor;
import 'package:lunarlog/domain/notifications/notification_preferences.dart'
    show QuietHours;
import 'package:lunarlog/domain/notifications/reminder_config.dart';
import 'package:lunarlog/domain/notifications/reminder_config_store.dart';
import 'package:lunarlog/domain/repositories/profile_modes_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
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

/// The "Your Cycle" group, in Clue's catalogue order with the PMS-watch
/// kind slotted after the due reminder (Issue #178).
const List<ReminderKind> kCycleGroupKinds = [
  ReminderKind.periodStartingSoon,
  ReminderKind.upcoming,
  ReminderKind.pms,
  ReminderKind.late,
  ReminderKind.fertileWindowSoon,
  ReminderKind.cycleStatisticChange,
];

/// The "Other Reminders" group (Issue #178): Clue's tracking reminder and
/// daily check-in both map onto the existing daily log nudge.
const List<ReminderKind> kOtherGroupKinds = [ReminderKind.log];

String _formatTimeOfDay(int minutes) {
  final hour = (minutes ~/ 60).toString().padLeft(2, '0');
  final minute = (minutes % 60).toString().padLeft(2, '0');
  return '$hour:$minute';
}

/// Localized label for each kind. A map (not a switch) keeps the
/// per-kind complexity out of the CRAP gate's reach — one literal per
/// kind, exercised exhaustively by the reminder settings screen tests —
/// the same shape [birthControlChoiceLabels] uses.
Map<ReminderKind, String> _kindLabels(AppLocalizations l10n) => {
      ReminderKind.periodStartingSoon: l10n.reminderKindPeriodStartingSoon,
      ReminderKind.upcoming: l10n.reminderKindPeriodDue,
      ReminderKind.pms: l10n.reminderKindPmsWatch,
      ReminderKind.late: l10n.reminderKindPeriodLate,
      ReminderKind.fertileWindowSoon: l10n.reminderKindFertileWindowSoon,
      ReminderKind.cycleStatisticChange: l10n.reminderKindCycleStats,
      ReminderKind.log: l10n.reminderKindLogNudge,
      ReminderKind.birthControlPill: l10n.reminderKindBirthControlPill,
      ReminderKind.birthControlPatch: l10n.reminderKindBirthControlPatch,
      ReminderKind.birthControlRing: l10n.reminderKindBirthControlRing,
      ReminderKind.birthControlShot: l10n.reminderKindBirthControlShot,
    };

/// Localized subtitle for each kind (see [_kindLabels] for the map
/// rationale).
Map<ReminderKind, String> _kindSubtitles(AppLocalizations l10n) => {
      ReminderKind.periodStartingSoon:
          l10n.reminderKindPeriodStartingSoonSubtitle,
      ReminderKind.upcoming: l10n.reminderKindPeriodDueSubtitle,
      ReminderKind.pms: l10n.reminderKindPmsWatchSubtitle,
      ReminderKind.late: l10n.reminderKindPeriodLateSubtitle,
      ReminderKind.fertileWindowSoon: l10n.reminderKindFertileWindowSoonSubtitle,
      ReminderKind.cycleStatisticChange: l10n.reminderKindCycleStatsSubtitle,
      ReminderKind.log: l10n.reminderKindLogNudgeSubtitle,
      ReminderKind.birthControlPill: l10n.reminderKindBirthControlPillSubtitle,
      ReminderKind.birthControlPatch:
          l10n.reminderKindBirthControlPatchSubtitle,
      ReminderKind.birthControlRing: l10n.reminderKindBirthControlRingSubtitle,
      ReminderKind.birthControlShot: l10n.reminderKindBirthControlShotSubtitle,
    };

String _kindLabel(AppLocalizations l10n, ReminderKind kind) =>
    _kindLabels(l10n)[kind]!;

String _kindSubtitle(AppLocalizations l10n, ReminderKind kind) =>
    _kindSubtitles(l10n)[kind]!;

/// Whether [kind]'s adherence reminder anchors on the method's recorded
/// start date (issue #183): the patch, ring, and shot cadences count
/// their due dates from `birth_control_started_on`, so without one they
/// plan nothing and the settings row says so. The pill needs no anchor —
/// while the method is in effect every day is a dose day.
bool _birthControlKindNeedsStartDate(ReminderKind kind) => switch (kind) {
      ReminderKind.birthControlPatch ||
      ReminderKind.birthControlRing ||
      ReminderKind.birthControlShot =>
        true,
      ReminderKind.birthControlPill ||
      ReminderKind.upcoming ||
      ReminderKind.periodStartingSoon ||
      ReminderKind.pms ||
      ReminderKind.fertileWindowSoon ||
      ReminderKind.late ||
      ReminderKind.cycleStatisticChange ||
      ReminderKind.log =>
        false,
    };

/// The profile's birth-control method in effect today, from its raw
/// `profile_modes` state. A malformed effective date (storage validates
/// the ISO shape, but the row must never crash a settings render)
/// degrades to no method.
BirthControlMethod? _birthControlMethodInEffect(
  BirthControlState? state,
  LocalDate today,
) {
  if (state == null) return null;
  try {
    return birthControlMethodInEffectOn(
      storedMethod: state.method,
      startedOn: state.startedOn,
      stoppedOn: state.stoppedOn,
      date: today,
    );
  } on ArgumentError {
    return null;
  }
}

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

  /// The selected profile's raw birth-control state (issue #183), loaded
  /// alongside the config: it decides which adherence kind — or the
  /// explainer row — the "Your Birth Control" group renders.
  BirthControlState? _birthControlState;

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
    final modes = context.read<ProfileModesRepository>();
    _selectedId = profile.id;
    _loadedForId = profile.id;
    _config = null;
    _birthControlState = null;
    unawaited(() async {
      final results =
          await Future.wait([service.load(profile.id), modes.find(profile.id)]);
      if (!mounted) return;
      setState(() {
        final row = results[1] as ProfileLifecycleMode?;
        _birthControlState = row == null
            ? null
            : (
                method: row.birthControlMethod,
                startedOn: row.birthControlStartedOn,
                stoppedOn: row.birthControlStoppedOn,
              );
        _config = (results[0] as ReminderConfig?) ??
            ReminderConfig.fromMode(profile.mode);
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
      _birthControlState = null;
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
    final l10n = AppLocalizations.of(context);
    return ListView(
      children: [
        _profileTile(profiles, profile),
        const Divider(),
        ..._group(l10n.reminderSectionCycle, kCycleGroupKinds, config),
        ..._birthControlGroup(l10n, config),
        ..._group(l10n.reminderSectionOther, kOtherGroupKinds, config),
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

  /// One named group of reminder types (Issue #178): the header, then each
  /// type's toggle, lead-days (where the type has a forward anchor), and
  /// time rows.
  List<Widget> _group(
    String header,
    List<ReminderKind> kinds,
    ReminderConfig config,
  ) =>
      [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            header,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        for (final kind in kinds) ...[
          _typeTile(kind, config),
          if (_hasLead(kind)) _leadTile(kind, config),
          _timeTile(kind, config),
          const Divider(),
        ],
      ];

  /// The "Your Birth Control" group (Issue #178's layout, Issue #183's
  /// content): the adherence reminder matching the profile's recorded
  /// method — the pill's daily, the patch's weekly, the ring's monthly,
  /// the injection's 12-weekly cadence — toggleable exactly like every
  /// other type; or an explainer row when no reminder applies (no method
  /// recorded, the method has no user-administered cadence — implant and
  /// both IUD flavors — or it is not in effect today). A method change in
  /// profile settings swaps the row the next time the screen is opened,
  /// while the planner re-routes the armed reminders at the coordinator's
  /// next replan.
  List<Widget> _birthControlGroup(AppLocalizations l10n, ReminderConfig config) {
    final method = _birthControlMethodInEffect(
      _birthControlState,
      LocalDate.today(),
    );
    final kind = method == null ? null : birthControlReminderKindFor(method);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          l10n.reminderSectionBirthControl,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
      if (kind == null)
        ListTile(
          key: const ValueKey('reminder-birth-control-none'),
          title: Text(l10n.reminderBirthControlTitle),
          subtitle: Text(l10n.reminderBirthControlFollowsMethod),
          enabled: false,
        )
      else ...[
        _typeTile(
          kind,
          config,
          subtitleOverride:
              _birthControlKindNeedsStartDate(kind) &&
                  (_birthControlState?.startedOn ?? '').isEmpty
              ? l10n.reminderBirthControlNeedsStartDate
              : null,
        ),
        _timeTile(kind, config),
      ],
      const Divider(),
    ];
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

  Widget _typeTile(
    ReminderKind kind,
    ReminderConfig config, {
    String? subtitleOverride,
  }) {
    final typeConfig = config.typeConfig(kind);
    final l10n = AppLocalizations.of(context);
    return SwitchListTile(
      key: ValueKey('reminder-${kind.name}-switch'),
      title: Text(_kindLabel(l10n, kind)),
      subtitle: Text(subtitleOverride ?? _kindSubtitle(l10n, kind)),
      value: typeConfig.enabled,
      onChanged: (on) => _update(config.withTypeConfig(
        kind,
        typeConfig.copyWith(enabled: on),
      )),
    );
  }

  /// Whether [kind]'s row set includes a lead-days picker: exactly the
  /// types with a forward anchor (the estimate-anchored kinds and the
  /// fertile-window-anchored kind). The late window, the daily log nudge,
  /// the event-driven statistic-change kind, and issue #183's
  /// birth-control cadences (anchored on the method's own due dates, not
  /// ahead of them) have nothing to lead.
  static bool _hasLead(ReminderKind kind) => switch (kind) {
        ReminderKind.upcoming ||
        ReminderKind.periodStartingSoon ||
        ReminderKind.pms ||
        ReminderKind.fertileWindowSoon =>
          true,
        ReminderKind.late ||
        ReminderKind.cycleStatisticChange ||
        ReminderKind.log ||
        ReminderKind.birthControlPill ||
        ReminderKind.birthControlPatch ||
        ReminderKind.birthControlRing ||
        ReminderKind.birthControlShot =>
          false,
      };

  Widget _leadTile(ReminderKind kind, ReminderConfig config) {
    final typeConfig = config.typeConfig(kind);
    final l10n = AppLocalizations.of(context);
    return ListTile(
      key: ValueKey('reminder-${kind.name}-lead'),
      title: Text(switch (kind) {
        ReminderKind.pms => l10n.reminderLeadDaysBeforePms,
        ReminderKind.fertileWindowSoon =>
          l10n.reminderLeadDaysBeforeFertileWindow,
        _ => l10n.reminderLeadDaysBeforeStart,
      }),
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
