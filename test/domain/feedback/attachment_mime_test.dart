/// Unit tests for the attachment filename-to-MIME mapping (issue #215),
/// extracted from `image_picker_attachment_source.dart`'s private
/// `_mimeTypeFromName` into a pure domain function. The adapter's own seam
/// test (`test/data/feedback/image_picker_attachment_source_test.dart`)
/// still covers the end-to-end null-mime pick; these pin the mapping table
/// directly.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/feedback/attachment_mime.dart';

void main() {
  group('attachmentMimeTypeFromFilename', () {
    test('maps every supported extension, case-insensitively', () {
      const cases = {
        'IMG_0001.png': 'image/png',
        'IMG_0001.PNG': 'image/png',
        'IMG_0001.jpg': 'image/jpeg',
        'IMG_0001.jpeg': 'image/jpeg',
        'IMG_0001.JPG': 'image/jpeg',
        'IMG_0001.webp': 'image/webp',
        'photo.heic': 'image/jpeg',
        'photo.HEIC': 'image/jpeg',
        'photo.heif': 'image/jpeg',
        'photo.HEIF': 'image/jpeg',
      };
      for (final entry in cases.entries) {
        expect(
          attachmentMimeTypeFromFilename(entry.key),
          entry.value,
          reason: '${entry.key} should resolve to ${entry.value}',
        );
      }
    });

    test('maps an unsupported or missing extension to octet-stream', () {
      expect(
        attachmentMimeTypeFromFilename('shot.gif'),
        'application/octet-stream',
      );
      expect(
        attachmentMimeTypeFromFilename('shot'),
        'application/octet-stream',
      );
      expect(attachmentMimeTypeFromFilename(''), 'application/octet-stream');
      // Extension-looking suffixes that are not the whole extension.
      expect(
        attachmentMimeTypeFromFilename('shot.jpgx'),
        'application/octet-stream',
      );
    });

    test('a heic/heif pick maps to image/jpeg, not octet-stream (#207)', () {
      // With imageQuality passed, the plugin has already re-encoded the
      // pick as JPEG before the bytes cross into Dart — labelling it
      // octet-stream made the UI reject it as an unsupported type with no
      // way to comply from the gallery.
      expect(attachmentMimeTypeFromFilename('IMG_0001.heic'), 'image/jpeg');
      expect(attachmentMimeTypeFromFilename('IMG_0002.heif'), 'image/jpeg');
    });
  });
}
