/// Contextual offline help cards (Issue #139, R17/U7).
///
/// Every card is a compile-time constant: title, summary, body paragraphs,
/// source, and review date all ship in the app bundle, so every card opens
/// with no network. Copy rules (enforced by `test/domain/help/`):
/// - No fertility content — nothing about fertile windows, ovulation, or
///   conception, educational or otherwise (PRIVACY.md binding constraint).
/// - No individualised medical advice — cards explain the app and general
///   cycle literacy only. Estimates always sit next to the "Estimates only"
///   framing, and worry is always routed to a clinician, never answered.
/// - Every card carries a non-empty [source] and [reviewDate] (provenance).
/// - Every card names at least one [screens] trigger: the screen whose
///   question it answers. [byScreen] is the trigger map.
library;

/// One bundled help card.
class HelpCard {
  const HelpCard({
    required this.id,
    required this.title,
    required this.summary,
    required this.body,
    required this.source,
    required this.reviewDate,
    required this.screens,
  });

  /// Stable key, also used for widget keys (`help-link-<id>`).
  final String id;

  /// Short heading shown in the sheet and the library list.
  final String title;

  /// One or two sentences shown under the title.
  final String summary;

  /// The card copy, rendered as paragraphs. Explains the app and general
  /// cycle literacy only — never individualised medical advice.
  final List<String> body;

  /// Where the card's claims come from (app behaviour and/or a public
  /// patient-education source).
  final String source;

  /// ISO-8601 review date (`YYYY-MM-DD`) the copy was last reviewed.
  final String reviewDate;

  /// Screen keys whose question this card answers (see [HelpCards.byScreen]).
  final List<String> screens;
}

/// The bundled card set (24 cards) and its trigger map.
class HelpCards {
  const HelpCards._();

  static const String _reviewDate = '2026-09-11';
  static const String _appPredictionSource =
      'LunarLog prediction engine (lib/domain/prediction/prediction.dart)';
  static const String _appBehaviourSource = 'LunarLog app behaviour';
  static const String _appSharingSource =
      'LunarLog sharing model (lib/domain/models/profile_guardian.dart)';
  static const String _literacySource =
      'American College of Obstetricians and Gynecologists (ACOG), '
      'patient education on menstruation';

  static const HelpCard whyNoEstimateYet = HelpCard(
    id: 'why-no-estimate-yet',
    title: 'Why no estimate yet?',
    summary:
        'The app waits for three completed cycles before it estimates '
        'anything. This is working as intended.',
    body: [
      'A period estimate is an average of past cycle lengths. With fewer '
          'than three completed cycles there is nothing honest to average, '
          'so the app shows "not enough history yet" instead of guessing.',
      'A cycle counts once a new period starts after the last one. Cycles '
          'shorter than 15 days or longer than 60 days stay in history but '
          'never feed the average, because they would pull it away from '
          'the usual pattern.',
      'Keep logging period starts. The estimate appears on its own once '
          'three usable cycles are recorded — usually around three months '
          'of logging.',
      'Estimates only — not medical advice. If something worries you, talk '
          'to a doctor or another clinician you trust.',
    ],
    source: _appPredictionSource,
    reviewDate: _reviewDate,
    screens: ['overview-not-enough', 'analysis-not-enough'],
  );

  static const HelpCard confidenceLevels = HelpCard(
    id: 'confidence-levels',
    title: 'What the confidence label means',
    summary:
        'High, Learning, Irregular, and Provisional say how steady the '
        'logged history behind an estimate is.',
    body: [
      'High means recent cycles are steady, so the estimate is at its most '
          'reliable. Learning means there are only a few usable cycles so '
          'far — the estimate improves as more are logged.',
      'Irregular means logged cycles vary a lot, so the estimate is a '
          'rough guide. A range is shown instead of a single date whenever '
          'the label is not High.',
      'Provisional means the estimate comes from onboarding answers, not '
          'logged cycles yet. It is replaced by a computed estimate once '
          'three real cycles are recorded.',
      'Estimates only — not medical advice.',
    ],
    source: _appPredictionSource,
    reviewDate: _reviewDate,
    screens: ['overview-estimate', 'analysis-stats'],
  );

