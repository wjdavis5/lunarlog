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
import 'package:lunarlog/domain/import/account_import.dart';
import 'package:lunarlog/domain/import/account_import_coordinator.dart';
import 'package:lunarlog/domain/import/clue/clue_import_run.dart';
import 'package:lunarlog/domain/import/clue/clue_zip_reader.dart'
    show looksLikeZipArchive;
import 'package:lunarlog/domain/import/import_file_cap.dart' show ImportFileTooLargeException;
import 'package:lunarlog/domain/import/import_file_reader.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/util/timezone.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/components/inline_error.dart';
import 'package:provider/provider.dart';

/// One line, no raw exception text (mirrors
/// `export_account_collaborator.dart`'s `kAccountExportFailureCopy`).
const String kImportApplyFailureCopy =
    'Could not finish the import. Nothing was written — please try again.';

/// Shown when [StaleImportPlanException] aborts a confirm (Issue #140
/// review, LLA-085): distinct from [kImportApplyFailureCopy] because
/// retrying with the SAME plan would just fail the same way again — the
/// screen resets to the pick step instead so a fresh [_buildPlan] rebuilds
/// against the now-current state.
const String kImportStalePlanCopy =
    'Your data changed while this was open. Please choose the file again '
    'to include the latest changes.';

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

/// The `compute`-shaped seam [defaultClueImportPrepare] sends a large zip's
/// prepare through (issue #795). Production uses [_isolateCluePrepare];
/// a test injects a recorder so the offload branch is provable without
/// spinning up (and waiting on) a real isolate.
typedef CluePrepareOffload = Future<CluePrepareResult> Function(
  CluePrepareRequest request,
);

/// The production offload: [prepareClueImportResult] is a top-level function
/// and [CluePrepareRequest] is a sendable value, so the whole
/// extraction/SHA-256/JSON-parse body runs on a worker isolate.
Future<CluePrepareResult> _isolateCluePrepare(CluePrepareRequest request) =>
    compute(prepareClueImportResult, request);

/// Runs a Clue prepare inline for a small zip, or off the UI isolate via
/// [compute] once [kImportComputeOffloadThresholdBytes] is reached — the
/// same threshold and shape [_parse] uses for the JSON path (issue #795).
/// The Clue path's zip extraction, SHA-256, and JSON parse are pure CPU
/// work big enough to stall a frame on a real export, so it reuses the
/// established seam rather than inventing a second threshold. The result
/// is a typed [CluePrepareResult], never a thrown exception, so a typed
/// failure crosses the isolate boundary intact.
Future<CluePrepareResult> defaultClueImportPrepare(
  CluePrepareRequest request, {
  CluePrepareOffload offload = _isolateCluePrepare,
}) {
  if (request.zipBytes.length >= kImportComputeOffloadThresholdBytes) {
    return offload(request);
  }
  return Future.value(prepareClueImportResult(request));
}

/// Shown when a picked `.zip` cannot be read as a Clue export — a wrong
/// password, a corrupt archive, or a ZIP that simply is not Clue's (Issue
/// #452). One honest sentence; the raw [ClueZipException] message is never
/// rendered.
const String kClueImportReadFailureCopy =
    'Could not read that Clue export. Check the file and the password '
    'from your export email, then try again.';

/// Shown when a picked ZIP opens but does not contain Clue's
/// `measurements.json` — a ZIP from somewhere else, not a Clue export
/// (Issue #452).
const String kClueImportNotClueCopy =
    'That ZIP is not a Clue export. Choose the .zip file Clue emailed you.';

/// Shown when a Clue export was read and previewed but the write itself
/// failed (Issue #452). Mirrors [kImportApplyFailureCopy]: the importer's
/// transaction is all-or-nothing, so nothing was written.
const String kClueImportApplyFailureCopy =
    'Could not finish the Clue import. Nothing was written — please try '
    'again.';

/// The default name offered when a Clue import has no existing profile to
/// write into (a first-run restore). Editable, so the operator — not this
/// screen — decides what the imported profile is called.
const String kClueImportedProfileDefaultName = 'Imported from Clue';

