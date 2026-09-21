/// First-run flow (F1, AS1 + Issue #216's onboarding rework + Issue #804's
/// household setup): with zero profiles the gate forces this flow before
/// anything else. Steps, each a boolean that falls through to the next:
/// the web development acknowledgment (KTD9, web only) → the three-card
/// introduction (identity/value, profiles-and-guardians, the data/sync
/// notice — #216; gated by the same [SettingsKeys.firstRunNoticeShown]
/// flag the single-notice step used) → the account step ("Sign in or
/// create account", with "Not now"; only when the build has an
/// [AuthController] and no session yet) → the name form ("Continue") →
/// the cycle questions (#216: last period start, typical cycle/period
/// length, birth-control method, goal/mode — every question skippable),
/// whose "Create profile" performs the creation and hands the answers
/// to the [OnboardingCycleAnswersRecorder] seam.
///
/// Issue #804 — household setup in first run: the name form opens with
/// the "Who is this profile for?" choice (Me, preselected / Someone I
/// care for / Both), so today's single-profile path never answers it. A
/// "Someone I care for" (or a post-"Both" add-loop) card carries a
/// relationship dropdown, a minor default of on, and a Teen-mode
/// *suggestion* (preselected, never forced — #131); its cycle step is the
/// one optional last-period question. After such a creation the flow
/// continues: "Add another person?" loops back to a fresh card, then
/// "Add another guardian?" offers the guardian invite and — per #966's
/// preset machinery — the subject invite for a minor's own profile, with
/// the sign-in prompt living here (the first place an account is
/// required, saying why) when the account step was skipped. Every new
/// step is skippable; a "Me" profile ends the flow exactly as before.
/// While the household loop is running the controller's
/// `firstRunFlowActive` flag keeps the home gate from unmounting this
/// screen (the zero-profiles rule alone would).
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

import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/limits.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/models/profile_relationship.dart';
import 'package:lunarlog/domain/onboarding/onboarding_cycle_answers.dart';
import 'package:lunarlog/domain/prediction/prediction.dart' show CycleFacts;
import 'package:lunarlog/domain/pregnancy.dart'
    show estimatedDueDateFromLastPeriod;
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/domain/sync/sync_engine.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/observability/route_names.dart'
    show kRouteImportScreen, kRouteInviteGuardianSheet;
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/restoring_screen.dart';
import 'package:lunarlog/ui/account/sign_in_screen.dart';
import 'package:lunarlog/ui/account/sync_status_controller.dart';
import 'package:lunarlog/ui/account/sync_status_tile.dart';
import 'package:lunarlog/ui/components/inline_error.dart';
import 'package:lunarlog/ui/components/responsive_body.dart';
import 'package:lunarlog/ui/l10n/dates.dart';
import 'package:lunarlog/ui/profiles/birth_control_choices.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/profiles/profile_dialogs.dart';
import 'package:lunarlog/ui/routes.dart' show pushNamedScreen;
import 'package:lunarlog/ui/sharing/invite_guardian_dialog.dart';
import 'package:lunarlog/ui/theme/tokens.dart';
import 'package:lunarlog/ui/web/dev_banner.dart';
import 'package:provider/provider.dart';

/// The app's wordmark as rendered on the identity card. A proper noun,
/// not translatable copy (#340's numeral precedent).
const String kFirstRunBrandName = 'lunarlog';

/// The date-picker callable, injectable so widget tests can answer the
/// last-period question without driving the Material dialog.
typedef FirstRunDatePicker = Future<DateTime?> Function(
  BuildContext context,
  DateTime initialDate,
  DateTime firstDate,
  DateTime lastDate,
);

Future<DateTime?> _showMaterialDatePicker(
  BuildContext context,
  DateTime initialDate,
  DateTime firstDate,
  DateTime lastDate,
) => showDatePicker(
  context: context,
  initialDate: initialDate,
  firstDate: firstDate,
  lastDate: lastDate,
);

/// How far back the last-period-start picker reaches: a generous year —
/// the question asks about the *last* period, so anything older is a
/// different question.
const int kLastPeriodLookbackDays = 365;

/// Issue #804: who the card being filled is for. `me` (preselected)
/// keeps today's single-profile flow exactly as it is; `someone` and
/// `both` switch the flow into the household setup — the add-another
/// loop and the invite step.
enum _FirstRunWho { me, someone, both }

/// The relationship choices for a card that is not the operator's own
/// (issue #804). `self` is deliberately absent: the "Me" answer covers
/// it, and the add-another loop is for *other* people.
const List<ProfileRelationship> _caredForRelationships = [
  ProfileRelationship.daughter,
  ProfileRelationship.son,
  ProfileRelationship.child,
  ProfileRelationship.partner,
  ProfileRelationship.other,
];

/// Whether [relationship] marks the profile subject as the operator's
/// child — the three relationships the subject-invite preset (#966) and
/// the Teen-mode suggestion key off.
bool _isChildRelationship(ProfileRelationship relationship) =>
    relationship == ProfileRelationship.daughter ||
    relationship == ProfileRelationship.son ||
    relationship == ProfileRelationship.child;

class FirstRunScreen extends StatefulWidget {
  const FirstRunScreen({
    super.key,
    this.isWebBuild = kIsWeb,
    this.todayProvider = LocalDate.today,
    this.pickDate = _showMaterialDatePicker,
    this.onOpenImport,
  });

  /// KTD9 web guardrail; injectable so host tests can exercise it.
  final bool isWebBuild;