  static const HelpCard whatEstimateMeans = HelpCard(
    id: 'what-estimate-means',
    title: 'What the next-period estimate is',
    summary:
        'The average of recent cycle lengths added to the last period '
        'start. An average, not a promise.',
    body: [
      'The app takes the most recent usable cycle lengths, averages them, '
          'and counts that many days forward from the last logged period '
          'start. That date is the estimate.',
      'When recent cycles differ from each other, the app shows a range '
          '(a few days either side of the estimate) instead of one exact '
          'date. Wider spread means a wider range.',
      'Logging more cycles sharpens the average. Skipped or unusual cycles '
          'can be left out of the average from the history list without '
          'deleting them.',
      'Estimates only — not medical advice.',
    ],
    source: _appPredictionSource,
    reviewDate: _reviewDate,
    screens: ['overview-estimate', 'month-calendar'],
  );

  static const HelpCard periodLate = HelpCard(
    id: 'period-late',
    title: 'Why the app says a period is late',
    summary:
        '"Late" only means today is past the estimated date. The estimate '
        'is an average, and averages miss.',
    body: [
      'The app compares today with the estimated next start. A few days '
          'past it, the resolver offers three options: log the period, '
          'skip this cycle, or be reminded again in three days.',
      'Logging the period closes the cycle and the whole estimate '
          'recomputes. Skipping leaves the cycle in history but out of the '
          'average, and moves the estimate one average cycle later.',
      'A late estimate is not a statement about anyone\u2019s body — it '
          'only means nothing logged yet lines up with the average. If '
          'something worries you, talk to a doctor or another clinician '
          'you trust.',
      'Estimates only — not medical advice.',
    ],
    source: _appPredictionSource,
    reviewDate: _reviewDate,
    screens: ['late-resolver'],
  );

  static const HelpCard unusuallyLongCycle = HelpCard(
    id: 'unusually-long-cycle',
    title: 'Why a cycle is called unusually long',
    summary:
        'Sixty days without a new logged period start. The app keeps '
        'showing an estimate instead of going quiet.',
    body: [
      'Once the open cycle passes sixty days, the app flags it as '
          'unusually long and treats the estimate as a rough guide. Logging '
          'a period is what closes the cycle.',
      'The estimate keeps rolling forward in whole average-cycle steps so '
          'reminders and the calendar always have a live date, while the '
          'count of days since the estimate keeps growing alongside it.',
      'Estimates only — not medical advice. If something worries you, talk '
          'to a doctor or another clinician you trust.',
    ],
    source: _appPredictionSource,
    reviewDate: _reviewDate,
    screens: ['late-resolver'],
  );

  static const HelpCard skipCycleOmit = HelpCard(
    id: 'skip-cycle-omit',
    title: 'Skipping a cycle in the average',
    summary:
        'An unusual cycle can be left out of the average without deleting '
        'it. History stays complete; the maths stays honest.',
    body: [
      '"Skip this cycle" marks the open cycle\u2019s start as omitted. The '
          'estimate advances one average cycle, and when the next period is '
          'logged, that cycle\u2019s real length never feeds the mean.',
      'Omitted cycles stay visible in history. The omission can be undone '
          'from the history list, which puts the cycle back into the '
          'average.',
      'Use this for cycles you know were unusual — for example after '
          'illness, travel, or a missed log — rather than deleting entries.',
    ],
    source: _appBehaviourSource,
    reviewDate: _reviewDate,
    screens: ['cycle-history', 'late-resolver'],
  );

