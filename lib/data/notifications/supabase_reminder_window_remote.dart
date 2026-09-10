/// The Supabase-backed [ReminderWindowRemote] (Issue #5, U6; KTD4, R13):
/// the one narrow `upsert_reminder_window` write, no content. Constructed by
/// the composition factory (`lib/composition/app_dependencies.dart`) — the
/// composition module constructs this, it does not implement it.
library;

import 'package:lunarlog/domain/notifications/reminder_window_remote.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

class SupabaseReminderWindowRemote implements ReminderWindowRemote {
  SupabaseReminderWindowRemote(this._client);

  final SupabaseClient _client;

  @override
  Future<void> upsert({
    required String profileId,
    required String estimatedNextStartIso,
    required bool episodeOpen,
  }) async {
    await _client.rpc<dynamic>('upsert_reminder_window', params: {
      'p_profile_id': profileId,
      'p_estimated_next_start': estimatedNextStartIso,
      'p_episode_open': episodeOpen,
    });
  }
}