/// Merge disclosure for the Clue preview step (Issue #452): unlike the
/// JSON path, a Clue import writes into one chosen profile and never
/// creates/removes any other.
const String kClueImportMergePolicySentence =
    'Nothing already on this device is deleted. Day entries and '
    'observations are added to the profile you choose.';

/// `$n $singular` or `$n $plural` (`n == 1` picks [singular]).
String _count(int n, String singular, String plural) =>
    '$n ${n == 1 ? singular : plural}';

class ImportScreen extends StatefulWidget {
  const ImportScreen({
    super.key,
    this.pickFile,
    this.coordinator,
    this.clueRunner,
    this.profilesRepository,
  });

  /// Reads the picked file's bytes; null means "not provided by the
  /// caller" (default: the tree-provided [ImportFileReader]). Injectable
  /// for tests, which pass an [ImportFileReader] implementation.
  final ImportFileReader? pickFile;

  /// Plans and applies imports; null means "read the tree-provided
  /// [AccountImportCoordinator]" (see `_ImportScreenState._coordinator`).
  /// Injectable for tests.
  final AccountImportCoordinator? coordinator;

  /// Writes a prepared Clue export (Issue #452); null means "read the
  /// tree-provided [ClueImportRunner]". Injectable for tests.
  final ClueImportRunner? clueRunner;

  /// Lists/creates the profile a Clue import targets (Issue #452); null
  /// means "read the tree-provided [ProfilesRepository]". Injectable so the
  /// JSON path's tests never need a provider tree for it.
  final ProfilesRepository? profilesRepository;

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

  /// The picked Clue zip's bytes, non-null only while the Clue path is
  /// active (Issue #452).
  Uint8List? _clueZipBytes;

  /// The decrypted/parsed Clue export, once its password was accepted.
  ClueImportPreview? _cluePreview;

  /// The applied Clue summary shown on the result step.
  ClueImportSummary? _clueResult;

  /// Live profiles offered as the Clue import's target.
  List<Profile> _clueProfiles = const [];

  /// The chosen existing target profile id, or null to create a new one.
  String? _clueProfileId;

  final TextEditingController _cluePassword = TextEditingController();
  final TextEditingController _clueProfileName =
      TextEditingController(text: kClueImportedProfileDefaultName);

  @override
  void dispose() {
    _cluePassword.dispose();
    _clueProfileName.dispose();
    super.dispose();
  }

  AccountImportCoordinator _coordinator(BuildContext context) {
    final injected = widget.coordinator;
    if (injected != null) return injected;
    return context.read<AccountImportCoordinator>();
  }

  ClueImportRunner _clueRunner(BuildContext context) {
    final injected = widget.clueRunner;
    if (injected != null) return injected;
    return context.read<ClueImportRunner>();
  }

  ProfilesRepository _profilesRepository(BuildContext context) {
    final injected = widget.profilesRepository;
    if (injected != null) return injected;
    return context.read<ProfilesRepository>();
  }

  Future<void> _pickAndPlan() async {
    setState(() => _error = null);
    try {
      final bytes = await _readPickedFileCapped();
      if (bytes == null || !mounted) return;
      if (looksLikeZipArchive(bytes)) {
        // Issue #452: a ZIP is a Clue export (or an honest failure). Hold
        // its bytes and ask for the export password before parsing.
        setState(() {
          _clueZipBytes = bytes;
          _cluePreview = null;
          _clueResult = null;
        });
        return;
      }
      final parsed = await _parse(bytes);
      // A second `mounted` re-check (`_parse` is itself an `await` gap,
      // possibly a whole extra isolate round trip for a large file) before
      // this switch ever reads `context` below.
      if (!mounted) return;
      switch (parsed) {
        case AccountImportParseFailed(:final error):
          _showImportError(error.message);
        case AccountImportParsed(:final document):
          // Only reached (and only reads `context` here) once bytes were
          // actually picked and this state is still mounted — cancelling
          // the picker never needs a coordinator at all, and a test that
          // only exercises the pick/cancel step injects its own
          // coordinator and never sees this line run.
          await _buildPlan(_coordinator(context), document);
      }
    } catch (error) {
      // Issue #140 review, item 3: `parseAccountImport` itself now rejects
      // every malformed shape it knows about with a typed
      // `AccountImportParseFailed` rather than a raw `TypeError` (see that
      // function's own doc comment) — this is a last-resort backstop for
      // anything else a bad file or a picker failure could still throw,
      // so this screen never surfaces an unhandled exception instead of
      // `InlineError`. [ImportFileTooLargeException] never reaches here —
      // [_readPickedFileCapped] catches it distinctly (Issue #626,
      // LLA-089's size cap is a picker-only failure mode, never something
      // `_parse`/`_buildPlan` below could throw).
      debugPrint('lunarlog import: pick/parse failed (${error.runtimeType})');
      _showImportError(kImportApplyFailureCopy);
    }
  }

