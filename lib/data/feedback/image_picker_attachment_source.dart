/// Thin adapter over the `image_picker` plugin (Issue #6, U7). Platform
/// concern, like `lib/data/auth/google_sign_in_client.dart`: the domain and
/// UI layers only ever see [AttachmentSource]/[FeedbackAttachment].
library;

import 'package:image_picker/image_picker.dart';
import 'package:lunarlog/domain/feedback/feedback_service.dart';

/// Production [AttachmentSource] over [ImagePicker]. Cannot run under
/// `flutter test` (no platform channel implementation), so it is excluded
/// from the coverage/CRAP gate in `tool/quality/exclusions.dart`; it holds
/// no branching logic worth testing in isolation.
class ImagePickerAttachmentSource implements AttachmentSource {
  ImagePickerAttachmentSource({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<FeedbackAttachment?> pickImage() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return FeedbackAttachment(
      bytes: bytes,
      mimeType: file.mimeType ?? _mimeTypeFromName(file.name),
      filename: file.name,
    );
  }

  String _mimeTypeFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'application/octet-stream';
  }
}
