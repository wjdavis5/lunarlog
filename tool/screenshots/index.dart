/// The JSON index the screenshot run emits next to the PNGs (issue
/// #1104): one entry per rendered (screen, device, theme) triple,
/// recording the screen id, device size, theme, app version, and commit
/// — everything the site build (and a later store-listing upload) needs
/// to pick a PNG without parsing filenames.
///
/// Pure and deterministic: the same inputs produce a byte-identical
/// string, entries sorted by (screen, device, theme), stable 2-space
/// indentation, no timestamps.
library;

import 'dart:convert';

import 'manifest.dart';

/// One rendered screenshot's index record.
class ScreenshotIndexEntry {
  const ScreenshotIndexEntry({
    required this.screenId,
    required this.deviceId,
    required this.theme,
    required this.file,
    required this.width,
    required this.height,
    required this.storePixelSize,
  });

  final String screenId;
  final String deviceId;
  final ScreenshotTheme theme;

  /// PNG filename, relative to the index file's directory.
  final String file;

  /// PNG pixel dimensions (logical size x pixel ratio).
  final int width;
  final int height;

  /// The store listing size this PNG matches (from the device manifest).
  final (int, int) storePixelSize;

  Map<String, Object?> _toJson() => {
        'screen': screenId,
        'device': deviceId,
        'theme': theme.id,
        'file': file,
        'width': width,
        'height': height,
        'storeSize': '${storePixelSize.$1}x${storePixelSize.$2}',
      };
}

/// Builds the index document. [appVersion] is the pubspec version the
/// screenshots were rendered from; [commit] the commit they were rendered
/// at (the caller resolves both — the runner reads pubspec/`git`).
String buildIndexJson({
  required List<ScreenshotIndexEntry> entries,
  required String appVersion,
  required String commit,
}) {
  final sorted = [...entries]..sort((a, b) {
        final byScreen = a.screenId.compareTo(b.screenId);
        if (byScreen != 0) return byScreen;
        final byDevice = a.deviceId.compareTo(b.deviceId);
        if (byDevice != 0) return byDevice;
        return a.theme.id.compareTo(b.theme.id);
      });
  final body = {
    'appVersion': appVersion,
    'commit': commit,
    'screens': [
      for (final e in sorted) e._toJson(),
    ],
  };
  return _prettyJson(body);
}

/// Deterministic 2-space JSON: `JsonEncoder.withIndent` sorts nothing but
/// map literals iterate in insertion order and the encoder escapes
/// identically every run — the sort above is what makes the entry order
/// stable regardless of render completion order.
String _prettyJson(Object? json) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(json);
}
