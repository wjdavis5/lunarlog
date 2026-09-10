/// Birth-control vocabulary (Issue #260): the canonical tracked-method
/// ids stored in `profile_modes.birth_control_method`, the six per-day
/// intake observation categories, and the pill's per-day adherence
/// values.
///
/// THREE storage facts, two surfaces (the issue's dual model — both are
/// persisted, neither is derived from the other):
///
/// 1. **Profile-level current method** lives in #188's
///    `profile_modes.birth_control_method` (with
///    `birth_control_started_on`/`birth_control_stopped_on` effective
///    dates). That column was landed deliberately free-text by
///    20260909000000_profile_modes_and_cycle_overrides.sql ("#260 owns
///    that vocabulary"); this module now owns it: [BirthControlMethod]
///    is the closed set of values lunarlog itself writes, and
///    [BirthControlMethod.fromDb] is the total read. Changing the stored
///    method never rewrites any observation row — they are different
///    tables (see the pgTAP guarantee in
///    `supabase/tests/birth_control_test.sql`).
/// 2. **Per-day intake** lives in #240's `observations` child table as a
///    `birth_control_*` category family: one category per Clue method
///    ([kBirthControlCategories]), one row per logged day. A missed pill
///    day does not mean the method changed, so nothing here infers the
///    profile-level method from intake rows (A1-29's explicit warning).
/// 3. **Pill adherence** is the pill category's per-day value
///    ([PillAdherence] — the code on the intake row).
///
/// Unverified-confidence caveat (A1-29, binding): Clue's exact option
/// strings for the pill-adherence values — and for the non-pill methods'
/// per-day values, if any — are not publicly enumerated. [PillAdherence]'s
/// `taken`/`late`/`missed` strings are the widely-reported shape, pinned
/// here as the working set and **documented as pending pre-ship
/// verification against a real Clue export**. Because `observations.code`
/// is stored-never-rejected (issue #240's D-10 decision), re-pinning a
/// string later is a vocabulary-only change: already-stored rows keep
/// round-tripping either way.
///
/// The other five method categories are presence-based: a logged row
/// carries a null `code` (there is no attested per-day value set to
/// borrow, and the taxonomy's house rule is *never an invented
/// placeholder* — see `lib/domain/tags.dart`'s unverified-category
/// precedent). Future verified values join as codes without any schema
/// change.
///
/// Pure Dart with no drift/Flutter imports (R14/R16) — `test/architecture/`
/// `layering_test.dart` enforces that.
library;

import 'models/local_date.dart';

/// The `observations.category` prefix shared by the six per-day intake
/// categories (the "birth_control category family", issue #260 AC1).
const String kBirthControlCategoryPrefix = 'birth_control_';

/// Per-day pill-intake category (the pill's adherence row lands here).
const String kBirthControlPillCategory = 'birth_control_pill';

/// Presence-only per-day categories (a logged row = the method was
/// recorded for the day; no attested per-day value set yet — see the
/// library doc comment).
const String kBirthControlShotCategory = 'birth_control_shot';
const String kBirthControlImplantCategory = 'birth_control_implant';
const String kBirthControlPatchCategory = 'birth_control_patch';
const String kBirthControlRingCategory = 'birth_control_ring';
const String kBirthControlIudCategory = 'birth_control_iud';

/// The six-method `birth_control` category family (issue #260 AC1), in
/// Clue's own surfacing order. The IUD category intentionally covers both
/// the hormonal and copper flavors — Clue tracks one IUD category; the
/// flavor distinction lives on the profile-level method
/// ([BirthControlMethod.hormonalIud]/[BirthControlMethod.copperIud]),
/// where #216's onboarding question already captured it.
const Set<String> kBirthControlCategories = {
  kBirthControlPillCategory,
  kBirthControlShotCategory,
  kBirthControlImplantCategory,
  kBirthControlPatchCategory,
  kBirthControlRingCategory,
  kBirthControlIudCategory,
};

/// Whether [category] is one of the per-day intake categories.
bool isBirthControlCategory(String? category) =>
    category != null && kBirthControlCategories.contains(category);

