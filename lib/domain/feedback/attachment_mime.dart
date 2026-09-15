/// Attachment filename-to-MIME mapping (issue #215).
///
/// Extracted verbatim out of
/// `lib/data/feedback/image_picker_attachment_source.dart`'s private
/// `_mimeTypeFromName` so the mapping is a directly unit-tested pure
/// function in the domain layer, on the `buildFirebaseOptions()` precedent —
/// the adapter keeps only the plugin-bound pick itself.
library;

/// Name-based fallback MIME type for a picked gallery image whose
/// platform-reported `XFile.mimeType` came back null.
///
/// `.heic`/`.heif` map to `image/jpeg`, not `application/octet-stream`
/// (#207): the image_picker adapter passes `imageQuality`, which makes the
/// plugin re-encode the image as JPEG in platform code before the bytes
/// cross into Dart, so an HEIC pick whose extension and null mime still say
/// HEIC is a JPEG attachment — labelling it octet-stream made the UI reject
/// it as an unsupported type with no way to comply from the gallery.
String attachmentMimeTypeFromFilename(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/jpeg';
  return 'application/octet-stream';
}