  static const HelpCard cycleDay = HelpCard(
    id: 'cycle-day',
    title: 'What "cycle day" means',
    summary:
        'Cycle day 1 is the first day of bleeding of a period. Every '
        'following day counts up from there.',
    body: [
      'The app numbers each day from the most recent logged period start: '
          'that day is cycle day 1, the next day is cycle day 2, and so on '
          'until the next period starts a new count.',
      'While today falls inside logged bleeding days, the app simply says '
          '"period" instead of a number.',
      'The count restarts only when a new period start is logged — editing '
          'or deleting that entry moves the whole count.',
    ],
    source: _literacySource,
    reviewDate: _reviewDate,
    screens: ['overview-estimate', 'day-sheet'],
  );

  static const HelpCard periodLengthAverage = HelpCard(
    id: 'period-length-average',
    title: 'What the average period length is',
    summary:
        'The average number of bleeding days per period, taken from '
        'recently logged periods.',
    body: [
      'Each logged period contributes its bleed length — how many days in a '
          'row bleeding was logged. The app averages the most recent ones.',
      'This average shapes how many days the calendar shades as bleeding '
          'around the next estimate. Logging full periods, start to finish, '
          'keeps it accurate.',
      'Estimates only — not medical advice.',
    ],
    source: _appPredictionSource,
    reviewDate: _reviewDate,
    screens: ['analysis-stats'],
  );

  static const HelpCard logPeriod = HelpCard(
    id: 'log-period',
    title: 'How to log a period',
    summary:
        'Open a day, record bleeding, and the app does the rest. One tap '
        'on today is enough to start.',
    body: [
      'Each day holds one entry: flow level, tracked options, and an '
          'optional note. Logging bleeding on a day marks it as a bleeding '
          'day; consecutive bleeding days form a period.',
      'The quick-log action on the overview records today in one tap. The '
          'calendar opens any day — past days can be filled in later, so a '
          'forgotten day is never lost.',
      'Everything works offline. Entries sync to the account\u2019s other '
          'devices the next time the device is online and signed in.',
    ],
    source: _appBehaviourSource,
    reviewDate: _reviewDate,
    screens: ['day-sheet', 'month-calendar'],
  );

  static const HelpCard flowLevels = HelpCard(
    id: 'flow-levels',
    title: 'What the flow levels mean',
    summary:
        'A simple scale from "not bleeding" to "super heavy", plus '
        'spotting as its own tracked option.',
    body: [
      'Each logged day carries one flow level: not bleeding, light, '
          'medium, heavy, or super heavy. The level describes that day only '
          '— pick what fits best, there is no measurement to take.',
      'Spotting is tracked separately from flow, as one of the day\u2019s '
          'options. Light staining between periods is logged there rather '
          'than as a light-flow day, which keeps period boundaries honest.',
      '"Not bleeding today" is an explicit note, different from leaving a '
          'day unlogged. It tells the record the day was seen and there was '
          'nothing to log.',
    ],
    source: _appBehaviourSource,
    reviewDate: _reviewDate,
    screens: ['flow-levels', 'day-sheet'],
  );

  static const HelpCard tagsNotes = HelpCard(
    id: 'tags-notes',
    title: 'What tags and notes are for',
    summary:
        'Tags are quick labels; notes are free text. Both are personal '
        'memory aids attached to a day.',
    body: [
      'Tags mark a day with a short label so patterns are easy to spot '
          'later. A day can carry several tags, and the same tag can repeat '
          'across days.',
      'Notes hold anything a label cannot — a sentence or two in your own '
          'words. Notes are optional on every day.',
      'Tags and notes are visible to anyone the profile is shared with, '
          'under the same rules as the rest of the day\u2019s entry.',
    ],
    source: _appBehaviourSource,
    reviewDate: _reviewDate,
    screens: ['tags-notes', 'day-sheet'],
  );

