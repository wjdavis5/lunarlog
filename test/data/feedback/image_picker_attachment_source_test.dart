/// Regression tests for the image_picker attachment adapter (#207): the
/// downscale/normalisation parameters passed to the platform pick, the
/// pre-read size rejection, and the name-based mime fallback that turns a
/// null-mime `.heic` pick into a JPEG attachment instead of an
/// `application/octet-stream` rejection.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lunarlog/data/feedback/image_picker_attachment_source.dart';
import 'package:lunarlog/domain/feedback/feedback_service.dart';

/// A fake [XFile] whose `length()` answers from a stored value without any
/// filesystem access, and whose `readAsBytes()` is observable — the
/// oversized-rejection test proves the bytes are *never* read.
class FakePickedFile implements XFile {
  FakePickedFile({
    required this.name,
    this.mimeType,
    required this.sizeBytes,
    this.payload,
  });

  int readCalls = 0;

  /// The length [length] reports — the file's real size in the oversized
  /// case, never derived from [payload].
  final int sizeBytes;

  /// What [readAsBytes] serves; null simulates "the read never happened".
  final Uint8List? payload;

  @override
  final String name;

  @override
  final String? mimeType;

  @override
  Future<int> length() async => sizeBytes;

  @override
  Future<Uint8List> readAsBytes() async {
    readCalls++;
    return payload ?? Uint8List(0);
  }

  @override
  String get path => name;

  @override
  Future<void> saveTo(String path) => throw UnimplementedError();

  @override
  Future<String> readAsString({Encoding encoding = utf8}) =>
      throw UnimplementedError();

  @override
  Stream<Uint8List> openRead([int? start, int? end]) =>
      throw UnimplementedError();

  @override
  Future<DateTime> lastModified() => throw UnimplementedError();

  @override
  String toString() => 'FakePickedFile($name, length: $sizeBytes)';
}

/// Records what the adapter asks the platform to do.
class RecordingPicker {
  RecordingPicker(this.file);

  final XFile? file;
  int calls = 0;
  ImageSource? source;
  double? maxWidth;
  double? maxHeight;
  int? imageQuality;

  Future<XFile?> call({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
  }) {
    calls++;
    this.source = source;
    this.maxWidth = maxWidth;
    this.maxHeight = maxHeight;
    this.imageQuality = imageQuality;
    return Future.value(file);
  }
}

ImagePickerAttachmentSource sourceWith(RecordingPicker picker) =>
    ImagePickerAttachmentSource(pickGalleryImage: picker.call);

const int kCap = kMaxAttachmentBytes;

void main() {
  test('the platform pick is asked to downscale to a supported, small JPEG', () async {
    final picker = RecordingPicker(FakePickedFile(
      name: 'IMG_0001.jpg',
      mimeType: 'image/jpeg',
      sizeBytes: 1024,
      payload: Uint8List.fromList([1, 2, 3]),
    ));
    final attachment = await sourceWith(picker).pickImage();

    expect(picker.calls, 1);
    expect(picker.source, ImageSource.gallery);
    expect(picker.maxWidth, kMaxAttachmentImageEdge,
        reason: 'a 12 MP photo must be scaled before the bytes cross into Dart');
    expect(picker.maxHeight, kMaxAttachmentImageEdge);
    expect(picker.imageQuality, kAttachmentJpegQuality,
        reason: 'the quality parameter is what makes the plugin normalise '
            'the image to JPEG');
    expect(attachment, isNotNull);
  });

  test('an oversized pick is rejected before its bytes are ever read', () async {
    final picker = RecordingPicker(FakePickedFile(
      name: 'huge.png',
      mimeType: 'image/png',
      sizeBytes: kCap + 1,
    ));
    final source = sourceWith(picker);

    await expectLater(source.pickImage(), throwsA(isA<AttachmentTooLargeException>()));
    expect((picker.file! as FakePickedFile).readCalls, 0,
        reason: 'the rejection must happen on the file length, not after '
            'the full read (#207)');
  });

  test('a pick exactly at the cap is accepted (the check is strictly over)', () async {
    final bytes = Uint8List.fromList(List<int>.filled(64, 7));
    final picker = RecordingPicker(FakePickedFile(
      name: 'exact.png',
      mimeType: 'image/png',
      sizeBytes: kCap,
      payload: bytes,
    ));

    final attachment = await sourceWith(picker).pickImage();

    expect(attachment, isNotNull);
    expect(attachment!.sizeBytes, bytes.length);
    expect((picker.file! as FakePickedFile).readCalls, 1);
  });

  test('an iOS .heic pick with a null mimeType is accepted as a JPEG attachment',
      () async {
    final bytes = Uint8List.fromList(List<int>.filled(128, 9));
    final picker = RecordingPicker(FakePickedFile(
      name: 'IMG_0001.heic',
      mimeType: null,
      sizeBytes: bytes.length,
      payload: bytes,
    ));

    final attachment = await sourceWith(picker).pickImage();

    expect(attachment!.mimeType, 'image/jpeg',
        reason: 'with imageQuality passed the plugin has already re-encoded '
            'the image as JPEG; labelling it octet-stream made the UI reject '
            'the pick as an unsupported type');
    expect(attachment.filename, 'IMG_0001.heic');
    expect(attachment.bytes, bytes);
  });

  test('.heif maps the same way', () async {
    final picker = RecordingPicker(FakePickedFile(
      name: 'IMG_0002.HEIF',
      mimeType: null,
      sizeBytes: 128,
      payload: Uint8List.fromList(List<int>.filled(128, 9)),
    ));

    final attachment = await sourceWith(picker).pickImage();

    expect(attachment!.mimeType, 'image/jpeg');
  });

  test('a non-null mimeType wins over the name fallback', () async {
    final picker = RecordingPicker(FakePickedFile(
      name: 'photo.jpg',
      mimeType: 'image/png',
      sizeBytes: 32,
      payload: Uint8List(32),
    ));

    final attachment = await sourceWith(picker).pickImage();

    expect(attachment!.mimeType, 'image/png');
  });

  test('the name fallback keeps mapping the supported extensions, and only them',
      () async {
    final cases = {
      'shot.png': 'image/png',
      'shot.PNG': 'image/png',
      'shot.jpg': 'image/jpeg',
      'shot.jpeg': 'image/jpeg',
      'shot.webp': 'image/webp',
      'shot.gif': 'application/octet-stream',
      'shot': 'application/octet-stream',
    };
    for (final entry in cases.entries) {
      final picker = RecordingPicker(FakePickedFile(
        name: entry.key,
        mimeType: null,
        sizeBytes: 16,
        payload: Uint8List(16),
      ));
      final attachment = await sourceWith(picker).pickImage();
      expect(attachment!.mimeType, entry.value,
          reason: '${entry.key} should resolve to ${entry.value}');
    }
  });

  test('a cancelled pick returns null and never builds an attachment', () async {
    final picker = RecordingPicker(null);

    final attachment = await sourceWith(picker).pickImage();

    expect(attachment, isNull);
    expect(picker.calls, 1);
  });
}
