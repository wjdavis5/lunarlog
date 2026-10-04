import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the background-import gate in the privacy policy (issue #1224).
///
/// PRIVACY.md §4's background sentence used to read "once a profile is
/// bound, the same import pass can also run in the background without a
/// tap" — implying binding alone suffices — while the shipped code (issue
/// #1215) is stricter: `HealthImportService.importInBackground` returns
/// `firstImportNotStarted` until `HealthSyncBinding.hasCompletedFirstImport`
/// reports a completed user-initiated import for the current binding, and
/// binding or unbinding clears that marker. A privacy ledger that
/// understates a gate is not an overclaim, but it is still drift, so these
/// assertions keep the sentence, the ledger entry, and the code from
/// drifting apart again:
///
/// - §4's background sentence states the first-import gate, before it
///   states what the background pass does;
/// - Section 10's Change History carries the entry naming the gate;
/// - the "Last Updated" header's clause names the gate too (the header
///   line and the newest Change History bullet move together);
/// - the code still gates `importInBackground` on the marker the sentence
///   now names.
void main() {
  final privacy =
      File('PRIVACY.md').readAsStringSync().replaceAll('\r\n', '\n');

  // §4's health-sync paragraph is one markdown line, exactly the shape
  // `privacy_header_test.dart` reads; the background sentence is the part
  // that runs from "Reading starts" to the paragraph's next sentence.
  final paragraphStart = privacy.indexOf(
    '**On-device health-platform sync (Apple Health / Health Connect)',
  );
  final paragraph = paragraphStart < 0
      ? ''
      : privacy.substring(paragraphStart, privacy.indexOf('\n', paragraphStart));

  test("§4's background sentence names the first-import gate", () {
    expect(
      paragraphStart,
      greaterThanOrEqualTo(0),
      reason: "Section 4's health-sync paragraph is the ledger's background "
          'import story; it must exist',
    );
    const gate = 'once a profile is bound **and you have run the first '
        'import yourself**';
    expect(
      paragraph,
      contains(gate),
      reason: 'the background sentence must state the real gate — binding '
          'alone does not open it (issue #1224, behavior from issue #1215)',
    );
    const background = 'same import pass can also run in the background';
    expect(paragraph, contains(background));
    // The gate belongs to the background sentence, not merely somewhere in
    // the paragraph: it must precede the background phrase it qualifies.
    expect(
      paragraph.indexOf(gate),
      lessThan(paragraph.indexOf(background)),
      reason: 'the gate clause must qualify the background sentence itself',
    );
  });

  test("Section 10's Change History carries the gate entry", () {
    expect(
      privacy,
      contains('background health imports gated on your first import'),
      reason: 'the header line and the newest Change History bullet move '
          'together — the entry naming the gate is that bullet',
    );
    expect(
      privacy,
      contains('Unbinding or re-binding clears that marker'),
      reason: 'the entry must carry the per-binding scope (issue #1215)',
    );
  });

  test("the gate's Change History entry still names the gate", () {
    // The "Last Updated" header names the newest change (PRIVACY.md's own
    // rule, pinned by privacy_header_test.dart); the gate clause rides the
    // September 29 gate bullet wherever the header moves.
    final gateEntry = privacy
        .split('\n')
        .firstWhere((line) =>
            line.startsWith('- **September 29, 2026 (background health imports'));
    expect(gateEntry, contains('run the first import yourself'));
  });

  test('the code still gates importInBackground on the marker the policy '
      'names', () {
    // The facts the sentence paraphrases, read from their sources of
    // record so the policy and the app cannot drift apart.
    final service = File('lib/data/health/health_import_service.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect(
      service,
      contains('if (!await _binding.hasCompletedFirstImport())'),
      reason: 'the gate §4 names must still be the code gate',
    );
    expect(
      service,
      contains('firstImportNotStarted: true'),
      reason: 'an unstarted first import is a silent no-op, not an error',
    );
    final binding = File('lib/domain/health/health_sync_binding.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect(
      binding,
      contains('Future<bool> hasCompletedFirstImport()'),
      reason: 'the marker read behind the gate',
    );
    expect(
      binding,
      contains('_clearFirstImportMarker'),
      reason: 'the marker is per-binding — bind/unbind clear it',
    );
  });
}