/// The pill's per-day adherence value (issue #260 AC2) — the `code` on a
/// [kBirthControlPillCategory] intake row.
///
/// **Pending pre-ship verification (A1-29):** these exact strings are the
/// widely-reported taken/late/missed shape, not a publicly-attested Clue
/// export set; pin against a real export before shipping UI that surfaces
/// them. Stored-never-rejected means a later re-pinning is a
/// vocabulary-only change (see the library doc comment).
enum PillAdherence {
  taken,
  late,
  missed;

  /// The raw string stored on the observation row and sent over the wire.
  String toDb() => switch (this) {
        PillAdherence.taken => 'taken',
        PillAdherence.late => 'late',
        PillAdherence.missed => 'missed',
      };

  /// Normalises a stored `code` back to the enum: an unrecognised value
  /// (a future addition, a re-pinned set, a Clue import's own string)
  /// degrades to null rather than crashing a read — same total-read rule
  /// as [BirthControlMethod.fromDb].
  static PillAdherence? fromDb(String? raw) => switch (raw) {
        'taken' => taken,
        'late' => late,
        'missed' => missed,
        _ => null,
      };
}

/// The canonical birth-control method vocabulary (issue #260), stored in
/// #188's `profile_modes.birth_control_method`.
///
/// Supersedes #216's stopgap (the first-run selector stored localized
/// English labels into the column until this module landed; those legacy
/// values keep parsing via [fromDb]'s legacy table). The six *tracked*
/// methods ([isTracked] — the ones with per-day intake categories and the
/// ones #233/#183/#152 consume) mirror Clue's model; `none`, `condom`,
/// and `other` are the non-tracked answers #216's selector could already
/// store, kept so a stored answer never degrades on read.
enum BirthControlMethod {
  none,
  pill,
  shot,
  implant,
  patch,
  ring,
  hormonalIud,
  copperIud,
  condom,
  other,

  /// Read-only degradation for a stored value this build does not
  /// recognise (a future addition, a row from a newer client) — never
  /// written back by lunarlog ([toDb] throws, keeping an unknown method
  /// from being silently replaced by a known one on a naive round-trip).
  unknown;

  /// The raw string stored in `profile_modes.birth_control_method`.
  ///
  /// Throws on [unknown]: an unrecognised value must fail loudly at the
  /// write site rather than overwrite someone's recorded method with a
  /// placeholder.
  String toDb() => switch (this) {
        BirthControlMethod.none => 'none',
        BirthControlMethod.pill => 'pill',
        BirthControlMethod.shot => 'shot',
        BirthControlMethod.implant => 'implant',
        BirthControlMethod.patch => 'patch',
        BirthControlMethod.ring => 'ring',
        BirthControlMethod.hormonalIud => 'hormonal_iud',
        BirthControlMethod.copperIud => 'copper_iud',
        BirthControlMethod.condom => 'condom',
        BirthControlMethod.other => 'other',
        BirthControlMethod.unknown =>
          throw StateError('an unrecognised birth-control method cannot be '
              'stored; leave the stored value untouched'),
      };

  /// Total read of `profile_modes.birth_control_method`:
  ///
  /// * null or blank (never answered) parses to null;
  /// * a canonical id parses to its member;
  /// * a legacy id from an earlier draft of this vocabulary
  ///   (`injection`, the pre-#260 English spelling of the shot) parses to
  ///   its canonical member;
  /// * a localized label written by #216's selector before this module
  ///   existed ("Pill", "Hormonal IUD", … — English is the app's only
  ///   locale today) parses to its member;
  /// * anything else degrades to [BirthControlMethod.unknown] rather than
  ///   throwing — a stored answer a future build wrote must survive the
  ///   read intact on the wire and in storage even when this build cannot
  ///   interpret it.
  static BirthControlMethod? fromDb(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final canonical = switch (raw) {
      'none' => none,
      'pill' => pill,
      'shot' => shot,
      'implant' => implant,
      'patch' => patch,
      'ring' => ring,
      'hormonal_iud' => hormonalIud,
      'copper_iud' => copperIud,
      'condom' => condom,
      'other' => other,
      _ => null,
    };
    if (canonical != null) return canonical;
    return _legacyStoredValues[raw] ?? unknown;
  }

