/// Orchestration for one seeder run (issue #710).
///
/// Order of operations, each a hard gate before the next:
///
/// 1. Allowlist — enforced in `seed_config.dart` before any client exists.
/// 2. Target guard — every LIVE profile the target can see (RLS-scoped
///    `profiles` + `profile_guardians` reads as the account) must be a
///    tool-created id from the state file; otherwise refuse, touching
///    nothing (the "refuses if the account owns or shares a profile it
///    didn't create" rule).
/// 3. Reset (only when a prior record exists) — `delete_profile_data` per
///    tool-created profile, as the account (the owner RPC).
/// 4. Partner bootstrap + the same guard for the partner.
/// 5. Push the payload through the real `sync_push` RPC, asserting
///    `rejected == []` after every call and failing loudly otherwise.
/// 6. Reminder windows (`upsert_reminder_window`) from the generated math.
/// 7. Sharing through the real RPCs: guardian invitations (co_parent on
///    the adult profile, caregiver on the teen) and one prediction
///    connection on the adult profile only (the teen counts as a minor —
///    refused by design, never attempted).
/// 8. Read-back verification (live day-entry and profile counts).
///
/// `notification_preferences` is deliberately never written (default-off
/// keeps the notification outbox clean).
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'payload_generator.dart';
import 'seed_config.dart';
import 'state_store.dart';
import 'supabase_seed_client.dart';
import 'sync_chunker.dart';

/// Thrown for every refusal/abort; [message] is safe to print.
class SeedRunException implements Exception {
  const SeedRunException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SeederDeps {
  const SeederDeps({
    required this.config,
    required this.client,
    required this.months,
    required this.seed,
    required this.statePath,
    required this.logger,
    this.resetAndReseed = false,
    this.clock = _systemClock,
    this.stateReaderWriter = const IoStateStore(),
  });

  static DateTime _systemClock() => DateTime.now();

  final SeedToolConfig config;
  final SupabaseSeedClient client;
  final int months;
  final int seed;
  final String statePath;
  final void Function(String line) logger;
  final bool resetAndReseed;
  final DateTime Function() clock;

  /// Injectable state-file access so tests can run without disk I/O.
  final SeedStateStore stateReaderWriter;
}

/// The state-file seam (file-backed in production, in-memory in tests).
class SeedStateStore {
  const SeedStateStore();

  SeedState load(String path) => loadStateFile(path);

  void write(String path, SeedState state) => writeStateFile(path, state);
}

class IoStateStore extends SeedStateStore {
  const IoStateStore();
}

/// One seeder run. See the library doc for the gated sequence.
class TestAccountSeeder {
  TestAccountSeeder(this._deps);

  final SeederDeps _deps;

  void _log(String line) => _deps.logger('[seed] $line');

  Future<Set<String>> _liveVisibleProfileIds(SeedSession session) async {
    final ids = <String>{};
    final profileRows = await _deps.client.restSelect(
      'profiles',
      'select=id&deleted_at=is.null',
      session,
    );
    ids.addAll(profileRows.map((r) => r['id']).whereType<String>());
    final guardianRows = await _deps.client.restSelect(
      'profile_guardians',
      'select=profile_id&status=eq.accepted',
      session,
    );
    ids.addAll(guardianRows.map((r) => r['profile_id']).whereType<String>());
    return ids;
  }

  Future<void> _guardAccount(
    String role,
    String email,
    SeedSession session,
    SeedState state,
  ) async {
    final visible = await _liveVisibleProfileIds(session);
    if (visible.isEmpty) return;
    final allowed = state.allowedProfileIdsFor(email);
    final foreign = visible.difference(allowed);
    if (foreign.isNotEmpty) {
      throw SeedRunException(
        '$role account $email owns or shares ${foreign.length} profile(s) '
        'this tool did not create (e.g. ${foreign.first}). Refusing to run '
        '— the seeder never touches profiles outside its own state file. '
        'If these are leftovers you are sure about, clear them manually or '
        'remove the state file only after deleting its profiles.',
      );
    }
  }

  Future<void> _assertSyncPushClean(
    String table,
    Object? result,
    int sentRows,
  ) async {
    if (result is! Map) {
      throw SeedRunException('sync_push($table): unexpected response shape');
    }
    final rejected = result['rejected'];
    if (rejected is List && rejected.isNotEmpty) {
      final ids = [
        for (final r in rejected)
          if (r is Map && r['id'] is String) r['id'] as String,
      ];
      throw SeedRunException(
        'sync_push($table): server REJECTED ${rejected.length} of $sentRows '
        'row(s) (first ids: ${ids.take(3).join(', ')}). The tool writes only '
        'payloads the server accepts; a rejection is a tool bug — nothing '
        'else from this run will be written.',
      );
    }
    final resolved = result['resolved'];
    _log('sync_push($table): $sentRows rows accepted'
        '${resolved is List && resolved.isNotEmpty ? ' (${resolved.length} resolved back — inspect)' : ''}');
  }

