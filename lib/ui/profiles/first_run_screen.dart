/// First-run flow (F1, AS1): with zero profiles the gate forces this flow
/// before anything else. Steps, each a boolean that falls through to the
/// next: the web development acknowledgment (KTD9, web only) → the
/// one-time notice ([SettingsKeys.firstRunNoticeShown]) → the account step
/// ("Sign in or create account", with "Not now"; only when the build has
/// an [AuthController] and no session yet) → the name form.
///
/// After a successful sign-in here the flow shows the data-free
/// "Restoring your data…" step until the sync snapshot has been through
/// `restoring` and settled (or reported an error), then lets the home gate
/// re-evaluate: profiles from the account skip the name form entirely
/// (F3, AE13); zero profiles fall through to it with the status tile
/// explaining why.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/sync/sync_engine.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/restoring_screen.dart';
import 'package:lunarlog/ui/account/sign_in_screen.dart';
import 'package:lunarlog/ui/account/sync_status_controller.dart';
import 'package:lunarlog/ui/account/sync_status_tile.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/profiles/profile_dialogs.dart';
import 'package:lunarlog/ui/web/dev_banner.dart';
import 'package:provider/provider.dart';

/// The revised first-run notice (U6, Approach 2).
const String kFirstRunNoticeCopy =
    'Data stays on this device unless you sign in to sync it to your account.';

class FirstRunScreen extends StatefulWidget {
  const FirstRunScreen({super.key, this.isWebBuild = kIsWeb});

  /// KTD9 web guardrail; injectable so host tests can exercise it.
  final bool isWebBuild;

  @override
  State<FirstRunScreen> createState() => _FirstRunScreenState();
}

class _FirstRunScreenState extends State<FirstRunScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _noticePending = true;
  bool _accountPending = false;
  bool _webAckPending = false;
  bool _isMinor = false;

  /// Set after a successful sign-in on the account step: the restoring
  /// step holds until the snapshot has passed through `restoring`.
  bool _awaitingRestore = false;
  bool _sawRestoring = false;

  @override
  void initState() {
    super.initState();
    _noticePending = !context.read<ProfileController>().firstRunNoticeShown;
    final auth = context.read<AuthController?>();
    _accountPending = auth != null && !_hasSession(auth.state);
    if (widget.isWebBuild) {
      _checkWebAcknowledgment();
    }
  }

  static bool _hasSession(AuthSessionState state) =>
      state == AuthSessionState.signedIn ||
      state == AuthSessionState.passwordRecovery;

  Future<void> _checkWebAcknowledgment() async {
    final store = context.read<SettingsStore>();
    final acknowledged =
        await store.get(SettingsKeys.webModalAcknowledged) == 'true';
    if (!mounted) return;
    if (acknowledged) return;
    setState(() => _webAckPending = true);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showWebFirstRunAcknowledgment(
        context,
        alreadyAcknowledged: false,
        onAcknowledged: () =>
            store.set(SettingsKeys.webModalAcknowledged, 'true'),
      );
      if (mounted) setState(() => _webAckPending = false);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _acknowledgeNotice() async {
    final controller = context.read<ProfileController>();
    await controller.markFirstRunNoticeShown();
    if (mounted) {
      setState(() => _noticePending = false);
    }
  }

  void _onSignedIn() {
    final sync = context.read<SyncStatusController?>();
    setState(() {
      _accountPending = false;
      // Without an engine there is nothing to restore from.
      _awaitingRestore = sync != null;
      _sawRestoring = false;
    });
  }

  /// Whether the restoring step is over: the engine reported an error, or
  /// it left `restoring` after having been there (or after binding), or
  /// the session went away.
  bool _restoreDone(SyncStatusController? sync, AuthController? auth) {
    if (sync == null) return true;
    if (auth != null && !_hasSession(auth.state)) return true;
    final snapshot = sync.snapshot;
    switch (snapshot.phase) {
      case SyncPhase.restoring:
        _sawRestoring = true;
        return false;
      case SyncPhase.error:
        return true;
      case SyncPhase.awaitingUploadConsent:
      case SyncPhase.accountMismatch:
        // The home gate renders those screens above this one.
        return true;
      case SyncPhase.idle:
      case SyncPhase.paused:
      case SyncPhase.pushing:
      case SyncPhase.pulling:
        return _sawRestoring || snapshot.boundUserId != null;
    }
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    final controller = context.read<ProfileController>();
    await controller.createProfile(
      displayName: _nameController.text,
      isMinor: _isMinor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthController?>(context);
    final sync = Provider.of<SyncStatusController?>(context);
    if (_webAckPending) {
      // The blocking acknowledgment dialog is up; keep a data-free scaffold
      // underneath it.
      return const Scaffold(body: SizedBox.expand());
    }
    if (_noticePending) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  kFirstRunNoticeCopy,
                  style: TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _acknowledgeNotice,
                  child: const Text('I understand'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_accountPending && auth != null) {
      return SignInScreen(
        embedded: true,
        onSignedIn: _onSignedIn,
        onNotNow: () => setState(() => _accountPending = false),
      );
    }
    if (_awaitingRestore) {
      if (_restoreDone(sync, auth)) {
        _awaitingRestore = false;
      } else {
        return const RestoringScreen();
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Create a profile')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (auth != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SyncStatusTile(webSyncOff: widget.isWebBuild && sync == null),
                ),
              TextFormField(
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: validateProfileName,
              ),
              CheckboxListTile(
                value: _isMinor,
                onChanged: (value) =>
                    setState(() => _isMinor = value ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text('This profile is for a minor'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _create,
                child: const Text('Create profile'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
