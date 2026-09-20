/// Tests for the shared export write→share→cleanup sequence (issue #843). A
/// real temporary directory and an injected share callback keep this runnable
/// under `flutter test` without `share_plus`/`path_provider`.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/export/export_file_share.dart';
import 'package:lunarlog/data/privacy/ephemeral_files.dart';

ExportShareFile _file(String name, String content) => ExportShareFile(
  fileName: name,
  bytes: Uint8List.fromList(content.codeUnits),
  mimeType: 'application/json',
);

void main() {
  late Directory root;
  late Directory cache;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lunarlog-share-test');
    cache = Directory('${root.path}${Platform.pathSeparator}cache');
    await cache.create(recursive: true);
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('writes each file under the export directory, shares it, then deletes '
      'the originals (issue #843)', () async {
    final sharedPaths = <String>[];
    final sharedNames = <String>[];

    await writeShareExportAndCleanup(
      directory: root,
      files: [_file('a.json', '{}'), _file('b.json', '{"b":1}')],
      cacheDirectory: cache,
      share: (files, names) async {
        for (final f in files) {
          sharedPaths.add(f.path);
          expect(
            await File(f.path).exists(),
            isTrue,
            reason: 'the file must exist while the share sheet holds it',
          );
        }
        sharedNames.addAll(names);
      },
    );

    expect(sharedNames, ['a.json', 'b.json']);
    for (final path in sharedPaths) {
      expect(
        await File(path).exists(),
        isFalse,
        reason: 'the app temp original is deleted after sharing',
      );
    }
  });

  test(
    'deletes the plugin share-cache copy after sharing (issue #843)',
    () async {
      final shareCache = Directory(
        '${cache.path}${Platform.pathSeparator}share_plus',
      );
      await shareCache.create(recursive: true);
      await File('${shareCache.path}${Platform.pathSeparator}copy')
          .writeAsString('exported content');

      await writeShareExportAndCleanup(
        directory: root,
        files: [_file('a.json', '{}')],
        cacheDirectory: cache,
        share: (files, names) async {},
      );

      expect(
        await shareCache.exists(),
        isFalse,
        reason: 'the share_plus cache copy must not persist',
      );
    },
  );

  test(
    'a cleanup failure neither fails the export nor surfaces (issue #843)',
    () async {
      var shared = false;

      await writeShareExportAndCleanup(
        directory: root,
        files: [_file('a.json', '{}')],
        cacheDirectory: cache,
        share: (files, names) async {
          shared = true;
        },
        deleteFile: (file) async => throw StateError('unlink denied'),
        sweepCache: (cacheDirectory) async => throw StateError('sweep denied'),
      );

      expect(shared, isTrue);
    },
  );

  test(
    'a share failure still attempts cleanup and propagates the share error',
    () async {
      final file = File('${root.path}${Platform.pathSeparator}a.json');

      await expectLater(
        writeShareExportAndCleanup(
          directory: root,
          files: [_file('a.json', '{}')],
          cacheDirectory: cache,
          share: (files, names) async => throw StateError('share sheet failed'),
        ),
        throwsA(isA<StateError>()),
      );

      expect(
        await file.exists(),
        isFalse,
        reason: 'cleanup still runs when the share throws',
      );
    },
  );

  test(
    'the default cleanup functions tolerate an absent cache directory',
    () async {
      await writeShareExportAndCleanup(
        directory: root,
        files: [_file('a.json', '{}')],
        cacheDirectory: null,
        share: (files, names) async {},
      );
      // No throw from the default sweep with a null cache directory.
    },
  );

  test('deleteFileBestEffort is the default delete seam', () async {
    // Guards against the default silently becoming a no-op.
    final file = File('${root.path}${Platform.pathSeparator}c.json');
    await file.writeAsString('x');
    await deleteFileBestEffort(file);
    expect(await file.exists(), isFalse);
  });
}
