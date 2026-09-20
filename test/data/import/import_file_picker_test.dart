/// Tests for the import file picker adapter's read-and-clean-up sequence
/// (issue #843): the picked backup is deleted after its bytes are read and
/// file_picker's own temp cache is cleared — both best-effort, neither able to
/// surface. The plugin call itself is replaced by an injected [PickedImportFile]
/// so this runs under `flutter test`.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/import/import_file_picker.dart';
import 'package:lunarlog/domain/import/import_file_cap.dart'
    show ImportFileTooLargeException;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lunarlog-import-test');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  PickedImportFile picked(File file, {int? declaredLength}) => PickedImportFile(
    path: file.path,
    declaredLength: declaredLength,
    bytesStream: file.openRead(),
  );

  test('reads the bytes, deletes the picked file, and clears the picker '
      'cache (issue #843)', () async {
    final file = File('${root.path}${Platform.pathSeparator}backup.json');
    await file.writeAsString('{"a":1}');
    var cleared = false;

    final reader = PickImportFileReader(
      pickFile: () async => picked(file, declaredLength: 7),
      clearTemporaryFiles: () async => cleared = true,
    );

    final bytes = await reader.read();

    expect(bytes, isNotNull);
    expect(String.fromCharCodes(bytes!), '{"a":1}');
    expect(
      await file.exists(),
      isFalse,
      reason: 'the plugin copy of the backup must be deleted after the read',
    );
    expect(cleared, isTrue);
  });

  test('a cancelled pick returns null and runs no cleanup', () async {
    var cleared = false;
    final reader = PickImportFileReader(
      pickFile: () async => null,
      clearTemporaryFiles: () async => cleared = true,
    );

    expect(await reader.read(), isNull);
    expect(cleared, isFalse);
  });

  test('an oversized declared length rejects before reading, and cleanup '
      'still runs', () async {
    final file = File('${root.path}${Platform.pathSeparator}huge.json');
    await file.writeAsString('tiny');
    var cleared = false;
    final reader = PickImportFileReader(
      pickFile: () async => picked(file, declaredLength: 1 << 40),
      clearTemporaryFiles: () async => cleared = true,
    );

    await expectLater(
      reader.read(),
      throwsA(isA<ImportFileTooLargeException>()),
    );
    expect(await file.exists(), isFalse);
    expect(cleared, isTrue);
  });

  test('a clearTemporaryFiles failure never surfaces (issue #843)', () async {
    final file = File('${root.path}${Platform.pathSeparator}backup.json');
    await file.writeAsString('{"a":1}');
    final reader = PickImportFileReader(
      pickFile: () async => picked(file, declaredLength: 7),
      clearTemporaryFiles: () async => throw StateError('cache clear failed'),
    );

    final bytes = await reader.read();

    expect(bytes, isNotNull);
    expect(await file.exists(), isFalse);
  });

  test(
    'a null platform path skips the file delete but still clears the cache',
    () async {
      var cleared = false;
      final reader = PickImportFileReader(
        pickFile: () async => PickedImportFile(
          path: null,
          declaredLength: 0,
          bytesStream: Stream<List<int>>.empty(),
        ),
        clearTemporaryFiles: () async => cleared = true,
      );

      expect(await reader.read(), isNotNull);
      expect(cleared, isTrue);
    },
  );
}