  /// "Today" as the device-local civil date; injectable for tests.
  final LocalDate Function() todayProvider;

  /// The date-picker callable; injectable for tests.
  final FirstRunDatePicker pickDate;

  /// Injected action to open the restore/import flow (Issue #468).
  /// Defaults to pushing [ImportScreen] via [kRouteImportScreen].
  final Future<void> Function(BuildContext context)? onOpenImport;

  @override
  State<FirstRunScreen> createState() => _FirstRunScreenState();
}

class _FirstRunScreenState extends State<FirstRunScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _cycleFormKey = GlobalKey<FormState>();
  final _typicalCycleController = TextEditingController();
  final _typicalPeriodController = TextEditingController();

  /// #165: the cycle questions' explicit focus chain — "next" on the
  /// typical-cycle field advances to the typical-period field.
  final _typicalCycleFocus = FocusNode();
  final _typicalPeriodFocus = FocusNode();

  /// Which introduction card is showing (0 value / 1 guardians / 2 the
  /// data/sync notice). The whole intro lives under [_noticePending].
  int _introIndex = 0;
  bool _noticePending = true;
  bool _accountPending = false;
  bool _webAckPending = false;
  bool _isMinor = false;
  bool _ageAcknowledged = false;
  bool _ageAckError = false;
  bool _ageAckPreviouslyRecorded = false;

  /// Issue #804: who the card being filled is for. Defaults to `me`, so
  /// the pre-#804 single-profile flow is unchanged (the chips never have
  /// to be touched).
  _FirstRunWho _who = _FirstRunWho.me;

  /// Issue #804: relationship of the card's subject to the operator, used
  /// whenever the card is for someone other than the operator
  /// ([_caredForCard]). Daughter is the default the issue names.
  ProfileRelationship _relationship = ProfileRelationship.daughter;

  /// Issue #804: profiles created during this first run, in order — the
  /// wrap-up loop's existence check and the invite step's per-profile
  /// rows are derived from it.
  final List<Profile> _createdProfiles = [];

  /// Issue #804: the "Add another person?" step, shown after a cared-for
  /// (or "Both"-flow) creation instead of ending the flow.
  bool _wrapUpPending = false;

  /// Issue #804: the "Add another guardian?" step — per-profile
  /// guardian and subject invites (#966's preset machinery).
  bool _inviteStepPending = false;

  /// Whether the card being filled is for someone other than the
  /// operator: an explicit "Someone I care for" answer, or any
  /// add-another-loop card. Drives the relationship dropdown, the
  /// shortened cycle step, and the created profile's relationship value.
  bool get _caredForCard =>
      _who == _FirstRunWho.someone || _createdProfiles.isNotEmpty;

  /// Whether this run continues after the current creation (the household
  /// wrap-up loop) instead of ending on the gate's ordinary transition. A
  /// "Both" answer is household even though its first card is the
  /// operator's own.
  bool get _householdFlow =>
      _who != _FirstRunWho.me || _createdProfiles.isNotEmpty;

  /// Care mode for the profile being created (Issue #131): selectable at
  /// creation, changeable later from the profile's edit dialog.
  ProfileMode _mode = ProfileMode.standard;

  /// Cycle-questions step (#216): shown between the name form and
  /// profile creation, so the home gate's zero-profiles decision (which
  /// would unmount this screen the moment a profile exists) is untouched.
  bool _cycleQuestionsPending = false;

  /// Issue #804: the shortened cycle step for a cared-for card — the one
  /// optional last-period question (a parent often does not know her
  /// daughter's typical lengths; #218's seeding tolerates blanks).
  bool _cycleShortPending = false;

  /// Cycle-question answers, all skippable (null / notAnswered).
  LocalDate? _lastPeriodStart;
  BirthControlChoice _birthControl = BirthControlChoice.notAnswered;
  LifecycleMode _lifecycleMode = LifecycleMode.tracking;

  /// Set after a successful sign-in on the account step: the restoring
  /// step holds until the snapshot has passed through `restoring`.
  bool _awaitingRestore = false;
  bool _sawRestoring = false;

  /// #544: guards [_create] against a double-tap on slow network (which
  /// would otherwise create two profiles) and surfaces a thrown failure
  /// instead of leaving the button looking like it did nothing.
  bool _creating = false;
  String? _createError;

  @override
  void initState() {
    super.initState();
    _noticePending = !context.read<ProfileController>().firstRunNoticeShown;
    final auth = context.read<AuthController?>();
    _accountPending = auth != null && !auth.state.hasUsableSession;
    // Cold-start link session (#2 U3): wait for the restore like a
    // sign-in made here would; without an engine there is nothing to
    // restore from.
    if (auth != null &&
        auth.signedIn &&
        context.read<SyncStatusController?>() != null) {
      _awaitingRestore = true;
    }
    if (widget.isWebBuild) {
      unawaited(_checkWebAcknowledgment());
    }
    unawaited(_checkAgeAcknowledgment());
  }

  Future<void> _checkAgeAcknowledgment() async {
    final store = context.read<SettingsStore>();
    final acknowledged =
        await store.get(SettingsKeys.minimumAgeAcknowledged) == 'true';
    if (!mounted) return;
    setState(() {
      _ageAckPreviouslyRecorded = acknowledged;
      _ageAcknowledged = acknowledged;
    });
  }

  Future<void> _checkWebAcknowledgment() async {
    final store = context.read<SettingsStore>();
    final acknowledged =
        await store.get(SettingsKeys.webModalAcknowledged) == 'true';
    if (!mounted) return;
    if (acknowledged) return;
    setState(() => _webAckPending = true);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _showWebAcknowledgmentDialog(store),
    );
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
    _typicalCycleFocus.dispose();
    _typicalPeriodFocus.dispose();
    super.dispose();
  }

  // ------------------------------------------------- introduction cards

  /// "Next": advance one card; on the notice card (the last) it is the
  /// "I understand" acknowledgement, which ends the introduction.
  void _advanceIntro() {
    if (_introIndex < 2) {
      setState(() => _introIndex++);
    } else {
      unawaited(_acknowledgeNotice());
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

  /// Opens the import/restore flow (Issue #468). When an import produces
  /// at least one profile, completes onboarding and selects the imported
  /// profile so the home gate transitions to AppShell.
  Future<void> _openImport() async {
    if (widget.onOpenImport != null) {
      await widget.onOpenImport!(context);
    } else {
      await pushNamedScreen<void>(context, kRouteImportScreen);
    }
    if (!mounted) return;
    final controller = context.read<ProfileController>();
    await controller.load();
    if (controller.activeProfiles.isNotEmpty) {
      await controller.markFirstRunNoticeShown();
      if (controller.activeProfile == null) {
        await controller.selectProfile(controller.activeProfiles.first.id);
      }
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
    if (auth != null && !auth.state.hasUsableSession) return true;
    return _restoreDoneForPhase(sync.snapshot);
  }

  /// A switch *expression* (not an if-chain): every [SyncPhase] value is
  /// named explicitly (no `_` wildcard), so adding a new phase without
  /// updating this method is a compile error, not a silently-wrong result.
  /// `error`, `awaitingUploadConsent` and `accountMismatch` end the wait
  /// immediately — the home gate renders its own screen for each of these
  /// above this one, so there is nothing left here to guard.
  bool _restoreDoneForPhase(SyncSnapshot snapshot) => switch (snapshot.phase) {
    SyncPhase.restoring => _markSawRestoringAndReturnFalse(),
    SyncPhase.error ||
    SyncPhase.awaitingUploadConsent ||
    SyncPhase.accountMismatch => true,
    SyncPhase.idle ||
    SyncPhase.paused ||
    SyncPhase.pushing ||
    SyncPhase.pulling => _sawRestoring || snapshot.boundUserId != null,
  };

  /// The `restoring` arm's side effect, pulled out since switch-expression
  /// arms must be single expressions.
  bool _markSawRestoringAndReturnFalse() {
    _sawRestoring = true;
    return false;
  }

  // ------------------------------------------------------ creation steps

  /// Issue #804: who-choice and relationship defaults. "Someone I care
  /// for" opens a daughter card with the minor flag on and Teen mode
  /// preselected — a *suggestion* (both stay changeable on the card,
  /// #131's "never forced"). "Me" and "Both" open on the operator's own
  /// card with today's defaults.
  void _onWhoChanged(_FirstRunWho who) {
    setState(() {
      _who = who;
      if (who == _FirstRunWho.someone) {
        // Someone always opens on a daughter card, whatever was picked on
        // an earlier visit to the choice.
        _relationship = ProfileRelationship.daughter;
        _applyRelationshipDefaults();
      } else {
        _isMinor = false;
        _mode = ProfileMode.standard;
      }
    });
  }

  /// Issue #804: relationship picked on a cared-for card. A child
  /// relationship suggests the minor flag and Teen mode (both stay
  /// changeable); partner/other defaults the flag back off.
  void _onRelationshipChanged(ProfileRelationship relationship) {
    setState(() {
      _relationship = relationship;
      _applyRelationshipDefaults();
    });
  }

  /// The defaults a cared-for card's controls get from the current
  /// [_relationship], split out of both change handlers.
  void _applyRelationshipDefaults() {
    if (_isChildRelationship(_relationship)) {
      _isMinor = true;
      _mode = ProfileMode.teen;
    } else {
      _isMinor = false;
    }
  }

  /// "Continue" on the name form: validate the name now so the final
  /// create cannot fail on it, then move to the cycle questions — the
  /// full five for the operator's own card, the one optional question
  /// for a cared-for card (#804). A household answer arms the
  /// controller's flow flag *before* any creation, so the home gate
  /// keeps this screen mounted once profiles exist.
  void _continueToCycleQuestions() {
    if (!_ageAckPreviouslyRecorded && !_ageAcknowledged) {
      setState(() => _ageAckError = true);
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (_householdFlow) {
      context.read<ProfileController>().beginFirstRunFlow();
    }
    setState(() {
      if (_caredForCard) {
        _cycleShortPending = true;
      } else {
        _cycleQuestionsPending = true;
      }
    });
  }

  Future<void> _pickLastPeriodDate() async {
    final today = widget.todayProvider();
    final picked = await widget.pickDate(
      context,
      _lastPeriodStart?.toDateTime() ?? today.toDateTime(),
      today.addDays(-kLastPeriodLookbackDays).toDateTime(),
      today.toDateTime(),
    );
    if (picked == null || !mounted) return;
    setState(() => _lastPeriodStart = LocalDate.fromDateTime(picked));
  }

  /// "Create profile" on the cycle-questions step: the only step that
  /// actually creates. The recorder seam is resolved before the first
  /// await (the home gate unmounts this screen the moment the profile
  /// exists on the plain path, so nothing may touch [context] after it;
  /// the household flow holds the screen via the controller's flag).
  Future<void> _create() async {
    if (_cycleFormKey.currentState?.validate() == false) return;
    // #544: without this guard, a double-tap on slow network fires two
    // overlapping calls and creates two profiles on first run.
    if (_creating) return;
    final controller = context.read<ProfileController>();
    final l10n = AppLocalizations.of(context);
    final recorder = _resolveRecorder();
    setState(() {
      _creating = true;
      _createError = null;
    });
    try {
      if (!_ageAckPreviouslyRecorded && _ageAcknowledged) {
        final store = context.read<SettingsStore>();
        await store.set(SettingsKeys.minimumAgeAcknowledged, 'true');
        _ageAckPreviouslyRecorded = true;
      }
      final profile = await controller.createProfile(
        displayName: _nameController.text,
        isMinor: _isMinor,
        mode: _mode,
        // Issue #853: creation always leaves the flag at the engine default
        // (null) — ON for a teen profile until `CycleConfidence.high`, OFF
        // otherwise, with no control on this form: the explicit tri-state
        // lives in the profile edit dialog
        // (`ProfileDialogs`' irregular-framing-toggle), which is also where
        // the framing is visible and changeable later.
        irregularFraming: null,
        // Issue #804: "Me" stamps `self` (AC2); a cared-for card stamps
        // the picked relationship.
        relationship:
            _caredForCard ? _relationship : ProfileRelationship.self,
        // Issue #530: the three cycle answers feed provisional seeding —
        // captured here, not just in the recorder.
        facts: CycleFacts(
          lastPeriodStart: _lastPeriodStart,
          typicalCycleLengthDays: _optionalInt(_typicalCycleController.text),
          typicalPeriodLengthDays: _optionalInt(_typicalPeriodController.text),
        ),
      );
      await recorder?.record(profile.id, _collectedAnswers(l10n));
      if (mounted) _onProfileCreated(profile);
    } catch (_) {
      if (mounted) {
        setState(() {
          _createError = 'Could not create the profile. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  /// Issue #804: after a successful creation inside the household flow,
  /// record the profile and advance to the wrap-up loop. The plain "Me"
  /// path does nothing here — the home gate's ordinary transition (the
  /// active profile's Today) takes over exactly as before this issue.
  void _onProfileCreated(Profile profile) {
    if (!_householdFlow) return;
    _createdProfiles.add(profile);
    setState(() {
      _cycleQuestionsPending = false;
      _cycleShortPending = false;
      _wrapUpPending = true;
    });
  }

  // ------------------------------------------- household wrap-up + invite

  /// "Add another person" on the wrap-up step: back to a fresh cared-for
  /// card with the per-person answers cleared.
  void _resetForNextPerson() {
    setState(() {
      _wrapUpPending = false;
      _nameController.clear();
      _typicalCycleController.clear();
      _typicalPeriodController.clear();
      _lastPeriodStart = null;
      _birthControl = BirthControlChoice.notAnswered;
      _lifecycleMode = LifecycleMode.tracking;
      _relationship = ProfileRelationship.daughter;
      _applyRelationshipDefaults();
      _createError = null;
    });
  }

  /// "Continue" on the wrap-up step: the invite step when this tree can
  /// actually create invites; without a [SharingService] (an unconfigured
  /// build) there is nothing to offer, so ending the flow *is* the skip.
  void _toInviteStep() {
    final sharing = context.read<SharingService?>();
    if (sharing == null) {
      _finishFlow();
      return;
    }
    setState(() {
      _wrapUpPending = false;
      _inviteStepPending = true;
    });
  }

  /// The invite step's back button: the wrap-up loop stays reachable so
  /// another person can still be added.
  void _backToWrapUp() {
    setState(() {
      _inviteStepPending = false;
      _wrapUpPending = true;
    });
  }

  /// Ends the household flow: the home gate resumes its ordinary
  /// decision. Several created profiles land on the picker — today's
  /// household surface (#803's dedicated view does not exist yet); a
  /// single profile lands on its Today (the active pointer #865 set at
  /// creation).
  void _finishFlow() {
    final controller = context.read<ProfileController>();
    controller.endFirstRunFlow();
    if (controller.activeProfiles.length > 1) {
      controller.openPicker();
    }
  }

  /// Opens #966's invite dialog for [profile]. [subjectInviteAvailable]
  /// gates the "her own profile" preset (offered *and* preselected by the
  /// dialog itself); the co-parent button keeps the plain guardian
  /// presets. Same sheet posture as Manage Guardians (#558: a generated
  /// single-use link must survive a stray tap outside the sheet).
  Future<void> _openInviteDialog(
    Profile profile,
    SharingService sharing, {
    required bool subjectInviteAvailable,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      routeSettings: const RouteSettings(name: kRouteInviteGuardianSheet),
      isDismissible: false,
      enableDrag: false,
      builder: (dialogContext) => InviteGuardianDialog(
        profileId: profile.id,
        profileName: profile.displayName,
        sharingService: sharing,
        subjectInviteAvailable: subjectInviteAvailable,
      ),
    );
  }

  /// The recorder seam, or null on a tree with none wired (the local-only
  /// test-harness shape; see [ProfileDetailScreen]'s precedent).
  OnboardingCycleAnswersRecorder? _resolveRecorder() =>
      context.read<OnboardingCycleAnswersRecorder?>();

  OnboardingCycleAnswers _collectedAnswers(AppLocalizations l10n) =>
      OnboardingCycleAnswers(
        lastPeriodStart: _lastPeriodStart,
        typicalCycleLengthDays: _optionalInt(_typicalCycleController.text),
        typicalPeriodLengthDays: _optionalInt(_typicalPeriodController.text),
        birthControlMethod: birthControlStoredValue(_birthControl),
        lifecycleMode: _lifecycleMode,
        // Issue #192: a pregnancy answer at onboarding derives its due
        // date from the just-supplied last-period start (Naegele's
        // rule, 280 days) — the same derivation the edit dialog
        // pre-fills with. A skipped last-period start carries no due
        // date (the manual pick is available later from the edit
        // dialog); the recorder only writes this value when the answers
        // enter Pregnancy mode.
        estimatedDueDate: _lifecycleMode == LifecycleMode.pregnancy &&
                _lastPeriodStart != null
            ? estimatedDueDateFromLastPeriod(_lastPeriodStart!).iso
            : null,
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
        onRestore: _openImport,
      );
    }
    if (_awaitingRestore) {
      if (_restoreDone(sync, auth)) {
        _awaitingRestore = false;
      } else {
        return const RestoringScreen();
      }
    }
    return _creationStepScreen(auth, sync);
  }

  /// The creation-half step decision (issue #804 added the wrap-up and
  /// invite steps behind the cycle questions). An if-chain, not nested
  /// ternaries: each step is one line to scan.
  Widget _creationStepScreen(AuthController? auth, SyncStatusController? sync) {
    if (_inviteStepPending) return _inviteStepScreen(auth);
    if (_wrapUpPending) return _wrapUpScreen();
    if (_cycleQuestionsPending) return _cycleQuestionsScreen();
    if (_cycleShortPending) return _shortCycleScreen();
    return _nameFormScreen(auth, sync);
  }

  /// The three-card introduction (#216): value, profiles/guardians, the
  /// data/sync notice (today's copy). "Skip" clears the whole intro, so a
  /// skip-everything user's added tap count stays inside the issue's
  /// budget of 2.
  Widget _introScreen() {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: ResponsiveBody(
          child: SingleChildScrollView(
          padding: const EdgeInsets.all(LLSpace.space5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _introBody(l10n),
              const SizedBox(height: LLSpace.space5),
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
                    child: Text(
                      _introIndex < 2
                          ? l10n.firstRunNext
                          : l10n.firstRunUnderstand,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: LLSpace.space4),
              OutlinedButton(
                key: const ValueKey('first-run-restore-intro'),
                onPressed: _openImport,
                child: Text(l10n.firstRunRestore),
              ),
            ],
          ),
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
      // Issue #808: the app's real brand mark (already bundled for the
      // launcher icon) instead of a stock `Icons.nights_stay` glyph, with
      // the wordmark raised to the display face's headlineSmall slot.
      // `Center` keeps it at 72dp inside the stretched column.
      Center(
        child: Image.asset(
          'assets/branding/app_icon_1024.png',
          key: const ValueKey('first-run-brand-mark'),
          width: 72,
          height: 72,
        ),
      ),
      const SizedBox(height: LLSpace.space2),
      Text(
        kFirstRunBrandName,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: LLSpace.space4),
      Text(
        l10n.firstRunValueHeadline,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: LLSpace.space2),
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
      const SizedBox(height: LLSpace.space2),
      Text(l10n.firstRunGuardiansBody),
      const SizedBox(height: LLSpace.space4),
      Text(
        l10n.firstRunMinorExplainerTitle,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: LLSpace.space2),
      Text(l10n.firstRunMinorExplainerBody),
    ],
  );

  Widget _noticeCard(AppLocalizations l10n) => Column(
    key: const ValueKey('first-run-card-notice'),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(l10n.firstRunNoticeBody, style: LLType.titleMedium.toTextStyle()),
    ],
  );

  /// The existing name form, with its submit moved to "Continue" and a
  /// one-line truthful hint under the minor checkbox (#216's
  /// accompanied-by-an-explanation AC). Issue #804 adds the who-choice
  /// above the name field (first card only) and the relationship dropdown
  /// on cared-for cards.
  Widget _nameFormScreen(AuthController? auth, SyncStatusController? sync) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.firstRunCreateTitle)),
      body: SafeArea(
        top: false,
        child: ResponsiveBody(
          child: Padding(
            padding: const EdgeInsets.all(LLSpace.space4),
            child: Form(
          key: _formKey,
          // A SingleChildScrollView, not a ListView: this form is short
          // (issue #804's who-choice made it taller than the smallest
          // test/low-end viewports), and every control on it — Continue
          // included — should be built and findable without scrolling,
          // exactly like the intro screen above.
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              if (auth != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SyncStatusTile(
                    webSyncOff: widget.isWebBuild && sync == null,
                  ),
                ),
              // Issue #804: the who-choice lives on the first card only —
              // add-another-loop cards are, by construction, for someone
              // else.
              if (_createdProfiles.isEmpty) _whoControl(l10n),
              TextFormField(
                key: const ValueKey('first-run-name-field'),
                controller: _nameController,
                autofocus: true,
                decoration: InputDecoration(labelText: l10n.firstRunNameLabel),
                maxLength: kMaxDisplayNameLength,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                validator: validateProfileName,
                // #165: the name form's only text field — "done" is its
                // submit (the Continue action), and `name` is the honest
                // autofill hint.
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _continueToCycleQuestions(),
                autofillHints: const [AutofillHints.name],
              ),
              if (_caredForCard) _relationshipField(l10n),
              _minorSection(l10n),
              if (!_ageAckPreviouslyRecorded) _ageAckSection(l10n),
              _careModeSection(l10n),
              const SizedBox(height: LLSpace.space3),
              FilledButton(
                key: const ValueKey('first-run-continue'),
                onPressed: _continueToCycleQuestions,
                child: Text(l10n.firstRunContinue),
              ),
              const SizedBox(height: LLSpace.space3),
              OutlinedButton(
                key: const ValueKey('first-run-restore-name-form'),
                onPressed: _openImport,
                child: Text(l10n.firstRunRestore),
              ),
            ],
            ),
          ),
          ),
        ),
      ),
    ),
  );
  }

  /// Issue #804: "Who is this profile for?" — three chips, `me`
  /// preselected so the plain single-profile path never answers it. The
  /// answer decides the created profile's relationship, the minor
  /// default, which cycle questions follow, and whether the household
  /// wrap-up (add-another + invites) runs after creation. Deliberately
  /// compact (shrink-wrapped chips on their own line under the label, no
  /// extra breathing room): the form must keep fitting — Continue
  /// reachable without scrolling — on the small surfaces it fit on
  /// before this issue.
  Widget _whoControl(AppLocalizations l10n) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        l10n.firstRunWhoLabel,
        key: const ValueKey('first-run-who-label'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      Wrap(
        key: const ValueKey('first-run-who-chips'),
        spacing: 8,
        children: [
          ChoiceChip(
            key: const ValueKey('first-run-who-me'),
            label: Text(l10n.firstRunWhoMe),
            selected: _who == _FirstRunWho.me,
            onSelected: (_) => _onWhoChanged(_FirstRunWho.me),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          ChoiceChip(
            key: const ValueKey('first-run-who-someone'),
            label: Text(l10n.firstRunWhoSomeone),
            selected: _who == _FirstRunWho.someone,
            onSelected: (_) => _onWhoChanged(_FirstRunWho.someone),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          ChoiceChip(
            key: const ValueKey('first-run-who-both'),
            label: Text(l10n.firstRunWhoBoth),
            selected: _who == _FirstRunWho.both,
            onSelected: (_) => _onWhoChanged(_FirstRunWho.both),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
      // #994: the compact, shrink-wrapped chips remove the Material
      // minimum-height slack that used to separate them from the Name
      // field's floating label, so the label drew across the chips' bottom
      // edge. Space them like every other stacked control on this card.
      const SizedBox(height: LLSpace.space3),
    ],
  );

  /// Issue #804: the relationship dropdown on a cared-for card. `self` is
  /// not offered — the "Me" answer covers it — and the display labels are
  /// the domain enum's own (the same convention the care-mode dropdown
  /// and the profile edit dialog use).
  Widget _relationshipField(AppLocalizations l10n) => MergeSemantics(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            l10n.firstRunRelationshipLabel,
            key: const ValueKey('first-run-relationship-label'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        DropdownButton<ProfileRelationship>(
          key: const ValueKey('first-run-relationship-dropdown'),
          value: _relationship,
          isExpanded: true,
          onChanged: (value) {
            if (value != null) _onRelationshipChanged(value);
          },
          items: [
            for (final relationship in _caredForRelationships)
              DropdownMenuItem<ProfileRelationship>(
                value: relationship,
                child: Text(relationship.label),
              ),
          ],
        ),
      ],
    ),
  );

  /// The minor checkbox and its one-line truthful hint (#216/#882), kept
  /// verbatim from the pre-#804 form. The *default* now depends on the
  /// who-answer/relationship (`_applyRelationshipDefaults`); the control
  /// itself stays user-changeable in every case.
  Widget _minorSection(AppLocalizations l10n) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CheckboxListTile(
        value: _isMinor,
        onChanged: (value) => setState(() => _isMinor = value ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        title: Text(l10n.firstRunMinorLabel),
      ),
      Padding(
        padding: const EdgeInsets.only(left: 12, bottom: 4),
        child: Text(
          l10n.firstRunMinorHint,
          key: const ValueKey('first-run-minor-hint'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ],
  );

  /// The minimum-age acknowledgement (Issue #269), extracted verbatim so
  /// [_nameFormScreen] stays inside the CRAP gate.
  Widget _ageAckSection(AppLocalizations l10n) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CheckboxListTile(
        key: const ValueKey('first-run-age-ack-checkbox'),
        value: _ageAcknowledged,
        onChanged: (value) => setState(() {
          _ageAcknowledged = value ?? false;
          if (_ageAcknowledged) _ageAckError = false;
        }),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        title: Text(l10n.firstRunAgeAcknowledgementLabel),
      ),
      Padding(
        padding: const EdgeInsets.only(left: 12, bottom: 4),
        child: Text(
          _ageAckError
              ? l10n.firstRunAgeAcknowledgementRequired
              : l10n.firstRunAgeAcknowledgementHint,
          key: const ValueKey('first-run-age-ack-hint'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: _ageAckError
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ],
  );

  /// The care-mode picker (#131) plus — issue #804 — the one-line note
  /// that Teen was a *suggestion* when it was preselected for a minor's
  /// card. Suggested, never forced: the dropdown stays fully changeable.
  Widget _careModeSection(AppLocalizations l10n) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // #557: MergeSemantics folds the label into the dropdown's
      // own announcement, so a screen reader hears the question
      // ("Care mode") instead of just the bare selected value.
      MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.firstRunCareModeLabel,
                key: const ValueKey('care-mode-label'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            DropdownButton<ProfileMode>(
              key: const ValueKey('care-mode-dropdown'),
              value: _mode,
              isExpanded: true,
              onChanged: (value) =>
                  setState(() => _mode = value ?? ProfileMode.standard),
              items: [
                // Issue #853: `irregular` is a legacy wire value,
                // not a choice — the framing is the composed flag
                // (editable later from the profile's edit dialog),
                // never a rival entry in this dropdown.
                for (final mode in ProfileMode.choosableModes)
                  DropdownMenuItem<ProfileMode>(
                    value: mode,
                    child: Text(mode.label),
                  ),
              ],
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          _mode.hint,
          key: const ValueKey('care-mode-hint'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      if (_mode == ProfileMode.teen &&
          _caredForCard &&
          _isChildRelationship(_relationship))
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            l10n.firstRunTeenSuggestedHint,
            key: const ValueKey('first-run-teen-hint'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
    ],
  );

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
      body: SafeArea(
        top: false,
        child: ResponsiveBody(
          child: Form(
          key: _cycleFormKey,
          child: ListView(
          padding: const EdgeInsets.all(LLSpace.space4),
          children: [
            Text(l10n.firstRunCycleCaption),
            const SizedBox(height: LLSpace.space4),
            _lastPeriodField(l10n),
            const SizedBox(height: LLSpace.space3),
            TextFormField(
              key: const ValueKey('cycle-typical-cycle'),
              controller: _typicalCycleController,
              focusNode: _typicalCycleFocus,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => _typicalPeriodFocus.requestFocus(),
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
            const SizedBox(height: LLSpace.space3),
            TextFormField(
              key: const ValueKey('cycle-typical-period'),
              controller: _typicalPeriodController,
              focusNode: _typicalPeriodFocus,
              keyboardType: TextInputType.number,
              // #165: the form's last text field — "done" submits (the
              // Create profile action, the same one the button performs).
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _create(),
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
            const SizedBox(height: LLSpace.space3),
            MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _labelAbove(
                    l10n.firstRunCycleBirthControlLabel,
                    const ValueKey('cycle-birth-control-label'),
                  ),
                  DropdownButton<BirthControlChoice>(
                    key: const ValueKey('cycle-birth-control'),
                    value: _birthControl,
                    isExpanded: true,
                    onChanged: (value) => setState(
                       () => _birthControl =
                          value ?? BirthControlChoice.notAnswered,
                    ),
                    items: [
                      for (final choice in BirthControlChoice.values)
                        DropdownMenuItem<BirthControlChoice>(
                          value: choice,
                          child: Text(birthControlChoiceLabel(choice, l10n)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: LLSpace.space3),
            MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _labelAbove(
                    l10n.firstRunCycleGoalLabel,
                    const ValueKey('cycle-goal-label'),
                  ),
                  DropdownButton<LifecycleMode>(
                    key: const ValueKey('cycle-goal'),
                    value: _lifecycleMode,
                    isExpanded: true,
                    onChanged: (value) => setState(
                      () => _lifecycleMode = value ?? LifecycleMode.tracking,
                    ),
                    items: [
                      for (final mode in LifecycleMode.values)
                        DropdownMenuItem<LifecycleMode>(
                          value: mode,
                          child: Text(mode.label),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: LLSpace.space4),
            FilledButton(
              key: const ValueKey('cycle-create'),
              onPressed: _creating ? null : _create,
              child: _creating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.firstRunCreateButton),
            ),
            if (_createError != null) ...[
              const SizedBox(height: LLSpace.space2),
              InlineError(
                key: const ValueKey('cycle-create-error'),
                message: _createError!,
                onRetry: _creating ? null : _create,
              ),
            ],
          ],
          ),
        ),
      ),
    ),
  );
  }

  /// Issue #804: the shortened cycle step for a cared-for card — the one
  /// optional last-period question with a caption that names the skip
  /// ("not sure? just continue"; the Create button *is* the skip). A
  /// parent often does not know her daughter's typical lengths, and
  /// #218's seeding tolerates blanks, so the full five questions would
  /// only be noise here.
  Widget _shortCycleScreen() {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.firstRunCreateTitle),
        leading: BackButton(
          onPressed: () => setState(() => _cycleShortPending = false),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ResponsiveBody(
          child: ListView(
            padding: const EdgeInsets.all(LLSpace.space4),
            children: [
              Text(l10n.firstRunCycleShortCaption),
              const SizedBox(height: LLSpace.space4),
              _lastPeriodField(l10n),
              const SizedBox(height: LLSpace.space4),
              FilledButton(
                key: const ValueKey('cycle-create'),
                onPressed: _creating ? null : _create,
                child: _creating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.firstRunCreateButton),
              ),
              if (_createError != null) ...[
                const SizedBox(height: LLSpace.space2),
                InlineError(
                  key: const ValueKey('cycle-create-error'),
                  message: _createError!,
                  onRetry: _creating ? null : _create,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Issue #804: the household wrap-up step — after a cared-for (or
  /// "Both"-flow) creation, loop back for the next person or move on to
  /// the invite step. Ending the flow is always one tap away
  /// ("Continue"), and without a [SharingService] "Continue" ends it
  /// directly (nothing to invite with).
  Widget _wrapUpScreen() {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.firstRunWrapUpTitle)),
      body: SafeArea(
        top: false,
        child: ResponsiveBody(
          child: Padding(
            padding: const EdgeInsets.all(LLSpace.space4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.firstRunWrapUpBody,
                  key: const ValueKey('first-run-wrap-up'),
                ),
                const SizedBox(height: LLSpace.space4),
                FilledButton(
                  key: const ValueKey('first-run-add-another'),
                  onPressed: _resetForNextPerson,
                  child: Text(l10n.firstRunWrapUpAddAnother),
                ),
                const SizedBox(height: LLSpace.space3),
                OutlinedButton(
                  key: const ValueKey('first-run-wrap-up-continue'),
                  onPressed: _toInviteStep,
                  child: Text(l10n.firstRunContinue),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Issue #804: "Add another guardian?" — one row per profile created
  /// in this flow, each offering the guardian invite and (per #966's
  /// gating, via [Profile.subjectInviteAvailableAt]) the subject preset
  /// for a minor's own profile. This is the first place an account is
  /// required: without a session the rows wait behind the why-line and
  /// the sign-in button, and "Skip for now" always ends the flow.
  Widget _inviteStepScreen(AuthController? auth) {
    final l10n = AppLocalizations.of(context);
    final sharing = context.read<SharingService?>();
    final needsSignIn = auth != null && !auth.state.hasUsableSession;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.firstRunInviteTitle),
        leading: BackButton(onPressed: _backToWrapUp),
      ),
      body: SafeArea(
        top: false,
        child: ResponsiveBody(
          child: ListView(
            padding: const EdgeInsets.all(LLSpace.space4),
            children: [
              Text(
                l10n.firstRunInviteBody(_createdProfiles.length),
                key: const ValueKey('first-run-invite-step'),
              ),
              if (needsSignIn) ...[
                const SizedBox(height: LLSpace.space3),
                Text(
                  l10n.firstRunInviteWhyAccount,
                  key: const ValueKey('first-run-invite-why-account'),
                ),
                const SizedBox(height: LLSpace.space3),
                FilledButton(
                  key: const ValueKey('first-run-invite-sign-in'),
                  onPressed: () => setState(() => _accountPending = true),
                  child: Text(l10n.firstRunInviteSignInAction),
                ),
              ],
              if (!needsSignIn && sharing != null)
                for (final profile in _createdProfiles)
                  _inviteRow(profile, sharing),
              const SizedBox(height: LLSpace.space4),
              OutlinedButton(
                key: ValueKey(
                  needsSignIn ? 'first-run-invite-skip' : 'first-run-invite-done',
                ),
                onPressed: _finishFlow,
                child: Text(
                  needsSignIn
                      ? l10n.firstRunInviteSkip
                      : l10n.firstRunInviteDone,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One created profile's invite affordances, split out of
  /// [_inviteStepScreen] for the CRAP gate's per-method complexity cap.
  Widget _inviteRow(Profile profile, SharingService sharing) {
    final l10n = AppLocalizations.of(context);
    final subjectAvailable =
        profile.subjectInviteAvailableAt(widget.todayProvider().toDateTime());
    return Padding(
      padding: const EdgeInsets.only(bottom: LLSpace.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            profile.displayName,
            key: ValueKey('first-run-invite-profile-${profile.id}'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: LLSpace.space2),
          OverflowBar(
            spacing: 8,
            overflowSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: ValueKey('first-run-invite-coparent-${profile.id}'),
                onPressed: () => unawaited(_openInviteDialog(
                  profile,
                  sharing,
                  subjectInviteAvailable: false,
                )),
                icon: const Icon(Icons.group_add, size: 18),
                label: Text(l10n.firstRunInviteCoParent),
              ),
              if (subjectAvailable)
                OutlinedButton.icon(
                  key: ValueKey('first-run-invite-subject-${profile.id}'),
                  onPressed: () => unawaited(_openInviteDialog(
                    profile,
                    sharing,
                    subjectInviteAvailable: true,
                  )),
                  icon: const Icon(Icons.person_add_alt, size: 18),
                  label: Text(l10n.inviteSubjectOption(profile.displayName)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _lastPeriodField(AppLocalizations l10n) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _labelAbove(
        l10n.firstRunCycleLastPeriodLabel,
        const ValueKey('cycle-last-period-label'),
      ),
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
                formatLocalDateMonthDayYear(_lastPeriodStart!),
                key: const ValueKey('cycle-last-period-value'),
              ),
            ),
            TextButton(
              onPressed: _pickLastPeriodDate,
              child: Text(l10n.firstRunCycleChangeDate),
            ),
            TextButton(
              key: const ValueKey('cycle-last-period-clear'),
              onPressed: () => setState(() => _lastPeriodStart = null),
              child: Text(l10n.firstRunCycleClearDate),
            ),
          ],
        ),
    ],
  );

  Widget _labelAbove(String label, Key key) => Align(
    alignment: Alignment.centerLeft,
    child: Text(label, key: key, style: Theme.of(context).textTheme.bodySmall),
  );

  /// Optional-day-count validation: blank passes (the question is
  /// skippable); anything else must parse as a whole number inside
  /// [min]–[max] inclusive, else [errorMessage].
  String? _validateDayRange(
    String? value,
    String errorMessage,
    int min,
    int max,
  ) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final parsed = int.tryParse(trimmed);
    if (parsed == null || parsed < min || parsed > max) {
      return errorMessage;
    }
    return null;
  }
}
