/// Issue #993's background import can never reach a health-store write:
/// the background surface (the coordinator, the trigger channel, the
/// `importInBackground` entry point, and the domain interface the platform
/// triggers drive) contains no call to any write/authorization/deletion
/// method of [HealthPlatformStore]. Enforced the same way
/// `health_sync_binding_scope_test.dart` and `layering_test.dart` enforce
/// their disciplines: walking the source tree with `dart:io`, no lint
/// plugin, no new dependency.
///
/// The write direction stays exactly where it was — behind the guarded
/// `HealthPlatformStore` port that `importNow` (and only `importNow`'s
/// prompt-shaped entry point) legitimately uses. A future edit that adds a
/// write call to a background path fails this test rather than silently
/// shipping a background pass that can mutate the OS health store.
///
/// `///` doc comments are stripped before scanning (the same care
/// `health_sync_binding_scope_test.dart` takes that a prose mention must
/// not trip the guard); `//` line comments and `/* */` blocks are stripped
/// too, since this test's prose legitimately names the forbidden methods.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The guarded [HealthPlatformStore] methods a background import must
/// never call — every write, both authorization prompts (the write path's
/// and, since Issue #1515, the tap import's own), the deletion
/// propagation, and the native-mirror binding writes. Deliberately
/// NOT forbidden: `isAvailable`, `permissionStatus`,
/// `importPermissionStatus`, and `openPermissionSettings` (the unguarded,
/// no-user-data probes — the background pass is contractually required to
/// call `importPermissionStatus`, the read-side one; see the Issue #1491
/// group below for which probe belongs to which pass).
const List<String> _forbiddenWriteSurface = [
  'writeMenstrualFlow',
  'writeIntermenstrualBleeding',
  'writeMenstrualPeriod',
  'writeSymptomSamples',
  'writeCervicalMucus',
  'writeOvulationTest',
  'writeBasalBodyTemperature',
  'deleteRecords',
  'requestWriteAuthorization',
  'requestImportAuthorization',
  // Issue #1573: the prompt for past data, raised only by a tap.
  'requestPastDataAccess',
  'bindProfile',
  'unbindProfile',
];

/// Any `.name(` occurrence of a forbidden method — the call form. A bare
/// prose word (`bound`, `binding`) cannot match; only a real invocation
/// does.
final RegExp _forbiddenCallPattern = RegExp(
  _forbiddenWriteSurface.map((name) => '\\.$name\\(').join('|'),
);

/// Strips `///`, `//`, and `/* */` comments so this test's own prose (and
/// any explanatory doc comment) can never trip the scan.
String _stripComments(String contents) {
  final noBlock = contents.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return noBlock
      .split('\n')
      .map((line) {
        final docIndex = line.indexOf('///');
        if (docIndex >= 0) return line.substring(0, docIndex);
        // `//` only when it is not inside a string literal on this line —
        // the strings this codebase scans (`'lunarlog/health'`) contain no
        // `//`, so a plain check is safe here.
        final lineIndex = line.indexOf('//');
        if (lineIndex >= 0 && !line.contains("'")) {
          return line.substring(0, lineIndex);
        }
        return line;
      })
      .join('\n');
}

String _read(String path) => File(path).readAsStringSync();

/// Extracts one class/method block by brace matching: from the first
/// occurrence of [startPattern] to the closing brace of the `{` that
/// follows it. Throws when the pattern is gone (the structure this test
/// pins was renamed — update the test, don't loosen it).
String _block(String source, RegExp startPattern) {
  final start = startPattern.firstMatch(source);
  if (start == null) {
    throw StateError('expected block not found: $startPattern');
  }
  final open = source.indexOf('{', start.start);
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(start.start, i + 1);
    }
  }
  throw StateError('unbalanced braces after: $startPattern');
}

