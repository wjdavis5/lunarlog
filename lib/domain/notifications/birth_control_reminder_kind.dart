/// Pure mapping from a recorded birth-control method to the adherence
/// reminder kind it plans (Issue #183), exposed here so `lib/ui` can name
/// the kind without importing `lib/domain/notifications/scheduling.dart`.
///
/// `lib/domain/notifications/scheduling.dart` imports and re-exports this so
/// its existing callers (and tests) keep resolving the same name.
library;

import '../birth_control.dart';
import 'reminder_config.dart' show ReminderKind;

/// The adherence reminder kind (Issue #183) a recorded method plans, or
/// null for the methods with no user-administered cadence: the implant
/// and both IUD flavors are clinician-administered and must never grow a
/// spurious recurring reminder (the issue's own assumption), and the
/// non-tracked answers (`none`/`condom`/`other`/unknown) have nothing to
/// remind about. Exhaustive: adding a [BirthControlMethod] without a
/// mapping is a compile error.
ReminderKind? birthControlReminderKindFor(BirthControlMethod method) =>
    switch (method) {
      BirthControlMethod.pill => ReminderKind.birthControlPill,
      BirthControlMethod.patch => ReminderKind.birthControlPatch,
      BirthControlMethod.ring => ReminderKind.birthControlRing,
      BirthControlMethod.shot => ReminderKind.birthControlShot,
      BirthControlMethod.none ||
      BirthControlMethod.implant ||
      BirthControlMethod.hormonalIud ||
      BirthControlMethod.copperIud ||
      BirthControlMethod.condom ||
      BirthControlMethod.other ||
      BirthControlMethod.unknown =>
        null,
    };