  static const HelpCard trackedSymptoms = HelpCard(
    id: 'tracked-symptoms',
    title: 'What tracked options are',
    summary:
        'One row per logged option — pain, mood, sleep, and more — tied '
        'to the day it was logged.',
    body: [
      'Beyond flow, each day can record any number of tracked options: '
          'pains, feelings, sleep, and other body and mind signals, each '
          'with its own detail where it fits.',
      'Options are stored as their own records on the day, the same way '
          'flow is. Logging a few consistently matters more than logging '
          'many occasionally.',
      'These records follow the same storage, sync, and sharing rules as '
          'every other entry on the profile.',
    ],
    source: _appBehaviourSource,
    reviewDate: _reviewDate,
    screens: ['symptoms', 'day-sheet'],
  );

  static const HelpCard editDeleteEntry = HelpCard(
    id: 'edit-delete-entry',
    title: 'Editing or deleting an entry',
    summary:
        'Any day can be changed or removed. Deleting keeps the day\u2019s '
        'place but clears what it carried.',
    body: [
      'Opening a logged day lets you change its flow, options, or note. '
          'Saving overwrites that day only — nothing else in history moves.',
      'Deleting an entry clears its content while keeping its place in the '
          'record, so a removed day never silently shifts the days around '
          'it. Deleted content syncs as deleted to every device.',
      'Fixing a mis-logged day sooner keeps estimates sharper, but there '
          'is no deadline — history can be corrected at any time.',
    ],
    source: _appBehaviourSource,
    reviewDate: _reviewDate,
    screens: ['day-sheet', 'cycle-history'],
  );

  static const HelpCard syncWhat = HelpCard(
    id: 'sync-what',
    title: 'What syncs and what does not',
    summary:
        'Signing in syncs profiles and day entries across devices and to '
        'other guardians. Nothing uploads before sign-in.',
    body: [
      'With an account, profiles and their day entries sync across the '
          'guardian\u2019s own devices and to every guardian a profile is '
          'shared with. Estimates are always computed on-device from the '
          'synced history — the server never computes them.',
      'Before sign-in, everything stays on the device. Signing in on a '
          'device that already holds entries asks for consent before '
          'uploading them.',
      'Support tickets, crash reports, and push tokens are separate flows '
          'with their own consent steps — they are never part of entry '
          'sync.',
    ],
    source: _appBehaviourSource,
    reviewDate: _reviewDate,
    screens: ['settings-sync', 'first-run'],
  );

  static const HelpCard offlineMode = HelpCard(
    id: 'offline-mode',
    title: 'Using the app with no network',
    summary:
        'Logging, viewing, and estimates all run from the copy on the '
        'device. Airplane mode changes nothing.',
    body: [
      'The app keeps a full local copy of every profile on the device. '
          'Logging a day, reading history, and viewing estimates never need '
          'a connection.',
      'Changes made offline are marked and sent the next time the device '
          'is online and signed in. Two devices editing at once converge on '
          'the newest write per field.',
      'Exporting data also works fully offline, since it is built from the '
          'same on-device copy.',
    ],
    source: _appBehaviourSource,
    reviewDate: _reviewDate,
    screens: ['settings-sync'],
  );

  static const HelpCard exportData = HelpCard(
    id: 'export-data',
    title: 'Getting a copy of your data',
    summary:
        'Settings → Your data → Export builds a file from the on-device '
        'copy. No account needed.',
    body: [
      'The export covers every profile and day entry on the device — owned '
          'profiles and shared ones alike. While signed in and online it '
          'additionally merges the account\u2019s own server-side record, '
          'such as memberships and preferences.',
      'The file is handed to the device\u2019s share sheet, so the '
          'destination is always your choice. A second, clinician-readable '
          'format is offered from the same place.',
      'On a shared or borrowed device, review the file before passing it '
          'on — it reflects everything that account can currently see.',
    ],
    source: _appBehaviourSource,
    reviewDate: _reviewDate,
    screens: ['settings-export'],
  );

