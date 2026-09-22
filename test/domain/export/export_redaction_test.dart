/// Table-driven tests for the shared export redaction and the minor-profile
/// export guard (Issue #115, gap G4).
///
/// The point of the table is that the *pipeline* every format uses —
/// `redactForLens(entries, lens)` before the builder — honours the viewer
/// lens for every format, not just the free-text-bearing ones. JSON and CSV
/// carry a note column; FHIR and PDF never read `DayEntry.note` at all, so
/// they pass trivially in both lenses (and the table says so explicitly
/// rather than leaving the absence untested).
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/export/account_export.dart';
import 'package:lunarlog/domain/export/clinical_pdf.dart';
import 'package:lunarlog/domain/export/clinical_pdf_summary.dart';
import 'package:lunarlog/domain/export/csv_export.dart';
import 'package:lunarlog/domain/export/export_redaction.dart';
import 'package:lunarlog/domain/export/fhir_bundle.dart';
import 'package:lunarlog/domain/export/fhir_export_range.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/sharing/guardian_lens.dart';

/// A distinctive string that can only appear in an export if a note's text
/// was emitted; every assertion searches the encoded output for it.
const String _noteMarker = 'PRIVATE-NOTE-MARKER-9f3a';

/// The formats, mapped to a builder that encodes entries the same way their
/// production export does (the builders themselves are the production
/// builders — only the file-write/share tail is omitted).
final Map<String, String Function(List<DayEntry>)> _builders =
    <String, String Function(List<DayEntry>)>{
  'JSON': (entries) => jsonEncode(
        buildAccountExport(
          profiles: [_profile()],
          entriesByProfile: {'p1': entries},
          exportedAt: DateTime.utc(2026, 4, 2),
          appVersion: '1.0.0+1',
        ),
      ),
  'CSV': (entries) => buildDailyLogCsv(entries: entries),
  'FHIR': (entries) => jsonEncode(
        buildFhirDocumentBundle(
          profile: _profile(),
          dayEntries: entries,
          exportedAt: DateTime.utc(2026, 4, 2),
          appVersion: '1.0.0+1',
        ),
      ),
  'PDF': (entries) => latin1.decode(
        buildClinicalPdfDocument(
          buildClinicalPdfSummary(
            profile: _profile(),
            dayEntries: entries,
            range: FhirExportRange.everything,
            rangeLabel: 'Everything',
            generatedAt: DateTime.utc(2026, 4, 2),
          ),
        ),
      ),
};

/// Whether a format's builder emits `DayEntry.note` at all. JSON/CSV do;
/// FHIR/PDF document the note's exclusion in their own headers.
const Map<String, bool> _carriesNotes = {
  'JSON': true,
  'CSV': true,
  'FHIR': false,
  'PDF': false,
};

