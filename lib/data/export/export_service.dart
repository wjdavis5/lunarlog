/// Export delivery (U1; R13): builds the CSV, PDF summary, and JSON for the
/// selected profile, shares them through the system share sheet, and owns
/// the temp files end to end.
///
/// Temp files are deleted on completion, cancellation, AND failure: the
/// share call sits inside a `try/finally` whose cleanup swallows nothing it
/// must report (a cleanup failure is logged by type only) and never masks
/// the share's own outcome. Tombstones are excluded by the builders.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/repositories/day_entries_repository.dart';
import '../../domain/repositories/profiles_repository.dart';
import 'profile_export.dart';
import 'share_client.dart';

/// What went wrong while exporting. Fieldless by design (R18).
@immutable
sealed class ExportError implements Exception {
  const ExportError();

  const factory ExportError.noProfile() = ExportNoProfileError;

  const factory ExportError.io() = ExportIoError;

  const factory ExportError.shareFailed() = ExportShareFailedError;

  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// No live profile with the requested id exists (it was never created or
/// was tombstoned). Nothing was written or shared.
final class ExportNoProfileError extends ExportError {
  const ExportNoProfileError();

  @override
  String toString() => 'ExportError.noProfile';
}

/// A temp file could not be written. Nothing was shared.
final class ExportIoError extends ExportError {
  const ExportIoError();

  @override
  String toString() => 'ExportError.io';
}

/// The share sheet could not be shown or failed. The temp files were still
/// deleted.
final class ExportShareFailedError extends ExportError {
  const ExportShareFailedError();

  @override
  String toString() => 'ExportError.shareFailed';
}

/// Where the temp files are staged. Production passes
/// `getTemporaryDirectory` from `path_provider`.
typedef TempDirectoryProvider = Future<Directory> Function();

class ExportService {
  ExportService({
    required this.profiles,
    required this.dayEntries,
    required this.tempDirectory,
    required this.shareFiles,
    this.clock,
  });

  final ProfilesRepository profiles;
  final DayEntriesRepository dayEntries;
  final TempDirectoryProvider tempDirectory;
  final ShareFiles shareFiles;

  /// Stamps the temp file names. Injectable so tests assert exact paths.
  final DateTime Function()? clock;

  /// Builds and shares the three export files for [profileId]. Throws
  /// [ExportError].
  Future<void> exportProfile(String profileId) async {
    final profile = await profiles.findById(profileId);
    if (profile == null) {
      throw const ExportError.noProfile();
    }
    final entries = await dayEntries.listForProfile(profileId);
    final stamp = (clock?.call() ?? DateTime.now().toUtc())
        .toIso8601String()
        .replaceAll(':', '-');
    final dir = await tempDirectory();
    final base = 'lunarlog-export-$stamp';
    final files = <File>[
      File('${dir.path}${Platform.pathSeparator}$base.csv'),
      File('${dir.path}${Platform.pathSeparator}$base.pdf'),
      File('${dir.path}${Platform.pathSeparator}$base.json'),
    ];
    try {
      await files[0].writeAsString(buildExportCsv(profile, entries));
      await files[1].writeAsBytes(await buildExportPdf(profile, entries));
      await files[2].writeAsString(
          const JsonEncoder.withIndent('  ').convert(
            buildExportJson(profile, entries),
          ),
        );
    } on ExportError {
      rethrow;
    } catch (_) {
      await _deleteQuietly(files);
      throw const ExportError.io();
    }
    try {
      await shareFiles(
        [for (final file in files) XFile(file.path)],
        subject: 'LunarLog data export',
      );
    } catch (_) {
      throw const ExportError.shareFailed();
    } finally {
      await _deleteQuietly(files);
    }
  }

  /// Best-effort temp cleanup: failures are type-only (never paths, never
  /// content) and never mask the outcome they follow.
  Future<void> _deleteQuietly(List<File> files) async {
    for (final file in files) {
      try {
        if (await file.exists()) await file.delete();
      } catch (error) {
        debugPrint(
            'lunarlog export: temp cleanup failed (${error.runtimeType})');
      }
    }
  }
}