  static const HelpCard deleteData = HelpCard(
    id: 'delete-data',
    title: 'Deleting entries, profiles, and accounts',
    summary:
        'Entries, profiles, and the whole account delete at three '
        'different levels. Each is immediate.',
    body: [
      'A single entry deletes from its day. A profile deletes from the app '
          'with its full history. Both sync as deleted to every device.',
      'Deleting the account (Settings → Account) removes every server row '
          'the account owns, the account itself, and the device\u2019s '
          'local data. A profile already transferred to someone else is '
          'theirs and is not removed.',
      'The confirmation offers to export first. Deleted data cannot be '
          'recovered by the app\u2019s operator.',
    ],
    source: _appBehaviourSource,
    reviewDate: _reviewDate,
    screens: ['settings-export', 'profiles-list'],
  );

  static const HelpCard reminders = HelpCard(
    id: 'reminders',
    title: 'How reminders work',
    summary:
        'Local reminders nudge logging and flag estimates. They fire '
        'on-device and carry no entry content.',
    body: [
      'Reminders are configured per profile and fire on the device itself. '
          'A missed-entry reminder appears when an expected log has not '
          'arrived; estimate reminders follow the next-period estimate.',
      'Push alerts to another guardian are optional, off by default, and '
          'always use the same fixed generic wording — never entry content.',
      'With too little history for an estimate, there is nothing to remind '
          'about yet. Reminders begin once estimates do.',
    ],
    source: _appBehaviourSource,
    reviewDate: _reviewDate,
    screens: ['reminders', 'overview-estimate'],
  );

  static const HelpCard guardianRoles = HelpCard(
    id: 'guardian-roles',
    title: 'What the guardian roles allow',
    summary:
        'Four roles, from most to least access: primary guardian, '
        'co-parent, caregiver, viewer.',
    body: [
      'The primary guardian owns the profile: they can edit it, manage '
          'guardians, and delete it. There is exactly one per profile. A '
          'co-parent can log entries, edit the profile, and manage '
          'guardians, but cannot delete the profile.',
      'A caregiver can log entries on the profile but cannot change the '
          'profile itself or manage guardians. A viewer can only read — '
          'the day sheet is read-only for them.',
      'Every entry keeps who logged it, so shared logging stays '
          'attributed no matter the mix of roles.',
    ],
    source: _appSharingSource,
    reviewDate: _reviewDate,
    screens: ['manage-guardians'],
  );

  static const HelpCard invitations = HelpCard(
    id: 'invitations',
    title: 'How invitations work',
    summary:
        'A guardian creates an invitation link for one role. The link '
        'expires after 48 hours and is single-use.',
    body: [
      'Invitations are created from the profile\u2019s guardian screen by '
          'someone allowed to manage guardians. The link carries the role '
          'it was created for — the recipient cannot choose a higher one.',
      'Each link works once and expires 48 hours after it is created. An '
          'expired or already-used link simply stops working; a fresh one '
          'can be created any time.',
      'Outstanding invitations are listed on the same screen and can be '
          'cancelled there before they are used.',
    ],
    source: _appSharingSource,
    reviewDate: _reviewDate,
    screens: ['invite-dialog', 'pending-invites', 'manage-guardians'],
  );

  static const HelpCard revocation = HelpCard(
    id: 'revocation',
    title: 'What removing a guardian does',
    summary:
        'Removal ends access immediately and cancels that profile\u2019s '
        'open invitations. Logged history stays.',
    body: [
      'A removed guardian can no longer read or log on the profile, and '
          'their alert settings for it stop. Entries they logged while they '
          'had access stay in history with their original attribution.',
      'Removing any guardian also cancels every still-open invitation for '
          'that profile, so no link created earlier can be used afterwards.',
      'Only the primary guardian and co-parents can remove guardians, and '
          'the primary guardian\u2019s own access cannot be removed this '
          'way — ownership moves only through a transfer.',
    ],
    source: _appSharingSource,
    reviewDate: _reviewDate,
    screens: ['revoke-guardian', 'manage-guardians'],
  );