  /// Runs the full gated sequence. Returns a summary line per step (also
  /// logged); throws [SeedRunException] / [SeedHttpException] on refusal.
  Future<Map<String, Object>> run() async {
    final config = _deps.config;
    final state = _deps.stateReaderWriter.load(_deps.statePath);
    final record = state.runs[config.target.email.toLowerCase()];

    if (record != null &&
        (record.months != _deps.months || record.seed != _deps.seed) &&
        !_deps.resetAndReseed) {
      throw SeedRunException(
        'State file records months=${record.months}/seed=${record.seed} for '
        '${config.target.email}, but this run is '
        'months=${_deps.months}/seed=${_deps.seed}. Re-run with '
        '--reset-and-reseed to wipe and regenerate deliberately.',
      );
    }

    _log('target: ${config.target.email} | partner: ${config.partner.email} '
        '| months=${_deps.months} seed=${_deps.seed}');

    // ---- 1. target session + guard --------------------------------------
    final target = await _deps.client.bootstrapAccount(config.target);
    _log('target session ok (user ${target.userId})');
    await _guardAccount('target', config.target.email, target, state);

    // ---- 2. reset prior tool-created profiles ---------------------------
    final retiredIds = <String>[];
    if (record != null) {
      for (final profileId in record.profileIds) {
        final result = await _deps.client.rpc(
          'delete_profile_data',
          {'p_profile_id': profileId},
          target,
        );
        _log('delete_profile_data($profileId): '
            '${_summarizeDeletion(result)}');
        retiredIds.add(profileId);
      }
    }

    // ---- 3. partner session + guard --------------------------------------
    final partner = await _deps.client.bootstrapAccount(config.partner);
    _log('partner session ok (user ${partner.userId})');
    final stateWithRetired = record == null
        ? state
        : SeedState(runs: {
            ...state.runs,
            record.targetEmail.toLowerCase(): SeedStateRecord(
              targetEmail: record.targetEmail,
              partnerEmail: record.partnerEmail,
              profileIds: const [],
              retiredProfileIds: [
                ...record.retiredProfileIds,
                ...retiredIds,
              ],
              months: record.months,
              seed: record.seed,
              targetUserId: target.userId,
              partnerUserId: partner.userId,
            ),
          });
    await _guardAccount('partner', config.partner.email, partner, stateWithRetired);

    // ---- 4. generate + push ----------------------------------------------
    final payload = generateSeedPayload(SeedSpec(
      months: _deps.months,
      seed: _deps.seed,
      clock: _deps.clock,
    ));
    final batches = chunkForSyncPush(payload);
    _log('payload: ${payload.profiles.length} profiles, '
        '${payload.dayEntries.length} day entries, '
        '${payload.observations.length} observations, '
        '${payload.profileModes.length} profile modes, '
        '${payload.cycleOverrides.length} cycle overrides, '
        '${payload.careNotes.length} care notes, '
        '${payload.visitPrepItems.length} visit-prep items '
        '(${batches.length} sync_push calls)');

    final profileIds = payload.profiles
        .map((p) => p['id'])
        .whereType<String>()
        .toList();
    var pushed = 0;
    const allParams = [
      'p_profiles',
      'p_day_entries',
      'p_observations',
      'p_profile_modes',
      'p_cycle_overrides',
      'p_care_notes',
      'p_visit_prep_items',
    ];
    for (final batch in batches) {
      // All seven parameters always present (empty arrays for the tables
      // this call does not carry) — PostgREST resolves the function by the
      // named arguments in the body, and a partial subset does not match
      // the signature even though the omitted ones have defaults.
      final result = await _deps.client.rpc(
        'sync_push',
        {
          for (final param in allParams)
            param: batch.params[param] ?? const <Map<String, Object?>>[],
        },
        target,
      );
      await _assertSyncPushClean(
        batch.tableName,
        result,
        batch.totalRows,
      );
      pushed += batch.totalRows;
      if (batch.tableName == 'p_profiles') {
        // Persist the fresh profile ids as soon as they exist — on a first
        // run AND a re-run — so an aborted mid-run is recoverable by a
        // plain re-run (the guard will then recognize them and reset them).
        await _saveState(
          stateWithRetired,
          profileIds: profileIds,
          retired: retiredIds,
          target: target,
          partner: partner,
        );
      }
    }
    _log('pushed $pushed rows total; rejected == [] on every call');

    // ---- 5. reminder windows ----------------------------------------------
    for (final window in payload.reminderWindows) {
      await _deps.client.rpc(
        'upsert_reminder_window',
        {
          'p_profile_id': window.profileId,
          'p_estimated_next_start': window.estimatedNextStart,
          'p_episode_open': window.episodeOpen,
        },
        target,
      );
    }
    _log('reminder windows published (${payload.reminderWindows.length})');

    // ---- 6. sharing ---------------------------------------------------------
    final adultProfileId = payload.profiles.firstWhere(
      (p) => p['is_minor'] == false,
      orElse: () => payload.profiles.first,
    )['id']! as String;
    final teenProfileId = payload.profiles
        .where((p) => p['is_minor'] == true)
        .map((p) => p['id'])
        .whereType<String>()
        .firstOrNull;

    // Prediction connection FIRST, before the guardian invitations:
    // accept_prediction_connection refuses an existing guardian by design
    // (the one-directional rule at pair level), so the partner must redeem
    // it while still outside the profile. Adult profile only — a minor
    // profile is refused server-side by design (profile_counts_as_minor),
    // never attempted.
    final predictionToken = _generateToken();
    await _deps.client.rpc(
      'create_prediction_connection',
      {
        'p_profile_id': adultProfileId,
        'p_token_hash': _hashToken(predictionToken),
        'p_recipient_label': 'Jordan (seed partner)',
      },
      target,
    );
    await _deps.client.rpc(
      'accept_prediction_connection',
      {'p_token_hash': _hashToken(predictionToken)},
      partner,
    );
    _log('prediction connection created + accepted (adult profile only)');

    // Guardian sharing: co_parent on the adult profile, caregiver on the
    // teen profile.
    await _shareProfile(
      profileId: adultProfileId,
      role: 'co_parent',
      label: 'Jordan (seed partner)',
      target: target,
      partner: partner,
    );
    if (teenProfileId != null) {
      await _shareProfile(
        profileId: teenProfileId,
        role: 'caregiver',
        label: 'Jordan (seed partner)',
        target: target,
        partner: partner,
      );
    }

    // ---- 7. read-back --------------------------------------------------------
    final readBackProfiles = await _deps.client.restSelect(
      'profiles',
      'select=id&deleted_at=is.null',
      target,
    );
    final readBackEntryCount = await _deps.client.restCount(
      'day_entries',
      'deleted_at=is.null&profile_id=in.(${profileIds.join(',')})',
      target,
    );
    _log('read-back: ${readBackProfiles.length} live profile(s) visible; '
        '$readBackEntryCount live day entries '
        '(expected ${payload.dayEntries.length})');
    if (readBackEntryCount != payload.dayEntries.length) {
      throw SeedRunException(
        'read-back mismatch: pushed ${payload.dayEntries.length} live day '
        'entries but the account can read $readBackEntryCount',
      );
    }

    // ---- 8. persist state ------------------------------------------------------
    await _saveState(
      stateWithRetired,
      profileIds: profileIds,
      retired: retiredIds,
      target: target,
      partner: partner,
    );
    _log('state saved to ${_deps.statePath}');

    return {
      'profiles': profileIds,
      'dayEntries': readBackEntryCount,
      'observations': payload.observations.length,
      'syncPushCalls': batches.length,
    };
  }

