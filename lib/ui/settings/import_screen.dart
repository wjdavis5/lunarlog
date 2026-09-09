/// Restore-from-file import screen (Issue #140): pick a file this app
/// exported -> preview what would change -> explicit confirm -> a result
/// summary. Pushed from `lib/ui/settings/your_data_section.dart`'s
/// "Import from file" tile via [kRouteImportScreen].
///
/// Every effectful collaborator is injectable (mirrors
/// `YourDataSection`'s `exportAccount` seam): [pickFile] defaults to the
/// real platform picker (`lib/data/import/import_file_picker.dart`, itself
/// excluded from the coverage gate — see that file's doc comment) and
/// [coordinator] defaults to a real [AccountImportCoordinator] built from
/// `Provider`-supplied repositories, so a widget test drives every state
/// (pick, parse error, preview, confirm, applying, result, apply error)
/// with fakes and never touches drift or a real file picker.
///
/// Parsing (`parseAccountImport`) and preview (`previewImport`) are pure
/// and run synchronously once bytes are in hand; only planning
/// ([AccountImportCoordinator.buildPlan], which reads the local store) and
/// applying ([AccountImportCoordinator.apply], the one Drift transaction)
/// are async — see `lib/domain/import/account_import.dart` and
/// `lib/data/import/account_importer.dart` for the actual merge/write
/// logic. This screen only sequences those calls and renders their result;
/// every text/widget builder below stays small on purpose (a handful of
/// tiny helpers rather than one large conditional build method), matching
/// this repo's per-method complexity convention.
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/import/account_importer.dart';
import 'package:lunarlog/data/import/import_file_picker.dart';
import 'package:lunarlog/data/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/domain/import/account_import.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/components/inline_error.dart';
import 'package:provider/provider.dart';

/// One line, no raw exception text (mirrors
/// `export_account_collaborator.dart`'s `kAccountExportFailureCopy`).
const String kImportApplyFailureCopy =
    'Could not finish the import. Nothing was written — please try again.';

/// Shown on the preview step when [ImportPlan.sharesWithOtherGuardians] is
/// true (Issue #140 review, item 10): importing into a matched profile
/// writes rows straight to the local store, which the sync engine then
/// pushes to every other device signed onto that profile — a guardian who
/// didn't run the import still ends up with its rows.
const String kImportSharedProfileGuardianSentence =
    'One of these profiles has another guardian — the rows you import will '
    'sync to their device too.';

/// A file at or above this size is parsed off the UI isolate (via
/// [compute]) rather than inline (Issue #140 review, item 10): parsing is
/// pure CPU work (JSON decode + validation, no I/O), so for a large file it
/// can visibly block the UI thread; a small file isn't worth an isolate's
/// spin-up cost.
const int kImportComputeOffloadThresholdBytes = 2 * 1024 * 1024;

