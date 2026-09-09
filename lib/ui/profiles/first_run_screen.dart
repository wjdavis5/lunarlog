/// First-run flow (F1, AS1 + Issue #216's onboarding rework): with zero
/// profiles the gate forces this flow before anything else. Steps, each
/// a boolean that falls through to the next: the web development
/// acknowledgment (KTD9, web only) → the three-card introduction
/// (identity/value, profiles-and-guardians, the data/sync notice —
/// #216; gated by the same [SettingsKeys.firstRunNoticeShown] flag the
/// single-notice step used) → the account step ("Sign in or create
/// account", with "Not now"; only when the build has an
/// [AuthController] and no session yet) → the name form ("Continue") →
/// the cycle questions (#216: last period start, typical cycle/period
/// length, birth-control method, goal/mode — every question skippable),
/// whose "Create profile" performs the creation and hands the answers
/// to the [OnboardingCycleAnswersRecorder] seam.
///
/// After a successful sign-in here the flow shows the data-free
/// "Restoring your data…" step until the sync snapshot has been through
/// `restoring` and settled (or reported an error), then lets the home gate
/// re-evaluate: profiles from the account skip the name form and cycle
/// questions entirely (F3, AE13); zero profiles fall through to them
/// with the status tile explaining why.
///
/// A first run that *starts* with a session (a cold-start link exchanged
/// before this screen existed) and has a [SyncStatusController] enters the
/// same restoring wait from `initState` instead of the name form, so the
/// bind-time pull is never skipped (#2 U3; KTD4, R8). The single
/// [_onSignedIn] path is unchanged and there is no build-time exit.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/repositories/drift_onboarding_cycle_answers_recorder.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/limits.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/onboarding/onboarding_cycle_answers.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/sync/sync_engine.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/restoring_screen.dart';
import 'package:lunarlog/ui/account/sign_in_screen.dart';
import 'package:lunarlog/ui/account/sync_status_controller.dart';
import 'package:lunarlog/ui/account/sync_status_tile.dart';
import 'package:lunarlog/ui/l10n/dates.dart';
import 'package:lunarlog/ui/profiles/birth_control_choices.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/profiles/profile_dialogs.dart';
import 'package:lunarlog/ui/theme/tokens.dart';
import 'package:lunarlog/ui/web/dev_banner.dart';
import 'package:provider/provider.dart';

/// The app's wordmark as rendered on the identity card. A proper noun,
/// not translatable copy (#340's numeral precedent).
const String kFirstRunBrandName = 'LunarLog';

/// The date-picker callable, injectable so widget tests can answer the
/// last-period question without driving the Material dialog.
typedef FirstRunDatePicker =
    Future<DateTime?> Function(BuildContext context, DateTime initialDate,
        DateTime firstDate, DateTime lastDate);

Future<DateTime?> _showMaterialDatePicker(BuildContext context,
        DateTime initialDate, DateTime firstDate, DateTime lastDate) =>
    showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );

/// How far back the last-period-start picker reaches: a generous year —
/// the question asks about the *last* period, so anything older is a
/// different question.
const int kLastPeriodLookbackDays = 365;

class FirstRunScreen extends StatefulWidget {
  const FirstRunScreen({
    super.key,
    this.isWebBuild = kIsWeb,
    this.todayProvider = LocalDate.today,
    this.pickDate = _showMaterialDatePicker,
  });

  /// KTD9 web guardrail; injectable so host tests can exercise it.
  final bool isWebBuild;

  /// "Today" as the device-local civil date; injectable for tests.
  final LocalDate Function() todayProvider;

  /// The date-picker callable; injectable for tests.
  final FirstRunDatePicker pickDate;

  @override
  State<FirstRunScreen> createState() => _FirstRunScreenState();
}