Profile _profile({bool isMinor = false}) => Profile(
      id: 'p1',
      displayName: 'Riley',
      isMinor: isMinor,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

DayEntry _entry({
  String id = 'e1',
  String? note = _noteMarker,
  bool notePrivate = false,
}) =>
    DayEntry(
      id: id,
      profileId: 'p1',
      localDate: LocalDate(2026, 4, 1),
      tz: 'UTC',
      flow: FlowLevel.medium,
      note: note,
      notePrivate: notePrivate,
      updatedAt: DateTime.utc(2026, 4, 1),
    );

ProfileGuardian _guardian({
  String userId = 'user-1',
  GuardianRole role = GuardianRole.caregiver,
  GuardianStatus status = GuardianStatus.accepted,
  bool isSubject = false,
}) =>
    ProfileGuardian(
      id: 'g-$userId',
      profileId: 'p1',
      userId: userId,
      role: role,
      status: status,
      isSubject: isSubject,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('redactForLens (the one shared step)', () {
    test('the subject lens returns entries untouched, byte-identical', () {
      final entries = [_entry(notePrivate: true)];
      final redacted = redactForLens(entries, GuardianLens.subject);
      expect(redacted.single, entries.single);
      expect(redacted.single.note, _noteMarker);
    });

    test('the guardian lens strips a private note but keeps the flag', () {
      final entry = _entry(notePrivate: true);
      final redacted = redactForLens([entry], GuardianLens.guardian).single;
      expect(redacted.note, isNull);
      expect(redacted.notePrivate, isTrue);
      // Non-note fields survive the copy.
      expect(redacted.id, entry.id);
      expect(redacted.localDate, entry.localDate);
      expect(redacted.flow, entry.flow);
      expect(redacted.tags, entry.tags);
    });

    test('the guardian lens never touches a shared (non-private) note', () {
      final redacted =
          redactForLens([_entry(notePrivate: false)], GuardianLens.guardian)
              .single;
      expect(redacted.note, _noteMarker);
    });

    test('the guardian lens leaves a private entry with no text alone', () {
      final redacted = redactForLens(
        [_entry(note: null, notePrivate: true)],
        GuardianLens.guardian,
      ).single;
      expect(redacted.note, isNull);
      expect(redacted.notePrivate, isTrue);
    });
  });

  group('every format honours the lens (Issue #115 G4 table)', () {
    for (final format in _builders.keys) {
      test('$format: a guardian-lens export never contains a private note',
          () {
        final encoded = _builders[format]!(
          redactForLens([_entry(notePrivate: true)], GuardianLens.guardian),
        );
        expect(encoded, isNot(contains(_noteMarker)));
      });

      test(
          '$format: the subject lens carries the note iff the format emits '
          'notes', () {
        final encoded = _builders[format]!(
          redactForLens([_entry(notePrivate: true)], GuardianLens.subject),
        );
        if (_carriesNotes[format]!) {
          expect(encoded, contains(_noteMarker));
        } else {
          expect(encoded, isNot(contains(_noteMarker)));
        }
      });
    }

    test(
        'sensitivity: without the redaction step a note-bearing format would '
        'leak the text, so the guardian assertions above are not vacuous', () {
      expect(_builders['JSON']!([_entry(notePrivate: true)]),
          contains(_noteMarker));
      expect(_builders['CSV']!([_entry(notePrivate: true)]),
          contains(_noteMarker));
    });

    test('the FHIR and PDF builders document note exclusion', () {
      // Both never read `DayEntry.note`; the marker is absent even with no
      // redaction, proving the guardian-lens assertions are structural.
      expect(_builders['FHIR']!([_entry(notePrivate: true)]),
          isNot(contains(_noteMarker)));
      expect(_builders['PDF']!([_entry(notePrivate: true)]),
          isNot(contains(_noteMarker)));
    });
  });

  group('canExportMinorProfile (Issue #115 G4 minor gate)', () {
    test('a non-minor profile is always exportable', () {
      expect(
        canExportMinorProfile(
          isMinor: false,
          guardians: [_guardian(userId: 'someone-else')],
          currentUserId: 'user-1',
        ),
        isTrue,
      );
    });

    test('a local-only operator (no account) fails open', () {
      expect(
        canExportMinorProfile(
          isMinor: true,
          guardians: const [],
          currentUserId: null,
        ),
        isTrue,
      );
    });

    test('unsynced membership rows fail open', () {
      expect(
        canExportMinorProfile(
          isMinor: true,
          guardians: const [],
          currentUserId: 'user-1',
        ),
        isTrue,
      );
    });

    test('an accepted guardian may export', () {
      expect(
        canExportMinorProfile(
          isMinor: true,
          guardians: [_guardian(userId: 'user-1')],
          currentUserId: 'user-1',
        ),
        isTrue,
      );
    });

    test('the subject may export', () {
      expect(
        canExportMinorProfile(
          isMinor: true,
          guardians: [
            _guardian(
              userId: 'user-1',
              role: GuardianRole.caregiver,
              isSubject: true,
            ),
          ],
          currentUserId: 'user-1',
        ),
        isTrue,
      );
    });

    test('a signed-in non-member is refused', () {
      expect(
        canExportMinorProfile(
          isMinor: true,
          guardians: [_guardian(userId: 'someone-else')],
          currentUserId: 'user-1',
        ),
        isFalse,
      );
    });

    test('a pending (not accepted) membership is refused', () {
      expect(
        canExportMinorProfile(
          isMinor: true,
          guardians: [
            _guardian(userId: 'user-1', status: GuardianStatus.pending),
          ],
          currentUserId: 'user-1',
        ),
        isFalse,
      );
    });
  });
}