  static const HelpCard ownershipTransfer = HelpCard(
    id: 'ownership-transfer',
    title: 'How ownership transfer works',
    summary:
        'A one-way handover of a profile to its own account. The parent '
        'chooses to stay on as co-manager or drop to read-only.',
    body: [
      'Only the primary guardian can arm a transfer. It creates a '
          'single-use link that expires after 72 hours; claiming it moves '
          'profile ownership and the primary-guardian seat to the new '
          'account in one step.',
      'The parent picks a continuing role when arming: co-manager to keep '
          'logging, or viewer for read-only. Afterwards that access is an '
          'ordinary membership — the new owner can remove it at any time.',
      'Every past entry keeps its original "logged by" attribution, and the '
          'transfer is one-way: there is no undo, only a new transfer back.',
    ],
    source: _appSharingSource,
    reviewDate: _reviewDate,
    screens: ['transfer-ownership', 'claim-profile', 'manage-guardians'],
  );

  static const HelpCard familyProfilesMinors = HelpCard(
    id: 'family-profiles-minors',
    title: 'Profiles for family members',
    summary:
        'One operator can keep profiles for several people, including '
        'minors. A minor flag marks a young person\u2019s profile.',
    body: [
      'Each profile has its own name, history, estimates, and guardian '
          'list. Switching profiles never mixes entries between people.',
      'Marking a profile as a minor\u2019s records that it belongs to a '
          'young person. Minor profiles are never shared outside their '
          'guardians, and they can later be transferred to the young '
          'person\u2019s own account when ready.',
      'Archiving hides a profile from the everyday list without deleting '
          'it. Archived profiles are read-only until restored.',
    ],
    source: _appBehaviourSource,
    reviewDate: _reviewDate,
    screens: ['profiles-list', 'first-run', 'manage-guardians'],
  );

  static const HelpCard privacyAtAGlance = HelpCard(
    id: 'privacy-at-a-glance',
    title: 'Privacy at a glance',
    summary:
        'On-device first, account-optional, and protected by the device '
        'lock. The full policy lives in Settings.',
    body: [
      'Entries live on the device under the operating system\u2019s own '
          'protection and only appear behind the device lock. Nothing '
          'leaves the device until an account is created and sign-in '
          'uploads it.',
      'Sharing is always explicit: a profile is visible to exactly the '
          'guardians listed on it, each with the role shown there. Nobody '
          'else — no advertisers, no data brokers — receives anything.',
      'Crash reports are scrubbed on-device before sending so they never '
          'carry health data, notes, dates, or names.',
    ],
    source: _appBehaviourSource,
    reviewDate: _reviewDate,
    screens: ['settings-privacy', 'first-run'],
  );

  /// Every bundled card, in library order.
  static const List<HelpCard> all = [
    whyNoEstimateYet,
    confidenceLevels,
    whatEstimateMeans,
    periodLate,
    unusuallyLongCycle,
    skipCycleOmit,
    cycleDay,
    periodLengthAverage,
    logPeriod,
    flowLevels,
    tagsNotes,
    trackedSymptoms,
    editDeleteEntry,
    syncWhat,
    offlineMode,
    exportData,
    deleteData,
    reminders,
    guardianRoles,
    invitations,
    revocation,
    ownershipTransfer,
    familyProfilesMinors,
    privacyAtAGlance,
  ];

  /// Card lookup by [id], or null for an unknown id.
  static HelpCard? byId(String id) {
    for (final card in all) {
      if (card.id == id) return card;
    }
    return null;
  }

  /// Trigger map: screen key → the cards answering that screen\u2019s
  /// question. Every card appears under each of its [HelpCard.screens].
  static Map<String, List<HelpCard>> get byScreen {
    final map = <String, List<HelpCard>>{};
    for (final card in all) {
      for (final screen in card.screens) {
        (map[screen] ??= []).add(card);
      }
    }
    return map;
  }

  /// The cards for [screen], or an empty list when the screen has none.
  static List<HelpCard> forScreen(String screen) =>
      byScreen[screen] ?? const [];
}
