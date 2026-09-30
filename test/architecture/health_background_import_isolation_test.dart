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
/// never call — every write, the authorization prompt, the deletion
/// propagation, and the native-mirror binding writes. Deliberately
/// NOT forbidden: `isAvailable`, `permissionStatus`, and
/// `openPermissionSettings` (the unguarded, no-user-data probes — the
/// background pass is contractually required to call `permissionStatus`).
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
        'requestWriteAuthorization (the probe replaces the prompt)', () {
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
            'Issue #959 permissionStatus probe is the only platform call '
            'it may make before the read.',
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
                name == 'requestWriteAuthorization',
          )
          .toSet();

      expect(channelWrites, isNotEmpty);
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