void main() {
  group('Issue #993: the background import path cannot reach a write API', () {
    test('the coordinator never calls a guarded write/authorization/'
        'deletion method', () {
      final source = _stripComments(
        _read('lib/data/health/health_background_import_service.dart'),
      );

      final match = _forbiddenCallPattern.firstMatch(source);
      expect(
        match,
        isNull,
        reason:
            'health_background_import_service.dart mentions '
            '${match?.group(0)} — a background pass must never write to, '
            're-bind, or prompt against the health store. The runner seam '
            '(HealthBackgroundImportRunner.importInBackground) is the only '
            'capability it gets.',
      );
    });

    test('the trigger channel never calls a guarded write/authorization/'
        'deletion method', () {
      final source = _stripComments(
        _read('lib/data/health/health_background_import_trigger.dart'),
      );

      final match = _forbiddenCallPattern.firstMatch(source);
      expect(
        match,
        isNull,
        reason:
            'health_background_import_trigger.dart mentions '
            '${match?.group(0)} — the trigger carries only the two trigger '
            'methods, never a write.',
      );
    });

    test('importInBackground is prompt-free: no bindProfile, no '
        'requestWriteAuthorization, no requestImportAuthorization (the '
        'probe replaces the prompt)', () {
      final source = _stripComments(
        _read('lib/data/health/health_import_service.dart'),
      );
      final body = _block(
        source,
        RegExp(r'Future<HealthImportSummary> importInBackground\('),
      );

      final match = _forbiddenCallPattern.firstMatch(body);
      expect(
        match,
        isNull,
        reason:
            'importInBackground calls ${match?.group(0)} — a background '
            'pass must never prompt or re-write the binding mirror; the '
            'read-side importPermissionStatus probe (Issue #1491) is the '
            'only platform call it may make before the read.',
      );
    });

    test(
      'the domain interface the triggers drive declares no write member',
      () {
        final source = _stripComments(
          _read('lib/domain/health/health_import.dart'),
        );
        final body = _block(
          source,
          RegExp(r'abstract interface class HealthBackgroundImportRunner'),
        );

        // A member declaration of any forbidden method (not just its call
        // form): the interface itself must stay prompt-free and write-free.
        final forbiddenMember = RegExp(
          _forbiddenWriteSurface.map((name) => '\\b$name\\b').join('|'),
        );
        final match = forbiddenMember.firstMatch(body);
        expect(
          match,
          isNull,
          reason:
              'HealthBackgroundImportRunner declares ${match?.group(0)} — '
              'the background interface must stay import-only '
              '(importInBackground + the platform getter).',
        );
      },
    );

    test('the forbidden list stays complete: every write-shaped channel '
        'method has a port method in the forbidden list', () {
      // Drift-proofing: a future write method added to
      // HealthChannelMethods (or the port) without being added to
      // [_forbiddenWriteSurface] fails here, so the scans above can never
      // silently go blind.
      final codec = _read('lib/data/health/health_channel_codec.dart');
      final channelWrites = RegExp(r"static const (\w+) = '")
          .allMatches(codec)
          .map((m) => m.group(1)!)
          .where(
            (name) =>
                name.startsWith('write') ||
                name == 'deleteRecords' ||
                // Every permission prompt, whichever direction it asks for
                // (Issue #1515 added the import's own).
                name.startsWith('request'),
          )
          .toSet();

      expect(channelWrites, isNotEmpty);
      expect(
        channelWrites,
        containsAll(['requestWriteAuthorization', 'requestImportAuthorization']),
      );
      for (final name in channelWrites) {
        expect(
          _forbiddenWriteSurface,
          contains(name),
          reason:
              '$name is a write-shaped channel method but is missing from '
              'this test\u2019s forbidden surface — add it so the background '
              'scans keep covering it.',
        );
      }
    });
  });

  // Issue #1491. There are two OS-permission probes and each belongs to one
  // direction: `permissionStatus` answers for the writes and gates the
  // write pass; `importPermissionStatus` answers for the reads the import
  // performs and gates the background import. The background import used
  // to read the write one, so it never ran for someone who allowed reading
  // only. A future edit that crosses the two fails here.
  group('Issue #1491: each pass is gated on its own direction\'s probe', () {
    test('importInBackground reads the read-side probe and never the '
        'write-side one', () {
      final source = _stripComments(
        _read('lib/data/health/health_import_service.dart'),
      );
      final body = _block(
        source,
        RegExp(r'Future<HealthImportSummary> importInBackground\('),
      );

      expect(body, contains('.importPermissionStatus()'));
      expect(
        body,
        isNot(contains('.permissionStatus()')),
        reason: 'the write permissions are not the background import\'s '
            'to wait on',
      );
    });

    test('nothing else in the import service reads the write-side probe',
        () {
      final source = _stripComments(
        _read('lib/data/health/health_import_service.dart'),
      );

      expect(source, isNot(contains('.permissionStatus()')));
      expect('.importPermissionStatus()'.allMatches(source), hasLength(1));
    });

    test('the write direction never reads the read-side probe', () {
      for (final path in [
        'lib/data/health/health_flow_write_service.dart',
        'lib/data/health/health_flow_write_coordinator.dart',
        'lib/data/health/health_sync_deletion_service.dart',
        'lib/data/health/health_sync_tombstone_coordinator.dart',
      ]) {
        expect(
          _stripComments(_read(path)),
          isNot(contains('importPermissionStatus')),
          reason: '$path gates writes; a read permission must not stop one',
        );
        // Issue #1549: nor the other read-side question.
        expect(
          _stripComments(_read(path)),
          isNot(contains('importReachesPastData')),
          reason: '$path gates writes; how far back a read reaches is '
              'nothing to it',
        );
      }
      // And the write pass still has its own gate.
      expect(
        _stripComments(
          _read('lib/data/health/health_flow_write_service.dart'),
        ),
        contains('.permissionStatus()'),
      );
    });
  });

  // Issue #1515. There are two permission requests and each belongs to one
  // direction, like the two probes above: `requestImportAuthorization` is
  // the tap import's (on Android the reads and no write permission) and
  // `requestWriteAuthorization` is the write pass's. The import used to
  // ask through the write pass's, so someone who had declined the writes
  // was shown them again on every tap of Import. A future edit that
  // crosses the two fails here.
  group('Issue #1515: each direction asks through its own request', () {
    test('the tap import raises the import\'s request and never the write '
        'path\'s', () {
      final source = _stripComments(
        _read('lib/data/health/health_import_service.dart'),
      );
      // From importNow's signature to the next entry point's, rather than a
      // brace match: its named-parameter braces would end the match at the
      // parameter list.
      final start = source.indexOf('Future<HealthImportSummary> importNow(');
      final end = source.indexOf(
        'Future<HealthImportSummary> importInBackground(',
      );
      expect(start, isNonNegative);
      expect(end, greaterThan(start));
      final body = source.substring(start, end);

      expect('.requestImportAuthorization('.allMatches(body), hasLength(1));
      // And nowhere in the service at all — importNow is its only prompt.
      expect(source, isNot(contains('.requestWriteAuthorization(')));
      expect('.requestImportAuthorization('.allMatches(source), hasLength(1));
    });

    test('the write direction never raises the import\'s request', () {
      for (final path in [
        'lib/data/health/health_flow_write_service.dart',
        'lib/data/health/health_flow_write_coordinator.dart',
        'lib/data/health/health_sync_deletion_service.dart',
        'lib/data/health/health_sync_tombstone_coordinator.dart',
      ]) {
        expect(
          _stripComments(_read(path)),
          isNot(contains('requestImportAuthorization')),
          reason: '$path writes; the import\'s request is not its to raise',
        );
      }
      // And the write pass still has its own, raised in exactly one place.
      expect(
        '.requestWriteAuthorization('.allMatches(
          _stripComments(
            _read('lib/data/health/health_flow_write_service.dart'),
          ),
        ),
        hasLength(1),
      );
    });

    test('the screen raises neither: it only reads the probe', () {
      final source = _stripComments(
        _read('lib/ui/settings/health_sync_screen.dart'),
      );

      expect(source, isNot(contains('requestWriteAuthorization')));
      expect(source, isNot(contains('requestImportAuthorization')));
    });

    test('the status line asks the read-side question only behind the '
        'platform fact, never by comparing the two answers', () {
      final source = _stripComments(
        _read('lib/ui/settings/health_sync_screen.dart'),
      );

      // One place asks it, and that place checks the fact first.
      expect('.importPermissionStatus()'.allMatches(source), hasLength(1));
      final fact = source.indexOf('if (!probe.readAccessDisclosed) return null;');
      final asked = source.indexOf('.importPermissionStatus()');
      expect(fact, isNonNegative,
          reason: 'the read-side answer must be withheld where the store '
              'does not disclose read access');
      expect(fact, lessThan(asked));
    });
  });

  group('Issue #1212: both import seams ride ONE service instance', () {
    test('the composition module constructs the import service exactly '
        'once, through the shared-seams builder', () {
      final source = _stripComments(
        _read('lib/composition/app_dependencies.dart'),
      );

      // One construction site: the concrete service is built a single
      // time and handed to both seams.
      expect(
        'LocalHealthImportService('.allMatches(source),
        hasLength(1),
      );
      // Its private builder is declared once and called once — a second
      // call site would be a second service with its own one-pass-at-a-
      // time gate, the two-instance overlap #1212 closed.
      expect(
        '_buildHealthImportService('.allMatches(source),
        hasLength(2),
        reason: 'declaration + exactly one call site',
      );
    });

    test('the app wires the runner and the coordinator from that one '
        'shared-seams builder', () {
      final source = _stripComments(_read('lib/app.dart'));

      expect(source, contains('buildHealthImportSeams('));
      expect(
        source,
        isNot(contains('buildHealthImportRunner')),
        reason: 'the retired per-seam builder constructed its own service '
            'instance — the importNow/importInBackground overlap #1212 '
            'closes',
      );
      expect(
        source,
        isNot(contains('buildHealthBackgroundImportCoordinator')),
        reason: 'the retired per-seam builder constructed its own service '
            'instance — the importNow/importInBackground overlap #1212 '
            'closes',
      );
    });

    test('_runPass serializes passes through the shared tail', () {
      final source = _stripComments(
        _read('lib/data/health/health_import_service.dart'),
      );
      // The service class, not the `_runPass` declaration block: its
      // record-typed parameters contain `{...}` braces that would truncate
      // the brace match at the parameter list.
      final service = _block(
        source,
        RegExp(r'class LocalHealthImportService'),
      );

      // The queue shape: each pass chains onto the previous pass's tail
      // and releases it only when its own steps have fully settled.
      expect(service, contains('Future<void> _passTail'));
      expect(service, contains('final previous = _passTail;'));
      expect(service, contains('_runPassSteps(bound, onProgress)'));
      expect(service, contains('.whenComplete(released.complete)'));

      // Both entry points funnel through the serialized _runPass —
      // importNow via `await` (since #1221 it inspects the summary to
      // stamp the first-import consent before returning) and
      // importInBackground via `return`.
      expect('_runPass(bound'.allMatches(service), hasLength(2));
    });
  });
}
