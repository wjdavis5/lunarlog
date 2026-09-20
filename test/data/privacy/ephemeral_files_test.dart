/// Tests for the best-effort ephemeral-file cleanup (issue #843). Every
/// function here is contractually unable to throw, so the tests assert both
/// that cleanup happens and that a hostile filesystem state (missing
/// directory, no cache dir at all) is tolerated.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/privacy/ephemeral_files.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lunarlog-ephemeral-test');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  group('deleteFileBestEffort', () {
    test('deletes an existing file', () async {
      final file = File('${root.path}${Platform.pathSeparator}a.json');
      await file.writeAsString('secret');
      await deleteFileBestEffort(file);
      expect(await file.exists(), isFalse);
    });

    test('is silent when the file is already gone', () async {
      final file = File('${root.path}${Platform.pathSeparator}missing.json');
      await deleteFileBestEffort(file);
    });
  });

  group('deleteDirectoryBestEffort', () {
    test('deletes a directory and its contents recursively', () async {
      final dir = Directory('${root.path}${Platform.pathSeparator}d');
      await dir.create(recursive: true);
      await File('${dir.path}${Platform.pathSeparator}x').writeAsString('x');
      await deleteDirectoryBestEffort(dir);
      expect(await dir.exists(), isFalse);
    });

    test('is silent when the directory is already gone', () async {
      await deleteDirectoryBestEffort(
        Directory('${root.path}${Platform.pathSeparator}missing'),
      );
    });
  });

  group('sweepEphemeralCachesBestEffort', () {
    test('removes the plugin subdirectories and direct plugin files, and '
        'nothing else', () async {
      // Plugin-owned caches.
      for (final name in kEphemeralCacheDirNames) {
        final dir = Directory('${root.path}${Platform.pathSeparator}$name');
        await dir.create(recursive: true);
        await File('${dir.path}${Platform.pathSeparator}copy')
            .writeAsString('x');
      }
      // A direct plugin temp file (Android's createTempFile pattern).
      final direct = File(
        '${root.path}${Platform.pathSeparator}image_picker_1234.jpg',
      );
      await direct.writeAsString('x');
      // Unrelated cache content that must survive.
      final unrelatedFile = File(
        '${root.path}${Platform.pathSeparator}keep.txt',
      );
      await unrelatedFile.writeAsString('keep');
      final unrelatedDir = Directory(
        '${root.path}${Platform.pathSeparator}other',
      );
      await unrelatedDir.create(recursive: true);

      await sweepEphemeralCachesBestEffort(root);

      for (final name in kEphemeralCacheDirNames) {
        expect(
          await Directory('${root.path}${Platform.pathSeparator}$name')
              .exists(),
          isFalse,
          reason: '$name should be swept',
        );
      }
      expect(await direct.exists(), isFalse);
      expect(await unrelatedFile.exists(), isTrue);
      expect(await unrelatedDir.exists(), isTrue);
    });

    test('tolerates a missing directory', () async {
      await sweepEphemeralCachesBestEffort(
        Directory('${root.path}${Platform.pathSeparator}does-not-exist'),
      );
    });

    test(
      'tolerates a null cache directory (no platform cache reported)',
      () async {
        await sweepEphemeralCachesBestEffort(null);
      },
    );
  });

  group('temporaryCacheDirectory', () {
    test(
      'degrades to null when the test host has no path_provider plugin',
      () async {
        // Under flutter test the plugin is unregistered; the resolver must
        // swallow that and return null instead of throwing.
        expect(await temporaryCacheDirectory(), isNull);
      },
    );
  });

  group('sweepPluginCachesAtStartup', () {
    test('never throws even with no platform cache directory', () async {
      await sweepPluginCachesAtStartup();
    });
  });

  group('exportDirectoryIn', () {
    test('creates and returns the export-tmp subdirectory', () async {
      final dir = await exportDirectoryIn(root);
      expect(dir.path, endsWith(kExportTempDirectoryName));
      expect(await dir.exists(), isTrue);
    });

    test('is idempotent when called twice', () async {
      final first = await exportDirectoryIn(root);
      final second = await exportDirectoryIn(root);
      expect(second.path, first.path);
      expect(await second.exists(), isTrue);
    });
  });
}
