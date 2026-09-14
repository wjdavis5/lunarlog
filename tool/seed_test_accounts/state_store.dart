/// The seeder's gitignored local state file (issue #710): what the tool
/// created, so re-runs can distinguish tool-created profiles from anything
/// else and refuse to touch the latter.
///
/// The default location is `.seed-state.json` at the repo root (added to
/// `.gitignore`). Pure JSON round-trip logic lives here; file I/O is in
/// `loadStateFile`/`writeStateFile` and stays thin.
library;

import 'dart:convert';
import 'dart:io';

class SeedStateRecord {
  const SeedStateRecord({
    required this.targetEmail,
    required this.partnerEmail,
    required this.profileIds,
    required this.months,
    required this.seed,
    this.targetUserId,
    this.partnerUserId,
    this.retiredProfileIds = const [],
  });

  factory SeedStateRecord.fromJson(Map<String, Object?> json) =>
      SeedStateRecord(
        targetEmail: json['targetEmail'] as String,
        partnerEmail: json['partnerEmail'] as String,
        profileIds: [
          for (final id in json['profileIds'] as List) id as String,
        ],
        months: json['months'] as int,
        seed: json['seed'] as int,
        targetUserId: json['targetUserId'] as String?,
        partnerUserId: json['partnerUserId'] as String?,
        retiredProfileIds: [
          for (final id in (json['retiredProfileIds'] as List?) ?? const [])
            id as String,
        ],
      );

  final String targetEmail;
  final String partnerEmail;

  /// The profile ids this record's LAST run created and left live.
  final List<String> profileIds;

  /// Profile ids from earlier runs of this record, since tombstoned by
  /// `delete_profile_data` (the profile row survives a reset as a
  /// content-free tombstone). Kept so the re-run guard can recognize them
  /// if a stale replica ever resurfaces them.
  final List<String> retiredProfileIds;

  final int months;
  final int seed;
  final String? targetUserId;
  final String? partnerUserId;

  Map<String, Object?> toJson() => {
        'targetEmail': targetEmail,
        'partnerEmail': partnerEmail,
        'profileIds': profileIds,
        'retiredProfileIds': retiredProfileIds,
        'months': months,
        'seed': seed,
        'targetUserId': targetUserId,
        'partnerUserId': partnerUserId,
      };
}

class SeedState {
  const SeedState({this.runs = const {}});

  /// Keyed by the target account email (lower-cased).
  final Map<String, SeedStateRecord> runs;

  factory SeedState.parse(String content) {
    if (content.trim().isEmpty) return const SeedState();
    final decoded = jsonDecode(content);
    if (decoded is! Map) {
      throw const FormatException('seed state file is not a JSON object');
    }
    final runs = decoded['runs'];
    if (runs is! Map) {
      throw const FormatException('seed state file has no runs object');
    }
    return SeedState(
      runs: {
        for (final entry in runs.entries)
          entry.key.toString():
              SeedStateRecord.fromJson(entry.value as Map<String, Object?>),
      },
    );
  }

  String encode() {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert({
      'version': 1,
      'runs': {
        for (final entry in runs.entries) entry.key: entry.value.toJson(),
      },
    });
  }

  /// Every profile id the tool may touch when acting as [email] (in either
  /// role — a partner shares the target's profiles, and an account that is
  /// itself another run's partner also sees that run's profiles).
  Set<String> allowedProfileIdsFor(String email) {
    final normalized = email.toLowerCase();
    final ids = <String>{};
    for (final record in runs.values) {
      if (record.targetEmail.toLowerCase() == normalized ||
          record.partnerEmail.toLowerCase() == normalized) {
        ids.addAll(record.profileIds);
        ids.addAll(record.retiredProfileIds);
      }
    }
    return ids;
  }
}

SeedState loadStateFile(String path) {
  final file = File(path);
  if (!file.existsSync()) return const SeedState();
  return SeedState.parse(file.readAsStringSync());
}

void writeStateFile(String path, SeedState state) {
  File(path).writeAsStringSync(state.encode());
}