  /// Reads the picked file's bytes via the injected/tree-provided
  /// [ImportFileReader] (Issue #626, LLA-089's stream-capped picker). Null
  /// means either the operator cancelled the picker, or the file was
  /// rejected as too large — the latter already shows the friendly
  /// [ImportFileTooLargeException.message] via [_showImportError] before
  /// returning, so [_pickAndPlan] only ever has to check for null, not
  /// which of the two happened.
  Future<Uint8List?> _readPickedFileCapped() async {
    final read = widget.pickFile?.read ?? context.read<ImportFileReader>().read;
    try {
      return await read();
    } on ImportFileTooLargeException catch (error) {
      // Issue #626, LLA-089: the picker now rejects an oversized file
      // before reading it into memory at all, via a typed exception rather
      // than `parseAccountImport`'s own post-hoc `bytes.length` check — the
      // operator still sees the identical friendly copy either way
      // ([ImportFileTooLargeException.message] is the same sentence).
      debugPrint('lunarlog import: picked file exceeds the size cap');
      _showImportError(error.message);
      return null;
    }
  }

  /// Shows [message] as the pick step's inline error, mounted-guarded like
  /// every other `setState` this screen makes from inside an `await` gap.
  void _showImportError(String message) {
    if (mounted) setState(() => _error = message);
  }

  /// Parses [bytes] inline, or off the UI isolate via [compute] once the
  /// file is large enough that the pure CPU work of decoding/validating it
  /// could visibly block the UI thread (Issue #140 review, item 10; see
  /// [kImportComputeOffloadThresholdBytes]).
  Future<AccountImportParseResult> _parse(Uint8List bytes) =>
      bytes.length >= kImportComputeOffloadThresholdBytes
          ? compute(parseAccountImport, bytes)
          : Future.value(parseAccountImport(bytes));

  // ---------------------------------------------------------------------
  // Clue export path (Issue #452).
  // ---------------------------------------------------------------------

