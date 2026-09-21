/// Which minimum-age acknowledgement copy an operator sees (Issue #957).
///
/// The pre-#957 acknowledgement was one flat statement — "I am 13 or older,
/// or a guardian managing a family profile" — which an under-13 operator
/// arriving through a parent's "her own profile" invitation cannot truthfully
/// affirm. The owner's 2026-09-20 decision keeps the 13+ statement for a cold
/// sign-up and gives the invited path its own wording: the parent's invitation
/// is the parental-consent record, so the operator acknowledges the invitation
/// rather than an age she does not have. No age is verified or collected
/// either way (issues #269/#802).
library;

import 'package:lunarlog/l10n/app_localizations.dart';

/// The context an acknowledgement is shown in. This is the injection seam
/// [#minimumAgeAcknowledgementCopy] branches on, so a widget test can render
/// either wording without a live sign-up or invite.
enum MinimumAgeAcknowledgementContext {
  /// A cold arrival: the 13-or-older statement (Issue #269).
  self13Plus,

  /// An arrival through a parent's or guardian's invitation: the
  /// parent-invite wording (Issue #957).
  parentInvite,
}

/// The [label] (the affirmation) and [hint] (the one-line explanation) for
/// one [MinimumAgeAcknowledgementContext].
class MinimumAgeAcknowledgementCopy {
  const MinimumAgeAcknowledgementCopy({
    required this.label,
    required this.hint,
  });

  final String label;
  final String hint;
}

/// Resolves the acknowledgement copy for [context].
MinimumAgeAcknowledgementCopy minimumAgeAcknowledgementCopy(
  AppLocalizations l10n,
  MinimumAgeAcknowledgementContext context,
) =>
    switch (context) {
      MinimumAgeAcknowledgementContext.self13Plus =>
        MinimumAgeAcknowledgementCopy(
          label: l10n.firstRunAgeAcknowledgementLabel,
          hint: l10n.firstRunAgeAcknowledgementHint,
        ),
      MinimumAgeAcknowledgementContext.parentInvite =>
        MinimumAgeAcknowledgementCopy(
          label: l10n.firstRunAgeAcknowledgementParentInviteLabel,
          hint: l10n.firstRunAgeAcknowledgementParentInviteHint,
        ),
    };