class _FirstRunScreenState extends State<FirstRunScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _cycleFormKey = GlobalKey<FormState>();
  final _typicalCycleController = TextEditingController();
  final _typicalPeriodController = TextEditingController();

  /// Which introduction card is showing (0 value / 1 guardians / 2 the
  /// data/sync notice). The whole intro lives under [_noticePending].
  int _introIndex = 0;
  bool _noticePending = true;
  bool _accountPending = false;
  bool _webAckPending = false;
  bool _isMinor = false;

  /// Care mode for the profile being created (Issue #131): selectable at
  /// creation, changeable later from the profile's edit dialog.
  ProfileMode _mode = ProfileMode.standard;

  /// The cycle-questions step (#216): shown between the name form and
  /// profile creation, so the home gate's zero-profiles decision (which
  /// would unmount this screen the moment a profile exists) is untouched.
  bool _cycleQuestionsPending = false;

  /// Cycle-question answers, all skippable (null / notAnswered).
  LocalDate? _lastPeriodStart;
  BirthControlChoice _birthControl = BirthControlChoice.notAnswered;
  LifecycleMode _lifecycleMode = LifecycleMode.tracking;

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
    // Cold-start link session (#2 U3): wait for the restore like a
    // sign-in made here would; without an engine there is nothing to
    // restore from.
    if (auth != null &&
        auth.signedIn &&
        context.read<SyncStatusController?>() != null) {
      _awaitingRestore = true;
    }
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
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _showWebAcknowledgmentDialog(store));
  }

  /// The blocking dialog itself, split out of [_checkWebAcknowledgment] so
  /// each half stays small: shown post-frame (over the data-free scaffold
  /// [build] renders while [_webAckPending]), then clears that flag once
  /// dismissed.
  Future<void> _showWebAcknowledgmentDialog(SettingsStore store) async {
    if (!mounted) return;
    await showWebFirstRunAcknowledgment(
      context,
      alreadyAcknowledged: false,
      onAcknowledged: () =>
          store.set(SettingsKeys.webModalAcknowledged, 'true'),
    );
    if (mounted) setState(() => _webAckPending = false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _typicalCycleController.dispose();
    _typicalPeriodController.dispose();
    super.dispose();
  }

  // ------------------------------------------------- introduction cards

  /// "Next": advance one card; on the notice card (the last) it is the
  /// "I understand" acknowledgement, which ends the introduction.
  void _advanceIntro() {
    if (_introIndex < 2) {
      setState(() => _introIndex++);
    } else {
      _acknowledgeNotice();
    }
  }

  /// "Skip": the introduction is one skippable unit, so skipping any
  /// card clears all of them — this is what keeps the issue's tap
  /// budget true (a skip-everything user spends one tap here, replacing
  /// today's single notice tap one-for-one).
  Future<void> _skipIntro() => _acknowledgeNotice();

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
    return _restoreDoneForPhase(sync.snapshot);
  }

  /// A switch *expression* (not an if-chain): every [SyncPhase] value is
  /// named explicitly (no `_` wildcard), so adding a new phase without
  /// updating this method is a compile error, not a silently-wrong result.
  /// `error`, `awaitingUploadConsent` and `accountMismatch` end the wait
  /// immediately — the home gate renders its own screen for each of these
  /// above this one, so there is nothing left here to guard.
  bool _restoreDoneForPhase(SyncSnapshot snapshot) =>
      switch (snapshot.phase) {
        SyncPhase.restoring => _markSawRestoringAndReturnFalse(),
        SyncPhase.error ||
        SyncPhase.awaitingUploadConsent ||
        SyncPhase.accountMismatch =>
          true,
        SyncPhase.idle ||
        SyncPhase.paused ||
        SyncPhase.pushing ||
        SyncPhase.pulling =>
          _sawRestoring || snapshot.boundUserId != null,
      };

  /// The `restoring` arm's side effect, pulled out since switch-expression
  /// arms must be single expressions.
  bool _markSawRestoringAndReturnFalse() {
    _sawRestoring = true;
    return false;
  }

  // ------------------------------------------------------ creation steps

  /// "Continue" on the name form: validate the name now so the final
  /// create cannot fail on it, then move to the cycle questions.
  void _continueToCycleQuestions() {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _cycleQuestionsPending = true);
  }

  Future<void> _pickLastPeriodDate() async {
    final today = _nowAsDateTime();
    final picked = await widget.pickDate(
      context,
      _lastPeriodStart == null
          ? today
          : _localDateToDateTime(_lastPeriodStart!),
      today.subtract(const Duration(days: kLastPeriodLookbackDays)),
      today,
    );
    if (picked == null || !mounted) return;
    setState(() => _lastPeriodStart = LocalDate.fromDateTime(picked));
  }

  DateTime _nowAsDateTime() =>
      _localDateToDateTime(widget.todayProvider());

  DateTime _localDateToDateTime(LocalDate date) =>
      DateTime(date.year, date.month, date.day);

  /// "Create profile" on the cycle-questions step: the only step that
  /// actually creates. The recorder seam is resolved before the first
  /// await (the home gate unmounts this screen the moment the profile
  /// exists, so nothing may touch [context] after it).
  Future<void> _create() async {
    if (!_cycleFormKey.currentState!.validate()) return;
    final controller = context.read<ProfileController>();
    final l10n = AppLocalizations.of(context);
    final recorder = _resolveRecorder();
    final profile = await controller.createProfile(
      displayName: _nameController.text,
      isMinor: _isMinor,
      mode: _mode,
    );
    await recorder?.record(profile.id, _collectedAnswers(l10n));
  }

  /// The recorder seam, or null on a tree with no storage wired (the
  /// local-only test-harness shape; see [ProfileDetailScreen]'s precedent).
  OnboardingCycleAnswersRecorder? _resolveRecorder() {
    final storage = context.read<LunarLogStorage?>();
    return storage == null
        ? null
        : DriftOnboardingCycleAnswersRecorder(storage,
            todayProvider: widget.todayProvider);
  }

  OnboardingCycleAnswers _collectedAnswers(AppLocalizations l10n) =>
      OnboardingCycleAnswers(
        lastPeriodStart: _lastPeriodStart,
        typicalCycleLengthDays:
            _optionalInt(_typicalCycleController.text),
        typicalPeriodLengthDays:
            _optionalInt(_typicalPeriodController.text),
        birthControlMethod:
            birthControlStoredValue(_birthControl, l10n),
        lifecycleMode: _lifecycleMode,
      );

  /// Parses an optional whole-day count; blank (skipped) is null. Range
  /// enforcement lives in the form validators, mirroring
  /// [kMinTypicalCycleLengthDays] and friends.
  int? _optionalInt(String text) {
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : int.tryParse(trimmed);
  }

  // ------------------------------------------------------------- builders

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
      return _introScreen();
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
    return _cycleQuestionsPending
        ? _cycleQuestionsScreen()
        : _nameFormScreen(auth, sync);
  }

  /// The three-card introduction (#216): value, profiles/guardians, the
  /// data/sync notice (today's copy). "Skip" clears the whole intro, so a
  /// skip-everything user's added tap count stays inside the issue's
  /// budget of 2.
  Widget _introScreen() {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _introBody(l10n),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    key: const ValueKey('first-run-skip'),
                    onPressed: _skipIntro,
                    child: Text(l10n.firstRunSkip),
                  ),
                  FilledButton(
                    key: const ValueKey('first-run-next'),
                    onPressed: _advanceIntro,
                    child: Text(_introIndex < 2
                        ? l10n.firstRunNext
                        : l10n.firstRunUnderstand),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The card content for [_introIndex] — kept branchy-but-small so each
  /// card's copy stays readable in place.
  Widget _introBody(AppLocalizations l10n) {
    switch (_introIndex) {
      case 0:
        return _valueCard(l10n);
      case 1:
        return _guardiansCard(l10n);
      case 2:
        return _noticeCard(l10n);
      default:
        // Unreachable: [_advanceIntro] ends the intro at index 2.
        return _noticeCard(l10n);
    }
  }

  Widget _valueCard(AppLocalizations l10n) => Column(
        key: const ValueKey('first-run-card-value'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.nights_stay, size: 48),
          const SizedBox(height: 8),
          Text(
            kFirstRunBrandName,
            textAlign: TextAlign.center,
            style: LLType.titleMedium.toTextStyle(),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.firstRunValueHeadline,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(l10n.firstRunValueBody),
        ],
      );

  Widget _guardiansCard(AppLocalizations l10n) => Column(
        key: const ValueKey('first-run-card-guardians'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.firstRunGuardiansTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(l10n.firstRunGuardiansBody),
          const SizedBox(height: 16),
          Text(
            l10n.firstRunMinorExplainerTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(l10n.firstRunMinorExplainerBody),
        ],
      );

  Widget _noticeCard(AppLocalizations l10n) => Column(
        key: const ValueKey('first-run-card-notice'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.firstRunNoticeBody,
            style: LLType.titleMedium.toTextStyle(),
          ),
        ],
      );

  /// The existing name form, with its submit moved to "Continue" and a
  /// one-line truthful hint under the minor checkbox (#216's
  /// accompanied-by-an-explanation AC).
  Widget _nameFormScreen(AuthController? auth, SyncStatusController? sync) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.firstRunCreateTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              if (auth != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SyncStatusTile(
                      webSyncOff: widget.isWebBuild && sync == null),
                ),
              TextFormField(
                controller: _nameController,
                autofocus: true,
                decoration: InputDecoration(labelText: l10n.firstRunNameLabel),
                maxLength: kMaxDisplayNameLength,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                validator: validateProfileName,
              ),
              CheckboxListTile(
                value: _isMinor,
                onChanged: (value) =>
                    setState(() => _isMinor = value ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.firstRunMinorLabel),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 8),
                child: Text(
                  l10n.firstRunMinorHint,
                  key: const ValueKey('first-run-minor-hint'),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(l10n.firstRunCareModeLabel,
                    key: const ValueKey('care-mode-label'),
                    style: Theme.of(context).textTheme.bodySmall),
              ),
              DropdownButton<ProfileMode>(
                key: const ValueKey('care-mode-dropdown'),
                value: _mode,
                isExpanded: true,
                onChanged: (value) =>
                    setState(() => _mode = value ?? ProfileMode.standard),
                items: [
                  for (final mode in ProfileMode.values)
                    DropdownMenuItem<ProfileMode>(
                      value: mode,
                      child: Text(mode.label),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _mode.hint,
                  key: const ValueKey('care-mode-hint'),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const ValueKey('first-run-continue'),
                onPressed: _continueToCycleQuestions,
                child: Text(l10n.firstRunContinue),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The cycle questions (#216): five optional questions on one screen,
  /// each individually skippable (blank / not answered), with the final
  /// "Create profile" performing the creation.
  Widget _cycleQuestionsScreen() {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.firstRunCreateTitle),
        leading: BackButton(
          onPressed: () => setState(() => _cycleQuestionsPending = false),
        ),
      ),
      body: Form(
        key: _cycleFormKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(l10n.firstRunCycleCaption),
            const SizedBox(height: 16),
            _lastPeriodField(l10n),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('cycle-typical-cycle'),
              controller: _typicalCycleController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.firstRunCycleTypicalCycleLabel,
                hintText: l10n.firstRunCycleTypicalCycleHint,
              ),
              validator: (value) => _validateDayRange(
                value,
                l10n.firstRunCycleLengthRangeError,
                kMinTypicalCycleLengthDays,
                kMaxTypicalCycleLengthDays,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('cycle-typical-period'),
              controller: _typicalPeriodController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.firstRunCycleTypicalPeriodLabel,
                hintText: l10n.firstRunCycleTypicalPeriodHint,
              ),
              validator: (value) => _validateDayRange(
                value,
                l10n.firstRunPeriodLengthRangeError,
                kMinTypicalPeriodLengthDays,
                kMaxTypicalPeriodLengthDays,
              ),
            ),
            const SizedBox(height: 12),
            _labelAbove(l10n.firstRunCycleBirthControlLabel,
                const ValueKey('cycle-birth-control-label')),
            DropdownButton<BirthControlChoice>(
              key: const ValueKey('cycle-birth-control'),
              value: _birthControl,
              isExpanded: true,
              onChanged: (value) => setState(() =>
                  _birthControl = value ?? BirthControlChoice.notAnswered),
              items: [
                for (final choice in BirthControlChoice.values)
                  DropdownMenuItem<BirthControlChoice>(
                    value: choice,
                    child: Text(birthControlChoiceLabel(choice, l10n)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _labelAbove(l10n.firstRunCycleGoalLabel,
                const ValueKey('cycle-goal-label')),
            DropdownButton<LifecycleMode>(
              key: const ValueKey('cycle-goal'),
              value: _lifecycleMode,
              isExpanded: true,
              onChanged: (value) => setState(
                  () => _lifecycleMode = value ?? LifecycleMode.tracking),
              items: [
                for (final mode in LifecycleMode.values)
                  DropdownMenuItem<LifecycleMode>(
                    value: mode,
                    child: Text(mode.label),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('cycle-create'),
              onPressed: _create,
              child: Text(l10n.firstRunCreateButton),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lastPeriodField(AppLocalizations l10n) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _labelAbove(l10n.firstRunCycleLastPeriodLabel,
              const ValueKey('cycle-last-period-label')),
          if (_lastPeriodStart == null)
            OutlinedButton.icon(
              key: const ValueKey('cycle-last-period-choose'),
              onPressed: _pickLastPeriodDate,
              icon: const Icon(Icons.calendar_today),
              label: Text(l10n.firstRunCycleChooseDate),
            )
          else
            Row(
              children: [
                Expanded(
                  child: Text(
                    formatMonthDayYear(
                        _localDateToDateTime(_lastPeriodStart!)),
                    key: const ValueKey('cycle-last-period-value'),
                  ),
                ),
                TextButton(
                  onPressed: _pickLastPeriodDate,
                  child: Text(l10n.firstRunCycleChangeDate),
                ),
                TextButton(
                  key: const ValueKey('cycle-last-period-clear'),
                  onPressed: () =>
                      setState(() => _lastPeriodStart = null),
                  child: Text(l10n.firstRunCycleClearDate),
                ),
              ],
            ),
        ],
      );

  Widget _labelAbove(String label, Key key) => Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          key: key,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );

  /// Optional-day-count validation: blank passes (the question is
  /// skippable); anything else must parse as a whole number inside
  /// [min]–[max] inclusive, else [errorMessage].
  String? _validateDayRange(
      String? value, String errorMessage, int min, int max) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final parsed = int.tryParse(trimmed);
    if (parsed == null || parsed < min || parsed > max) {
      return errorMessage;
    }
    return null;
  }
}