  /// Decrypts/parses the held Clue zip with the entered password and loads
  /// the profiles it could write into. The heavy work goes through
  /// [defaultClueImportPrepare] — off the UI isolate for a large export
  /// (issue #795) — and comes back as a typed [CluePrepareResult], so this
  /// screen maps a typed failure to honest copy rather than substring-
  /// matching an exception's English message.
  Future<void> _prepareClue() async {
    final bytes = _clueZipBytes;
    if (bytes == null || _busy) return;
    final repository = _profilesRepository(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await defaultClueImportPrepare(
        CluePrepareRequest(zipBytes: bytes, password: _cluePassword.text),
      );
      await _handleCluePrepareResult(repository, result);
    } catch (error) {
      debugPrint('lunarlog import: clue read failed (${error.runtimeType})');
      _showImportError(kClueImportReadFailureCopy);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Applies a typed [CluePrepareResult] (issue #795): a prepared preview
  /// loads the writable profiles and moves to the preview step; a typed
  /// failure shows its honest copy. Split out of [_prepareClue] so that
  /// method's own branching stays inside the CRAP gate.
  Future<void> _handleCluePrepareResult(
    ProfilesRepository repository,
    CluePrepareResult result,
  ) async {
    switch (result) {
      case CluePrepared(:final preview):
        final profiles = await repository.list();
        if (!mounted) return;
        setState(() {
          _cluePreview = preview;
          _clueProfiles = profiles;
          _clueProfileId = profiles.isEmpty ? null : profiles.first.id;
        });
      case CluePrepareFailed(:final failure):
        _showImportError(_clueReadFailureMessage(failure));
    }
  }

  /// The honest copy for a typed Clue prepare failure (issue #795): a ZIP
  /// without `measurements.json` is not a Clue export; everything else
  /// (wrong password, corrupt archive, malformed entry) is the retry copy.
  String _clueReadFailureMessage(CluePrepareFailure failure) =>
      switch (failure) {
        CluePrepareFailure.entryNotFound => kClueImportNotClueCopy,
        CluePrepareFailure.unreadable ||
        CluePrepareFailure.malformed =>
          kClueImportReadFailureCopy,
      };

  /// Applies the prepared Clue preview to the chosen/created profile.
  Future<void> _confirmClue() async {
    final preview = _cluePreview;
    if (preview == null || _busy) return;
    final runner = _clueRunner(context);
    final repository = _profilesRepository(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final profileId = await _resolveClueProfileId(repository);
      final summary = await runner.run(
        profileId: profileId,
        tz: resolveCurrentTimeZoneSync(),
        parseResult: preview.parseResult,
        fileChecksum: preview.fileChecksum,
      );
      if (mounted) setState(() => _clueResult = summary);
    } catch (error) {
      debugPrint('lunarlog import: clue apply failed (${error.runtimeType})');
      if (mounted) setState(() => _error = kClueImportApplyFailureCopy);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The Clue import target: the selected live profile, or a newly created
  /// one named from the text field (the first-run case, where no profile
  /// exists yet). Additive either way — [ClueImportRunner] never deletes.
  ///
  /// Defect #791: a created profile's id is recorded in [_clueProfileId]
  /// before [ClueImportRunner.run] is called, so a failed run (whose
  /// transaction rolls back its writes but not this profile, created
  /// outside it) leaves exactly one empty profile and every retry reuses
  /// it instead of orphaning another.
  Future<String> _resolveClueProfileId(ProfilesRepository repository) async {
    final selected = _clueProfileId;
    if (selected != null) return selected;
    final name = _clueProfileName.text.trim();
    final profile = await repository.create(
      displayName: name.isEmpty ? kClueImportedProfileDefaultName : name,
      isMinor: false,
    );
    _clueProfileId = profile.id;
    return profile.id;
  }

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
    } on StaleImportPlanException {
      // Issue #140 review, LLA-085: back to the pick step entirely, not
      // just clearing `_plan` — `_document`/`_preview` were built from the
      // same now-stale read, and a fresh pick re-parses and re-plans
      // against current state end to end.
      debugPrint('lunarlog import: apply aborted, stale plan');
      if (mounted) {
        setState(() {
          _document = null;
          _preview = null;
          _plan = null;
          _error = kImportStalePlanCopy;
        });
      }
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
      _clueZipBytes = null;
      _cluePreview = null;
      _clueResult = null;
      _clueProfiles = const [];
      _clueProfileId = null;
      _cluePassword.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final clueResult = _clueResult;
    if (clueResult != null) return _clueResultScaffold(context, clueResult);
    final cluePreview = _cluePreview;
    if (cluePreview != null) return _cluePreviewScaffold(context, cluePreview);
    if (_clueZipBytes != null) return _cluePasswordScaffold(context);
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
        appBar: AppBar(
          title: Text(AppLocalizations.of(context).importScreenTitle),
        ),
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
    final l10n = AppLocalizations.of(context);
    return _scaffold(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.importScreenPickBody),
        const SizedBox(height: 16),
        ElevatedButton(
          key: const ValueKey('import-pick-button'),
          onPressed: _busy ? null : _pickAndPlan,
          child: _busyOrLabel(l10n.importScreenChooseFileAction),
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          InlineError(key: const ValueKey('import-pick-error'), message: error),
        ],
      ],
    ));
  }

  // ---------------------------------------------------------------------
  // Clue export path scaffolds (Issue #452).
  // ---------------------------------------------------------------------

  Scaffold _cluePasswordScaffold(BuildContext context) {
    final error = _error;
    final l10n = AppLocalizations.of(context);
    return _scaffold(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.importCluePasswordPrompt),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('clue-password-field'),
          controller: _cluePassword,
          obscureText: true,
          decoration:
              InputDecoration(labelText: l10n.importClueExportPasswordLabel),
          onSubmitted: (_) => _prepareClue(),
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          InlineError(
              key: const ValueKey('clue-password-error'), message: error),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            TextButton(
              key: const ValueKey('clue-password-cancel'),
              onPressed: _busy ? null : _reset,
              child: Text(l10n.importClueCancel),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              key: const ValueKey('clue-password-continue'),
              onPressed: _busy ? null : _prepareClue,
              child: _busyOrLabel(l10n.importClueOpenExport),
            ),
          ],
        ),
      ],
    ));
  }

  String _cluePreviewSummaryText(ClueImportSummary summary) =>
      'Ready to import: ${_count(summary.dayCount, 'day', 'days')}, '
      '${_count(summary.datapointCount, 'datapoint', 'datapoints')}.';

  /// The target selector: a dropdown of live profiles, or — when none exist
  /// (a first-run restore) — an editable name for the profile this import
  /// creates.
  Widget _clueTargetSelector(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_clueProfiles.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.importClueNewProfileNote),
          TextField(
            key: const ValueKey('clue-new-profile-name'),
            controller: _clueProfileName,
            decoration: InputDecoration(labelText: l10n.importClueProfileNameLabel),
          ),
        ],
      );
    }
    return DropdownButton<String>(
      key: const ValueKey('clue-profile-dropdown'),
      value: _clueProfileId,
      isExpanded: true,
      onChanged: (value) => setState(() => _clueProfileId = value ?? _clueProfileId),
      items: [
        for (final profile in _clueProfiles)
          DropdownMenuItem<String>(
            value: profile.id,
            child: Text(profile.displayName),
          ),
      ],
    );
  }

  Widget _clueSummaryLines(Key key, ClueImportSummary summary) => Column(
        key: key,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in summary.summaryLines) Text(line),
        ],
      );

  Scaffold _cluePreviewScaffold(
    BuildContext context,
    ClueImportPreview preview,
  ) {
    final error = _error;
    final l10n = AppLocalizations.of(context);
    return _scaffold(SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_cluePreviewSummaryText(preview.summary),
              key: const ValueKey('clue-preview-summary')),
          const SizedBox(height: 8),
          const Text(kClueImportMergePolicySentence,
              key: ValueKey('clue-preview-policy')),
          const SizedBox(height: 8),
          _clueTargetSelector(context),
          const SizedBox(height: 8),
          _clueSummaryLines(
              const ValueKey('clue-preview-summary-lines'), preview.summary),
          if (error != null) ...[
            const SizedBox(height: 8),
            InlineError(
                key: const ValueKey('clue-preview-error'), message: error),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton(
                key: const ValueKey('clue-preview-cancel'),
                onPressed: _busy ? null : _reset,
                child: Text(l10n.importClueCancel),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                key: const ValueKey('clue-preview-confirm'),
                onPressed: _busy ? null : _confirmClue,
                child: _busyOrLabel(l10n.importClueImport),
              ),
            ],
          ),
        ],
      ),
    ));
  }

  Scaffold _clueResultScaffold(
    BuildContext context,
    ClueImportSummary summary,
  ) {
    final l10n = AppLocalizations.of(context);
    return _scaffold(SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _clueSummaryLines(const ValueKey('clue-result-summary'), summary),
          const SizedBox(height: 16),
          ElevatedButton(
            key: const ValueKey('clue-result-done'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.importClueDone),
          ),
        ],
      ),
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

  /// Issue #925: the preview's warning for day entries the plan will drop
  /// because their date is out of bounds — shown before the user commits so
  /// the count the preview otherwise reports ("3 day entries") is not a
  /// silent overstatement. Null when nothing was rejected.
  String? _entryDatesRejectedPreview(
    AppLocalizations l10n,
    ImportPlanSummary summary,
  ) {
    final count = summary.entryDatesRejected;
    if (count == 0) return null;
    return l10n.importEntryDatesRejectedPreview(
      count,
      _rejectionReasons(l10n, summary),
    );
  }

  /// Issue #925: "1 more than a day in the future and 2 before the birth
  /// year", naming only the non-zero rules. The two reasons have different
  /// fixes, so both are named when both occurred.
  String _rejectionReasons(AppLocalizations l10n, ImportPlanSummary summary) {
    final future = summary.entryDatesRejectedFuture;
    final before = summary.entryDatesRejectedBeforeBirthYear;
    if (future > 0 && before > 0) {
      return l10n.importEntryDatesRejectionReasonsJoin(
        l10n.importEntryDatesRejectionFuture(future),
        l10n.importEntryDatesRejectionBeforeBirthYear(before),
      );
    }
    if (future > 0) return l10n.importEntryDatesRejectionFuture(future);
    return l10n.importEntryDatesRejectionBeforeBirthYear(before);
  }

  Scaffold _previewScaffold(
    BuildContext context,
    ImportPreview preview,
    ImportPlan plan,
  ) {
    final summary = plan.summary;
    final error = _error;
    final l10n = AppLocalizations.of(context);
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
          if (_entryDatesRejectedPreview(l10n, summary) case final warning?) ...[
            const SizedBox(height: 8),
            Text(warning, key: const ValueKey('import-preview-rejected')),
          ],
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
                child: Text(AppLocalizations.of(context).importScreenCancel),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                key: const ValueKey('import-preview-confirm'),
                onPressed: _busy ? null : _confirm,
                child: _busyOrLabel(
                  AppLocalizations.of(context).importScreenImportAction,
                ),
              ),
            ],
          ),
        ],
      ),
    ));
  }

  String _resultSummaryText(AppLocalizations l10n, ImportPlanSummary summary) =>
      'Import complete: '
      '${_count(summary.profilesCreated, 'profile', 'profiles')} created, '
      '${summary.profilesMatched} matched, '
      '${summary.entriesAdded} entries added, ${summary.entriesMerged} merged, '
      '${summary.observationsAdded} observations added, '
      '${summary.observationsSkipped} skipped'
      '${_entryDatesRejectedSuffix(l10n, summary)}'
      '${_notesDiscardedSuffix(summary)}.';

  /// Issue #925: a restore whose file carried out-of-bounds dates drops them,
  /// and the bare result line's "0 skipped" (observations) otherwise reads as
  /// though nothing was. This counts the rejected day entries in the same
  /// sentence as the other outcomes, naming the reason(s) — omitted entirely
  /// when nothing was rejected, so a clean import reads exactly as before.
  String _entryDatesRejectedSuffix(
    AppLocalizations l10n,
    ImportPlanSummary summary,
  ) =>
      summary.entryDatesRejected == 0
          ? ''
          : ', ${l10n.importEntryDatesRejectedResult(
              summary.entryDatesRejected,
              _rejectionReasons(l10n, summary),
            )}';

  /// Issue #140 review, item 9: report honesty — a merged entry can keep
  /// the device's own note over the file's, and `entriesMerged` alone
  /// doesn't say so.
  String _notesDiscardedSuffix(ImportPlanSummary summary) =>
      summary.notesDiscarded == 0
          ? ''
          : ', ${_count(summary.notesDiscarded, 'file note', 'file notes')} '
              'not applied (an existing note was kept)';

  Scaffold _resultScaffold(BuildContext context, ImportPlanSummary summary) {
    final l10n = AppLocalizations.of(context);
    return _scaffold(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_resultSummaryText(l10n, summary),
            key: const ValueKey('import-result-summary')),
        _skippedList(const ValueKey('import-result-skipped'), summary.skippedProfiles),
        const SizedBox(height: 16),
        ElevatedButton(
          key: const ValueKey('import-result-done'),
          onPressed: () => Navigator.of(context).pop(summary),
          child: Text(AppLocalizations.of(context).importScreenDone),
        ),
      ],
    ));
  }
}
