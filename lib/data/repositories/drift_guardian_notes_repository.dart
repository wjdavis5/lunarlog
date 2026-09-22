/// Drift-backed [GuardianNotesRepository] over the storage layer (Issue
/// #801). Every call is scoped to exactly one profile id (R3), mirroring
/// [DriftCareContentRepository].
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/domain/models/guardian_note.dart' as domain;
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/repositories/guardian_notes_repository.dart';

import 'mappers.dart';

/// Issue #871: the Crockford base32 alphabet the server's ULID CHECK
/// (`^[0-9A-HJKMNP-TV-Z]{26}$`) accepts — digits plus A-Z minus I, L, O, U.
const String _crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// Issue #871: a deterministic, ULID-shaped id derived from a guardian
/// note's natural key `(profile, author, day)`.
///
/// Two devices that write the same author's note for the same day while
/// offline now mint the *same* row id, so `sync_push`'s existing per-id
/// last-writer-wins resolves them into one row instead of both surviving
/// as distinct rows (the bug: one was then invisible to its author). The
/// input is SHA-256'd and the digest encoded to Crockford base32, so the id
/// is stable across devices, platforms, and Dart versions — unlike
/// `String.hashCode`, which is not a cross-process contract.
String deterministicGuardianNoteId({
  required String profileId,
  required String? authorUserId,
  required String localDateIso,
}) {
  final input = '$profileId\u001f${authorUserId ?? ''}\u001f$localDateIso';
  return _encodeCrockford(sha256.convert(utf8.encode(input)).bytes, 26);
}

/// Encodes [bytes] to Crockford base32, taking the first [length] symbols.
String _encodeCrockford(List<int> bytes, int length) {
  final out = StringBuffer();
  var value = 0;
  var bits = 0;
  for (final byte in bytes) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      out.write(_crockford[(value >> bits) & 0x1f]);
    }
    // Keep only the bits not yet emitted so `value` cannot overflow as the
    // digest grows.
    value &= (1 << bits) - 1;
    if (out.length >= length) break;
  }
  if (out.length < length && bits > 0) {
    out.write(_crockford[(value << (5 - bits)) & 0x1f]);
  }
  return out.toString().substring(0, length);
}

class DriftGuardianNotesRepository implements GuardianNotesRepository {
  DriftGuardianNotesRepository(this._storage);

  final GuardianNoteStore _storage;

  @override
  Future<List<domain.GuardianNote>> listForProfile(String profileId) async => [
        for (final row in await _storage.getGuardianNotesForProfile(profileId))
          guardianNoteToDomain(row),
      ];

  @override
  Stream<List<domain.GuardianNote>> watchForProfile(String profileId) =>
      _storage
          .watchGuardianNotesForProfile(profileId)
          .map((rows) => rows.map(guardianNoteToDomain).toList());

  @override
  Future<domain.GuardianNote?> findOwnNoteForDate({
    required String profileId,
    required LocalDate localDate,
    required String? authorUserId,
  }) async {
    if (authorUserId == null) return null;
    final row = await _storage.findLiveGuardianNoteForDate(
      profileId: profileId,
      localDate: localDate.iso,
      authorUserId: authorUserId,
    );
    return row == null ? null : guardianNoteToDomain(row);
  }

  @override
  Future<domain.GuardianNote> save({
    String? id,
    required String profileId,
    required LocalDate localDate,
    required String tz,
    required String body,
    String? loggedByUserId,
  }) async {
    // Issue #871: a brand-new note whose author is known takes the
    // deterministic id, so two offline devices writing the same author's
    // note for the same day collide on one row at push time. An explicit
    // [id] (an edit) is always respected; a null author (a never-synced
    // local-only operator) keeps the random-ULID mint.
    final effectiveId = id ??
        (loggedByUserId == null
            ? null
            : deterministicGuardianNoteId(
                profileId: profileId,
                authorUserId: loggedByUserId,
                localDateIso: localDate.iso,
              ));
    return guardianNoteToDomain(await _storage.upsertGuardianNote(
      id: effectiveId,
      profileId: profileId,
      localDate: localDate.iso,
      tz: tz,
      body: body,
      loggedByUserId: loggedByUserId,
    ));
  }

  @override
  Future<void> delete(String id) => _storage.softDeleteGuardianNote(id);
}
