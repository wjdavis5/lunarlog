/// Unit tests for `lib/domain/import/import_file_cap.dart` (Issue #626,
/// LLA-089): the streaming byte cap the platform file picker
/// (`lib/data/import/import_file_picker.dart`, untestable under `flutter
/// test`) delegates to. Every stream here is small and synthetic — no
/// large binaries, and `maxBytes` is always overridden to a tiny value so
/// the cap can be proven without ever actually allocating anything close
/// to the real 256 MiB [kMaxImportFileBytes].
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/import/account_import.dart' show kMaxImportFileBytes;
import 'package:lunarlog/domain/import/import_file_cap.dart';

void main() {
  group('readCappedBytes — happy path', () {
    test('a stream at or under maxBytes returns every byte, in order', () async {
      final bytes = await readCappedBytes(
        byteStream: Stream.fromIterable([
          [1, 2, 3],
          [4, 5],
        ]),
        maxBytes: 10,
      );
      expect(bytes, [1, 2, 3, 4, 5]);
    });

    test('declaredLength at or under maxBytes does not itself reject — only '
        'the actual stream total matters once reading proceeds', () async {
      final bytes = await readCappedBytes(
        byteStream: Stream.fromIterable([
          [1, 2, 3],
        ]),
        declaredLength: 3,
        maxBytes: 10,
      );
      expect(bytes, [1, 2, 3]);
    });

    test('a null declaredLength (platform did not report one) skips the '
        'preflight and relies on the streamed cap alone', () async {
      final bytes = await readCappedBytes(
        byteStream: Stream.fromIterable([
          [1, 2],
        ]),
        maxBytes: 10,
      );
      expect(bytes, [1, 2]);
    });

    test('defaults to kMaxImportFileBytes when maxBytes is not overridden',
        () async {
      final bytes = await readCappedBytes(
        byteStream: Stream.fromIterable([
          [1, 2, 3],
        ]),
        declaredLength: kMaxImportFileBytes - 1,
      );
      expect(bytes, [1, 2, 3]);
    });
  });

  group('readCappedBytes — declaredLength preflight (Issue #626, LLA-089)', () {
    test('declaredLength over maxBytes throws WITHOUT ever listening to the '
        'byte stream — an honestly-oversized file is rejected before a '
        'single chunk is requested', () async {
      var listened = false;
      // Deliberately never closed: this callback only runs if something
      // subscribes, which — per this test's own assertion — must never
      // happen, so there is nothing here for a real listener to await.
      final stream = Stream<List<int>>.multi((controller) {
        listened = true;
      });

      await expectLater(
        () => readCappedBytes(
          byteStream: stream,
          declaredLength: 1000,
          maxBytes: 10,
        ),
        throwsA(isA<ImportFileTooLargeException>()),
      );
      expect(listened, isFalse,
          reason: 'the declaredLength preflight must short-circuit before '
              'the stream is ever subscribed to');
    });

    test('ImportFileTooLargeException.message matches '
        'importFileTooLargeMessage() — the same copy '
        "parseAccountImport's own post-hoc bytes.length check shows",
        () async {
      Object? caught;
      try {
        await readCappedBytes(
          byteStream: const Stream<List<int>>.empty(),
          declaredLength: 1000,
          maxBytes: 10,
        );
      } catch (error) {
        caught = error;
      }
      expect(caught, isA<ImportFileTooLargeException>());
      expect((caught as ImportFileTooLargeException).message,
          contains('larger than lunarlog can import'));
    });
  });

  group('readCappedBytes — streamed cap (Issue #626, LLA-089)', () {
    test('an oversized actual stream throws once the running total exceeds '
        'maxBytes, even though declaredLength under-reported it (a lying '
        'or stale declared size never bypasses the real cap)', () async {
      final stream = Stream<List<int>>.fromIterable([
        List.filled(5, 0),
        List.filled(5, 0),
        List.filled(5, 0), // running total 15 > maxBytes 10
      ]);

      await expectLater(
        () => readCappedBytes(
          byteStream: stream,
          declaredLength: 5, // passes the preflight
          maxBytes: 10,
        ),
        throwsA(isA<ImportFileTooLargeException>()),
      );
    });

    test('the cap is enforced DURING the read, not only after the whole '
        'stream is buffered: a stream that would keep producing chunks '
        'forever is abandoned within a handful of chunks, never drained',
        () async {
      var chunksProduced = 0;
      Stream<List<int>> infiniteStream() async* {
        while (true) {
          chunksProduced++;
          // A safety valve so a regression in the cap logic fails this
          // test quickly (an assertion below) rather than hanging forever.
          if (chunksProduced > 100000) return;
          yield [0, 0, 0];
        }
      }

      await expectLater(
        () => readCappedBytes(
          byteStream: infiniteStream(),
          maxBytes: 10,
        ),
        throwsA(isA<ImportFileTooLargeException>()),
      );
      expect(chunksProduced, lessThan(100),
          reason: 'bound allocation while reading (LLA-089): the read must '
              'stop within a handful of 3-byte chunks of a 10-byte cap, '
              'never anywhere near the 100000-chunk safety valve');
    });
  });
}
