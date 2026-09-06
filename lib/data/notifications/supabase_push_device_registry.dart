/// [PushDeviceRegistry] implementation over Supabase (Issue #5, U7).
///
/// [register] calls the `register_push_device` SECURITY DEFINER RPC
/// (`supabase/migrations/20260906160000_notification_preferences.sql`)
/// rather than upserting directly (round-2 review #1): a plain upsert
/// conflicting on `id` cannot recover from a stale row a previous account
/// on this install left behind (a failed sign-out deregistration is the
/// ordinary case, not the exotic one) - the UPDATE half of the upsert is
/// denied by RLS since the row's `user_id` does not match the new caller,
/// and there is no INSERT fallback once the conflict target already
/// exists, so the call silently affects nothing. The RPC runs as its
/// owner, so it can delete that stale row (matched by `id` *or* `token` -
/// the same physical install typically keeps the same FCM token across an
/// account switch) before inserting fresh under the caller's own
/// `auth.uid()`.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/notifications/push_registration.dart';

class SupabasePushDeviceRegistry implements PushDeviceRegistry {
  SupabasePushDeviceRegistry({required this.client});

  final SupabaseClient client;

  @override
  Future<void> register(
    String deviceId,
    String token, {
    required String platform,
  }) async {
    if (client.auth.currentUser?.id == null) return;
    await client.rpc<dynamic>('register_push_device', params: {
      'p_id': deviceId,
      'p_token': token,
      'p_platform': platform,
    });
  }

  @override
  Future<void> remove(String deviceId) async {
    await client.from('push_devices').delete().eq('id', deviceId);
  }

  @override
  Future<void> removeAllForCurrentUser() async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    await client.from('push_devices').delete().eq('user_id', userId);
  }
}
