/// Settings "Your data" section (Issue #222; source: B-17). Reachable
/// without a cloud account: renders whenever at least one profile exists on
/// this device and the platform is not web, independent of sign-in state.
///
/// "Export my data" used to live only inside `AccountSection`, gated
/// `if (signedIn && ...)` (Issue #17) - a user who declined the account
/// step at first run (an explicitly supported path, `first_run_screen.dart`
/// "Not now") had local-only data and no way to export it, even though the
/// underlying document (`lib/domain/export/account_export.dart`) never
/// actually needed an account; only that UI gate did. This section is that
/// fix: the tile moved here, above the Account section in
/// `settings_screen.dart`, and now renders for a signed-out operator too.
/// `AccountSection` keeps its own, independent use of the same
/// [ExportAccountCollaborator] seam for the delete-confirmation dialog's
/// "Export first" step - the two do not share any state. "Delete account"
/// stays in the Account section unchanged: it is inherently account-scoped
/// and does not belong here.
///
/// Not gated behind a fresh device-credential re-auth of its own: neither
/// was `AccountSection`'s pre-#222 export tile (only "Add"/"Remove" a
/// sign-in method and "Delete account" ever called
/// `GateController.reauthenticate` there) - reaching Settings at all
/// already sits behind the app's own lock, and this section changes nothing
/// about that.
///
/// Import (Issue #140) has no entry point here yet: a placeholder tile
/// wired to nothing would just be UI noise, so none is added. This
/// section's `build` is the reserved slot for it - another tile in the
/// same list, once #140 ships, with no restructuring needed.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/export/account_export_remote_source.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/export_account_collaborator.dart';
import 'package:lunarlog/ui/components/inline_error.dart';
import 'package:provider/provider.dart';

class YourDataSection extends StatefulWidget {
  const YourDataSection({
    super.key,
    this.showExport,
    this.exportAccount,
  });

  /// Whether "Export my data" may render at all; null means "not web"
  /// (matches `AccountSection`'s pre-#222 `showExportAndDelete` default -
  /// R11 never shipped either tile on web). Injectable so tests simulate
  /// web without actually running on it.
  final bool? showExport;

  /// Export collaborator; null means [defaultExportAccountCollaborator]
  /// (the real platform writer). Injectable so tests never touch
  /// `path_provider`/`share_plus`.
  final ExportAccountCollaborator? exportAccount;

  @override
  State<YourDataSection> createState() => _YourDataSectionState();
}

class _YourDataSectionState extends State<YourDataSection> {
  StreamSubscription<List<Profile>>? _profilesSub;
  List<Profile>? _profiles;
  bool _exporting = false;
  String? _exportError;

  bool get _canExport => widget.showExport ?? !kIsWeb;

  @override
  void initState() {
    super.initState();
    // Mirrors `SettingsScreen`'s own initState (a one-off `context.read`
    // for a Provider-injected singleton is safe here, unlike
    // `context.watch`/`Provider.of(listen: true)`): a nullable repository
    // means an unconfigured build (e.g. a test with none provided) simply
    // never sees any profiles, same as "no profiles yet".
    _profilesSub = context.read<ProfilesRepository?>()?.watch().listen(
      (profiles) {
        if (mounted) setState(() => _profiles = profiles);
      },
      onError: (Object error, StackTrace stackTrace) {
        // A broken profiles stream shouldn't surface as an unhandled zone
        // error; treat it like "no profiles yet" and hide the section.
        debugPrint('lunarlog your-data: profiles watch failed ($error)');
        if (mounted) setState(() => _profiles = null);
      },
    );
  }

  @override
  void dispose() {
    unawaited(_profilesSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profiles = _profiles;
    if (!_canExport || profiles == null || profiles.isEmpty) {
      return const SizedBox.shrink();
    }
    final auth = Provider.of<AuthController?>(context);
    // Matches `AccountSection._isSignedIn`: a `passwordRecovery` session
    // counts as signed in for rendering purposes here too, a pre-existing
    // soft bucket this section inherits rather than fixes.
    final signedIn = auth?.state == AuthSessionState.signedIn ||
        auth?.state == AuthSessionState.passwordRecovery;
    final theme = Theme.of(context);
    final exportError = _exportError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('Your data', style: theme.textTheme.titleSmall),
        ),
        ListTile(
          key: const ValueKey('your-data-export'),
          leading: const Icon(Icons.file_download_outlined),
          title: const Text('Export my data'),
          // Issue #222: the copy names the account's server data only when
          // signed in - a signed-out export is local-only (`serverIncluded:
          // false`, see `buildMergedAccountExport`) and must not claim more
          // than it delivers.
          subtitle: Text(
            signedIn
                ? 'Save your profiles and day entries as a JSON file, '
                    "including your account's server data."
                : 'Save your profiles and day entries as a JSON file.',
          ),
          enabled: !_exporting,
          trailing: _exporting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          onTap: !_exporting ? () => _export(context) : null,
        ),
        if (exportError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: InlineError(
              key: const ValueKey('your-data-export-error'),
              message: exportError,
            ),
          ),
        const Divider(),
      ],
    );
  }

  /// "Export my data" (mirrors `AccountSection`'s pre-#222 `_exportAccount`
  /// / `_runExport`, independently of that section's own collaborator):
  /// one export at a time, failures render as copy beneath the tile rather
  /// than an exception.
  Future<void> _export(BuildContext context) async {
    if (_exporting) return;
    setState(() {
      _exporting = true;
      _exportError = null;
    });
    try {
      final profilesRepo = context.read<ProfilesRepository>();
      final entriesRepo = context.read<DayEntriesRepository>();
      // Read before the first `await` below (not after -
      // `use_build_context_synchronously`), same as `AccountSection`'s
      // `_runExport`; null for an unconfigured build or a caller that
      // chooses to skip it, which `buildMergedAccountExport` treats as
      // "local-only document, no `server` key".
      final remoteSource = context.read<AccountExportRemoteSource?>();
      final profiles = await profilesRepo.list();
      final entriesByProfile = <String, List<DayEntry>>{};
      for (final profile in profiles) {
        entriesByProfile[profile.id] =
            await entriesRepo.listForProfile(profile.id);
      }
      await (widget.exportAccount ??
          defaultExportAccountCollaborator(remoteSource))(
        profiles: profiles,
        entriesByProfile: entriesByProfile,
        appVersion: kAppVersionForExport,
      );
    } catch (error) {
      debugPrint('lunarlog your-data: export failed (${error.runtimeType})');
      if (mounted) setState(() => _exportError = kAccountExportFailureCopy);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}
