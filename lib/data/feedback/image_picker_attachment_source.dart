/// Thin adapter over the `image_picker` plugin (Issue #6, U7). Platform
/// concern, like `lib/data/auth/google_sign_in_client.dart`: the domain and
/// UI layers only ever see [AttachmentSource]/[FeedbackAttachment]. Only the
/// plugin call itself is untestable under `flutter test`; every decision
/// around it runs against the injected [PickGalleryImage] seam (see
/// `test/data/feedback/image_picker_attachment_source_test.dart`, #207).
library;

import 'package:image_picker/image_picker.dart';
import 'package:lunarlog/domain/feedback/feedback_service.dart';

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

class ImagePickerAttachmentSource implements AttachmentSource {
  ImagePickerAttachmentSource({PickGalleryImage? pickGalleryImage})
      : _pickGalleryImage = pickGalleryImage ?? _pickFromPlugin;

  final PickGalleryImage _pickGalleryImage;

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
      mimeType: file.mimeType ?? _mimeTypeFromName(file.name),
      filename: file.name,
    );
  }

  /// Name-based fallback for platforms whose [XFile.mimeType] comes back
  /// null. `.heic`/`.heif` map to `image/jpeg`, not `application/octet-stream`
  /// (#207): with [kAttachmentJpegQuality] passed, the plugin has already
  /// re-encoded the image as JPEG before the bytes cross into Dart, so an
  /// HEIC pick whose extension and null mime still say HEIC is a JPEG
  /// attachment — labelling it octet-stream made the UI reject it as an
  /// unsupported type with no way to comply from the gallery.
  String _mimeTypeFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/jpeg';
    return 'application/octet-stream';
  }
}
