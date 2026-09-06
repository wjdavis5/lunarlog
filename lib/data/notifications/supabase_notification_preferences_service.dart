/// [NotificationPreferencesService] implementation over Supabase (Issue #5,
/// U6). The only file that touches [SupabaseClient] for this feature -
/// mirrors `lib/data/sharing/supabase_sharing_service.dart`'s error-mapping
/// shape.
///
/// `notification_preferences` carries no Realtime publication (KTD1 of the
/// wider plan: nothing about caregiver alerts is published), so [watchFor]
/// is a locally-broadcast stream: it fetches once on first subscription and
/// re-emits whenever [save] succeeds, rather than a live server push. This
/// is sufficient for a settings screen that owns the only writer.
library;

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/notifications/notification_preferences.dart';
import '../../domain/notifications/notification_preferences_service.dart';

class SupabaseNotificationPreferencesService
    implements NotificationPreferencesService {
  SupabaseNotificationPreferencesService({required this.client});

  final SupabaseClient client;

  final Map<String, StreamController<CaregiverAlertPreferences>>
      _controllers = {};

  @override
  Stream<CaregiverAlertPreferences> watchFor(String profileId) {
    final isNew = !_controllers.containsKey(profileId);
    final controller = _controllers.putIfAbsent(
      profileId,
      () => StreamController<CaregiverAlertPreferences>.broadcast(),
    );
    if (isNew) {
      unawaited(_loadInto(profileId, controller));
    }
    return controller.stream;
  }

  Future<void> _loadInto(
    String profileId,
    StreamController<CaregiverAlertPreferences> controller,
  ) async {
    try {
      final prefs = await _fetch(profileId);
      if (!controller.isClosed) controller.add(prefs);
    } catch (_) {
      // Best-effort initial load; a save() (or a future retry) can still
      // populate the stream. The screen shows the all-off default until
      // then rather than an error state for a read that never blocks R4.
    }
  }

  Future<CaregiverAlertPreferences> _fetch(String profileId) async {
    try {
      final userId = client.auth.currentUser?.id;
      if (userId == null) {
        throw const NotificationPreferencesFailure.unauthorized();
      }
      final row = await client
          .from('notification_preferences')
          .select()
          .eq('user_id', userId)
          .eq('profile_id', profileId)
          .maybeSingle();
      if (row == null) return CaregiverAlertPreferences.off;
      return _fromRow(row);
    } catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<void> save(
    String profileId,
    CaregiverAlertPreferences prefs,
  ) async {
    try {
      final userId = client.auth.currentUser?.id;
      if (userId == null) {
        throw const NotificationPreferencesFailure.unauthorized();
      }
      await client.from('notification_preferences').upsert({
        'user_id': userId,
        'profile_id': profileId,
        ..._toRow(prefs),
      });
    } catch (e) {
      throw _mapError(e);
    }
    _controllers[profileId]?.add(prefs);
  }

  static CaregiverAlertPreferences _fromRow(Map<String, dynamic> row) =>
      CaregiverAlertPreferences(
        alertOnLog: row['alert_on_log'] as bool? ?? false,
        alertOnCycleStartOnly:
            row['alert_on_cycle_start_only'] as bool? ?? false,
        alertOnHighSeverity: row['alert_on_high_severity'] as bool? ?? false,
        missedEntryThreshold:
            MissedEntryThreshold.fromDb(row['missed_entry_days'] as int?),
        quietHours: _quietHoursFromRow(
          row['quiet_hours_start'] as String?,
          row['quiet_hours_end'] as String?,
        ),
        timeZone: row['time_zone'] as String?,
      );

  static Map<String, dynamic> _toRow(CaregiverAlertPreferences prefs) => {
        'alert_on_log': prefs.alertOnLog,
        'alert_on_cycle_start_only': prefs.alertOnCycleStartOnly,
        'alert_on_high_severity': prefs.alertOnHighSeverity,
        'missed_entry_days': prefs.missedEntryThreshold.toDb(),
        'quiet_hours_start': _minutesToTimeString(prefs.quietHours?.startMinutes),
        'quiet_hours_end': _minutesToTimeString(prefs.quietHours?.endMinutes),
        'time_zone': prefs.timeZone,
      };

  static QuietHours? _quietHoursFromRow(String? start, String? end) {
    final startMinutes = _timeStringToMinutes(start);
    final endMinutes = _timeStringToMinutes(end);
    if (startMinutes == null || endMinutes == null) return null;
    return QuietHours(startMinutes: startMinutes, endMinutes: endMinutes);
  }

  static int? _timeStringToMinutes(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length < 2) return null;
    final hours = int.tryParse(parts[0]);
    final minutes = int.tryParse(parts[1]);
    if (hours == null || minutes == null) return null;
    return hours * 60 + minutes;
  }

  static String? _minutesToTimeString(int? minutes) {
    if (minutes == null) return null;
    final hours = (minutes ~/ 60) % 24;
    final mins = minutes % 60;
    return '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:00';
  }

  NotificationPreferencesFailure _mapError(Object error) {
    if (error is NotificationPreferencesFailure) return error;
    if (error is SocketException || error is http.ClientException) {
      return const NotificationPreferencesFailure.network();
    }
    if (error is PostgrestException) {
      return _mapPostgrestError(error);
    }
    return const NotificationPreferencesFailure.other();
  }

  NotificationPreferencesFailure _mapPostgrestError(PostgrestException error) {
    final code = error.code ?? '';
    final msg = error.message.toLowerCase();
    if (_isUnauthorized(code, msg)) {
      return const NotificationPreferencesFailure.unauthorized();
    }
    final status = int.tryParse(code);
    if (status != null && status >= 500) {
      return const NotificationPreferencesFailure.network();
    }
    return const NotificationPreferencesFailure.other();
  }

  bool _isUnauthorized(String code, String msg) =>
      code == 'PGRST301' ||
      code == '42501' ||
      msg.contains('permission') ||
      msg.contains('unauthorized');
}
