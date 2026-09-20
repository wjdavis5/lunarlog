/// Thin adapter over the `image_picker` plugin (Issue #6, U7). Platform
/// concern, like `lib/data/auth/google_sign_in_client.dart`: the domain and
/// UI layers only ever see [AttachmentSource]/[FeedbackAttachment]. Only the
/// plugin call itself is untestable under `flutter test`; every decision
/// around it runs against the injected [PickGalleryImage] seam (see
/// `test/data/feedback/image_picker_attachment_source_test.dart`, #207), and
/// the name-based mime fallback is the pure domain function
/// `attachmentMimeTypeFromFilename()` in
/// `lib/domain/feedback/attachment_mime.dart` with its own direct unit
/// tests (#215).
library;

import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:lunarlog/domain/feedback/attachment_mime.dart';
import 'package:lunarlog/domain/feedback/feedback_service.dart';

import '../privacy/ephemeral_files.dart';

/// Longest edge the plugin downscales a pick to before the bytes cross into
/// Dart (#207). A typical modern 12 MP photo (4032x3024) becomes 2048x1536,
/// which at [kAttachmentJpegQuality] encodes to a fraction of
/// [kMaxAttachmentBytes] — the old code loaded the full-size photo into
/// memory and then usually rejected it.
const double kMaxAttachmentImageEdge = 2048;

/// JPEG quality the plugin re-encodes a pick with (#207). Passing this is
/// also what normalises the format: image_picker_ios re-encodes through
/// `UIImageJPEGRepresentation` whenever a quality is supplied (a HEIC pick
/// resolves to its default type there, which converts to JPEG), and
/// image_picker_android does the same through BitmapFactory/skia.
const int kAttachmentJpegQuality = 80;

/// Seam over `ImagePicker.pickImage` (#207): the plugin call needs a
/// platform channel and cannot run under `flutter test`, so tests inject a
/// fake of this type and drive [ImagePickerAttachmentSource] end to end.
typedef PickGalleryImage = Future<XFile?> Function({
  required ImageSource source,
  double? maxWidth,
  double? maxHeight,
  int? imageQuality,
});

/// Deletes the picked file once its bytes are read (issue #843). Injectable
/// so a test can observe the path deletion without touching the filesystem.
typedef DeletePickedFile = Future<void> Function(String path);

class ImagePickerAttachmentSource implements AttachmentSource {
  ImagePickerAttachmentSource({
    PickGalleryImage? pickGalleryImage,
    DeletePickedFile? deletePickedFile,
  })  : _pickGalleryImage = pickGalleryImage ?? _pickFromPlugin,
        _deletePickedFile = deletePickedFile ?? _deleteFromDisk;

  final PickGalleryImage _pickGalleryImage;
  final DeletePickedFile _deletePickedFile;

  /// The real plugin path. Never executed under `flutter test`.
  static Future<XFile?> _pickFromPlugin({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
  }) =>
      ImagePicker().pickImage(
        source: source,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        imageQuality: imageQuality,
      );

  /// The real deletion path (issue #843): the plugin left a re-encoded copy in
  /// the Android cache / iOS `NSTemporaryDirectory()`, so it is unlinked after
  /// the bytes are read — best-effort, never surfaced.
  static Future<void> _deleteFromDisk(String path) =>
      deleteFileBestEffort(File(path));

  @override
  Future<FeedbackAttachment?> pickImage() async {
    // maxWidth/maxHeight/imageQuality make the plugin downscale and
    // re-encode (to JPEG) in platform code, so the bytes that reach Dart are
    // already small and already a supported format (#207).
    final file = await _pickGalleryImage(
      source: ImageSource.gallery,
      maxWidth: kMaxAttachmentImageEdge,
      maxHeight: kMaxAttachmentImageEdge,
      imageQuality: kAttachmentJpegQuality,
    );
    if (file == null) return null;
    try {
      // Reject an oversized pick *before* reading it (#207): `length()` stats
      // the file; the old code ran `readAsBytes()` unconditionally, so the
      // UI's too-large rejection had already cost the full read it exists to
      // avoid.
      if (await file.length() > kMaxAttachmentBytes) {
        throw const AttachmentTooLargeException();
      }
      final bytes = await file.readAsBytes();
      return FeedbackAttachment(
        bytes: bytes,
        // Issue #215: the name-based fallback mapping lives in
        // lib/domain/feedback/attachment_mime.dart
        // (attachmentMimeTypeFromFilename), directly unit-tested there.
        mimeType: file.mimeType ?? attachmentMimeTypeFromFilename(file.name),
        filename: file.name,
      );
    } finally {
      // Issue #843: the picked copy (accepted or rejected) is deleted here,
      // best-effort — a cleanup failure must never surface.
      try {
        await _deletePickedFile(file.path);
      } catch (_) {
        // Best effort only.
      }
    }
  }
}