/// `$n $singular` or `$n $plural` (`n == 1` picks [singular]).
String _count(int n, String singular, String plural) =>
    '$n ${n == 1 ? singular : plural}';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, this.pickFile, this.coordinator});

  /// Reads the picked file's bytes; null means "not provided by the
  /// caller" (default [pickImportFile]). Injectable for tests.
  final ImportFileReader? pickFile;

  /// Plans and applies imports; null means "build the real one from
  /// `Provider`-supplied repositories" (see `_ImportScreenState._coordinator`).
  /// Injectable for tests.
  final AccountImportCoordinator? coordinator;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  String? _error;
  bool _busy = false;
  AccountImportDocument? _document;
  ImportPreview? _preview;
  ImportPlan? _plan;
  ImportPlanSummary? _result;

  AccountImportCoordinator _coordinator(BuildContext context) {
    final injected = widget.coordinator;
    if (injected != null) return injected;
    final storage = context.read<LunarLogStorage>();
    return AccountImportCoordinator(
      profilesRepository: context.read<ProfilesRepository>(),
      dayEntriesRepository: context.read<DayEntriesRepository>(),
      observationsRepository: context.read<ObservationsRepository>(),
      storage: storage,
      guardiansForProfile: ProfileGuardiansRepository(storage).getForProfile,
      currentUserId: Provider.of<AuthController?>(context, listen: false)
          ?.currentUserId,
    );
  }

  Future<void> _pickAndPlan() async {
    setState(() => _error = null);
    try {
      final reader = widget.pickFile ?? pickImportFile;
      final bytes = await reader();
      if (bytes == null || !mounted) return;
      final parsed = await _parse(bytes);
      // A second `mounted` re-check (`_parse` is itself an `await` gap,
      // possibly a whole extra isolate round trip for a large file) before
      // this switch ever reads `context` below.
      if (!mounted) return;
      switch (parsed) {
        case AccountImportParseFailed(:final error):
          setState(() => _error = error.message);
        case AccountImportParsed(:final document):
          // Only reached (and only reads `context` here) once bytes were
          // actually picked and this state is still mounted — cancelling
          // the picker never needs a coordinator at all, and an
          // unconfigured build (no `Provider<LunarLogStorage>`, e.g. a
          // test that only exercises the pick/cancel step) never sees
          // this line run.
          await _buildPlan(_coordinator(context), document);
      }
    } catch (error) {
      // Issue #140 review, item 3: `parseAccountImport` itself now rejects
      // every malformed shape it knows about with a typed
      // `AccountImportParseFailed` rather than a raw `TypeError` (see that
      // function's own doc comment) — this is a last-resort backstop for
      // anything else a bad file or a picker failure could still throw,
      // so this screen never surfaces an unhandled exception instead of
      // `InlineError`.
      debugPrint('lunarlog import: pick/parse failed (${error.runtimeType})');
      if (mounted) setState(() => _error = kImportApplyFailureCopy);
    }
  }

  /// Parses [bytes] inline, or off the UI isolate via [compute] once the
  /// file is large enough that the pure CPU work of decoding/validating it
  /// could visibly block the UI thread (Issue #140 review, item 10; see
  /// [kImportComputeOffloadThresholdBytes]).
  Future<AccountImportParseResult> _parse(Uint8List bytes) =>
      bytes.length >= kImportComputeOffloadThresholdBytes
          ? compute(parseAccountImport, bytes)
          : Future.value(parseAccountImport(bytes));

  Future<void> _buildPlan(
    AccountImportCoordinator coordinator,
    AccountImportDocument document,
  ) async {
    setState(() => _busy = true);
    try {
      final plan = await coordinator.buildPlan(document);
      if (!mounted) return;
      setState(() {
        _document = document;
        _preview = previewImport(document);
        _plan = plan;
      });
    } catch (error) {
      debugPrint('lunarlog import: planning failed (${error.runtimeType})');
      if (mounted) setState(() => _error = kImportApplyFailureCopy);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final plan = _plan;
    if (plan == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final summary = await _coordinator(context).apply(plan);
      if (mounted) setState(() => _result = summary);
    } catch (error) {
      debugPrint('lunarlog import: apply failed (${error.runtimeType})');
      if (mounted) setState(() => _error = kImportApplyFailureCopy);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reset() {
    setState(() {
      _error = null;
      _document = null;
      _preview = null;
      _plan = null;
      _result = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    if (result != null) return _resultScaffold(context, result);
    final document = _document;
    final plan = _plan;
    if (document != null && plan != null) {
      return _previewScaffold(context, _preview!, plan);
    }
    return _pickScaffold(context);
  }

  Scaffold _scaffold(Widget body) => Scaffold(
        appBar: AppBar(title: const Text('Import from file')),
        body: SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: body)),
      );

  Widget _busyOrLabel(String label) => _busy
      ? const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : Text(label);

  Widget _skippedList(Key key, List<SkippedProfileReason> skipped) {
    if (skipped.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        key: key,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final s in skipped) Text('${s.displayName}: ${s.reason}')],
      ),
    );
  }

  Scaffold _pickScaffold(BuildContext context) {
    final error = _error;
    return _scaffold(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Choose a JSON file this app exported (Settings > Your data > '
          'Export my data). Your profiles and day entries are added to '
          'this device — nothing already here is ever deleted.',
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          key: const ValueKey('import-pick-button'),
          onPressed: _busy ? null : _pickAndPlan,
          child: _busyOrLabel('Choose file'),
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          InlineError(key: const ValueKey('import-pick-error'), message: error),
        ],
      ],
    ));
  }

  String _previewSummaryText(ImportPreview preview) =>
      '${_count(preview.profileCount, 'profile', 'profiles')}, '
      '${_count(preview.entryCount, 'day entry', 'day entries')}, '
      '${_count(preview.observationCount, 'observation', 'observations')}'
      '${_dateRangeSuffix(preview)}';

  String _dateRangeSuffix(ImportPreview preview) {
    final earliest = preview.earliestDate;
    final latest = preview.latestDate;
    if (earliest == null || latest == null) return '';
    return ' (${earliest.iso} to ${latest.iso})';
  }

  String _planSummaryText(ImportPlanSummary summary) =>
      '${_count(summary.profilesCreated, 'new profile', 'new profiles')}, '
      '${_count(summary.profilesMatched, 'matched profile', 'matched profiles')} '
      '(${summary.entriesAdded} entries added, ${summary.entriesMerged} merged).';

  Scaffold _previewScaffold(
    BuildContext context,
    ImportPreview preview,
    ImportPlan plan,
  ) {
    final summary = plan.summary;
    final error = _error;
    return _scaffold(SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_previewSummaryText(preview),
              key: const ValueKey('import-preview-summary')),
          const SizedBox(height: 8),
          const Text(kImportMergePolicySentence,
              key: ValueKey('import-preview-policy')),
          const SizedBox(height: 8),
          Text(_planSummaryText(summary),
              key: const ValueKey('import-preview-plan')),
          _skippedList(const ValueKey('import-preview-skipped'), summary.skippedProfiles),
          if (plan.sharesWithOtherGuardians) ...[
            const SizedBox(height: 8),
            const Text(kImportSharedProfileGuardianSentence,
                key: ValueKey('import-preview-shared-guardian')),
          ],
          if (error != null) ...[
            const SizedBox(height: 8),
            InlineError(
                key: const ValueKey('import-preview-error'), message: error),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton(
                key: const ValueKey('import-preview-cancel'),
                onPressed: _busy ? null : _reset,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                key: const ValueKey('import-preview-confirm'),
                onPressed: _busy ? null : _confirm,
                child: _busyOrLabel('Import'),
              ),
            ],
          ),
        ],
      ),
    ));
  }

  String _resultSummaryText(ImportPlanSummary summary) =>
      'Import complete: '
      '${_count(summary.profilesCreated, 'profile', 'profiles')} created, '
      '${summary.profilesMatched} matched, '
      '${summary.entriesAdded} entries added, ${summary.entriesMerged} merged, '
      '${summary.observationsAdded} observations added, '
      '${summary.observationsSkipped} skipped'
      '${_notesDiscardedSuffix(summary)}.';

  /// Issue #140 review, item 9: report honesty — a merged entry can keep
  /// the device's own note over the file's, and `entriesMerged` alone
  /// doesn't say so.
  String _notesDiscardedSuffix(ImportPlanSummary summary) =>
      summary.notesDiscarded == 0
          ? ''
          : ', ${_count(summary.notesDiscarded, 'file note', 'file notes')} '
              'not applied (an existing note was kept)';

  Scaffold _resultScaffold(BuildContext context, ImportPlanSummary summary) {
    return _scaffold(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_resultSummaryText(summary),
            key: const ValueKey('import-result-summary')),
        _skippedList(const ValueKey('import-result-skipped'), summary.skippedProfiles),
        const SizedBox(height: 16),
        ElevatedButton(
          key: const ValueKey('import-result-done'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    ));
  }
}