  /// Whether this is one of the six tracked methods the issue's model
  /// covers — the methods with a per-day intake category, consumed by
  /// prediction adaptation (#233), reminders (#183), and the clinical
  /// export's medications section (#152).
  bool get isTracked => intakeCategory != null;

  /// The per-day intake `observations.category` for this method, or null
  /// for the non-tracked answers (nothing logs a day row for "condom" in
  /// the issue's model).
  String? get intakeCategory => switch (this) {
        BirthControlMethod.pill => kBirthControlPillCategory,
        BirthControlMethod.shot => kBirthControlShotCategory,
        BirthControlMethod.implant => kBirthControlImplantCategory,
        BirthControlMethod.patch => kBirthControlPatchCategory,
        BirthControlMethod.ring => kBirthControlRingCategory,
        BirthControlMethod.hormonalIud ||
        BirthControlMethod.copperIud =>
          kBirthControlIudCategory,
        _ => null,
      };

  /// The intake category back to a tracked method. Both IUD flavors
  /// collapse to [hormonalIud] (the category deliberately does not carry
  /// the flavor — see [kBirthControlCategories]); non-intake categories
  /// parse to null.
  static BirthControlMethod? forIntakeCategory(String? category) =>
      switch (category) {
        kBirthControlPillCategory => pill,
        kBirthControlShotCategory => shot,
        kBirthControlImplantCategory => implant,
        kBirthControlPatchCategory => patch,
        kBirthControlRingCategory => ring,
        kBirthControlIudCategory => hormonalIud,
        _ => null,
      };
}

/// #216-era values the first-run selector / profile-edit dialog stored
/// before this module owned the vocabulary (English labels — the app's
/// only locale — plus the pre-#260 draft id `injection`), mapped onto the
/// canonical members. Never written by this build again; read-only.
const Map<String, BirthControlMethod> _legacyStoredValues = {
  'Pill': BirthControlMethod.pill,
  'Injection': BirthControlMethod.shot,
  'injection': BirthControlMethod.shot,
  'Hormonal IUD': BirthControlMethod.hormonalIud,
  'Copper IUD': BirthControlMethod.copperIud,
  'Implant': BirthControlMethod.implant,
  'Vaginal ring': BirthControlMethod.ring,
  'Ring': BirthControlMethod.ring,
  'Patch': BirthControlMethod.patch,
  'Condom': BirthControlMethod.condom,
  'None': BirthControlMethod.none,
  'Other': BirthControlMethod.other,
};

/// The birth-control method in effect on [date] — the consumption seam
/// #233 (birth-control-aware predictions), #183 (method reminders), and
/// #152 (clinical-export medications section) read instead of re-parsing
/// the row themselves (issue #260 AC5).
///
/// [storedMethod] is the raw `profile_modes.birth_control_method` value;
/// [startedOn]/[stoppedOn] the raw effective-date columns (`yyyy-MM-dd`
/// or null). Returns:
///
/// * null when no method is recorded, the method is recorded as none
///   ([BirthControlMethod.none] — an affirmative "no method" answer), the
///   recorded string is unparseable ([BirthControlMethod.unknown] — the
///   caller must not act on a method it cannot name), the method is not
///   one of the six tracked ones, [date] falls before [startedOn], or
///   [date] falls on or after [stoppedOn];
/// * the method otherwise (start day inclusive, stop day exclusive).
///
/// Never consults per-day intake rows: a missed pill day does not change
/// the method (A1-29's explicit warning, issue #260's "do not" note).
BirthControlMethod? birthControlMethodInEffectOn({
  required String? storedMethod,
  required String? startedOn,
  required String? stoppedOn,
  required LocalDate date,
}) {
  final method = BirthControlMethod.fromDb(storedMethod);
  if (method == null || !method.isTracked) return null;
  if (startedOn != null &&
      startedOn.isNotEmpty &&
      date.compareTo(LocalDate.fromIso(startedOn)) < 0) {
    return null;
  }
  if (stoppedOn != null &&
      stoppedOn.isNotEmpty &&
      date.compareTo(LocalDate.fromIso(stoppedOn)) >= 0) {
    return null;
  }
  return method;
}
