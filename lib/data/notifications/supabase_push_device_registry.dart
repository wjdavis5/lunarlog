/// [PushDeviceRegistry] implementation over Supabase (Issue #5, U7). Upserts
/// on `id` (the caller-supplied [deviceId]) so a token refresh replaces this
/// device's row rather than duplicating it (R19).
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
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    await client.from('push_devices').upsert({
      'id': deviceId,
      'user_id': userId,
      'token': token,
      'platform': platform,
      'disabled_at': null,
    });
  }

  @override
  Future<void> remove(String deviceId) async {
    await client.from('push_devices').delete().eq('id', deviceId);
  }
}