  Future<void> _shareProfile({
    required String profileId,
    required String role,
    required String label,
    required SeedSession target,
    required SeedSession partner,
  }) async {
    final token = _generateToken();
    await _deps.client.rpc(
      'create_guardian_invitation',
      {
        'p_profile_id': profileId,
        'p_role': role,
        'p_recipient_label': label,
        'p_token_hash': _hashToken(token),
        'p_ttl_hours': 48,
      },
      target,
    );
    await _deps.client.rpc(
      'accept_guardian_invitation',
      {
        'p_token_hash': _hashToken(token),
        'p_guardian_display_name': label,
      },
      partner,
    );
    _log('guardian sharing: partner accepted $role on $profileId');
  }

  Future<void> _saveState(
    SeedState base, {
    required List<String> profileIds,
    required List<String> retired,
    required SeedSession target,
    required SeedSession partner,
  }) async {
    final config = _deps.config;
    final record = SeedStateRecord(
      targetEmail: config.target.email,
      partnerEmail: config.partner.email,
      profileIds: profileIds,
      retiredProfileIds: retired,
      months: _deps.months,
      seed: _deps.seed,
      targetUserId: target.userId,
      partnerUserId: partner.userId,
    );
    final next = SeedState(runs: {
      ...base.runs,
      config.target.email.toLowerCase(): record,
    });
    _deps.stateReaderWriter.write(_deps.statePath, next);
  }

  String _summarizeDeletion(Object? result) {
    if (result is Map) {
      final dayEntries = result['day_entries'];
      final observations = result['observations'];
      return 'purged (day_entries: $dayEntries, observations: $observations)';
    }
    return 'purged';
  }

  /// 32 bytes of entropy, base64url-encoded without padding — the same
  /// shape `SupabaseSharingService.createInvite` generates; only the
  /// SHA-256 hex ever leaves the process.
  String _generateToken() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  String _hashToken(String rawToken) =>
      sha256.convert(utf8.encode(rawToken)).toString();
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
