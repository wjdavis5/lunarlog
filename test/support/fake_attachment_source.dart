/// Test double for the `AttachmentSource` domain contract (Issue #6, U7).
///
/// The real `ImagePickerAttachmentSource` (`lib/data/feedback/`) calls the
/// `image_picker` plugin, which cannot answer under `flutter test`; widget
/// tests provide this in the tree (or inject it through `FeedbackScreen`'s
/// own test seam) so `context.read<AttachmentSource>()` resolves.
library;

import 'package:lunarlog/domain/feedback/feedback_service.dart';

class FakeAttachmentSource implements AttachmentSource {
  FakeAttachmentSource({this.nextResult});

  FeedbackAttachment? nextResult;

  @override
  Future<FeedbackAttachment?> pickImage() async => nextResult;
}
