# COPPA and the parent-invitation consent record

Records the reasoning behind issue #957's policy: **13+ may create an
account and use LunarLog directly; an individual under 13 may use the app on
her own device only through an account and profile a parent or legal guardian
created and invited her into.** The parent's "her own profile" invitation
(issue #802's subject membership) is the parental-consent record. This note
explains why that is treated as consent, exactly what is recorded, and what
would strengthen it later. It is a product/engineering record, not legal
advice — a formal compliance review remains the owner's call.

## Why the parent invitation is treated as consent

- **The child cannot arrive cold.** A cold account creation still requires the
  flat 13-or-older acknowledgement. The under-13 path is reachable only when a
  parent or guardian, signed into their own account, creates the profile and
  sends the invitation. There is no self-service under-13 sign-up.
- **The consenting adult is authenticated.** The inviting account is a
  Supabase account whose email was confirmed at sign-up; the invitation is
  created from that authenticated session and is visible as a membership on a
  profile that account owns. The app treats that affirmative act — creating a
  profile for the child and inviting her to hold it herself — as the
  parent's authorization for her to use the app.
- **The consent is durable and inspectable, not inferred from a checkbox.**
  The accepted membership carries `is_subject`, the profile's owning account
  is the custodian until a deliberate ownership transfer, and the
  acknowledgement row records `consent_via = 'parent_invite'`. A parent's
  later deletion of the profile, or an ownership transfer, is a separate,
  recorded act.
- **No age is collected or verified by this path.** Birth year is never a
  gate (issues #269/#802); the policy distinguishes *how the operator
  arrived* (invited vs. cold), not a measured age.

## What is recorded

- `public.account_consents` (issue #845): one synced, owner-only row per
  account with `consent_via` (`self_13_plus` or `parent_invite`),
  `acknowledged_at`, `app_version`, and `policy_version`, written through
  `record_minimum_age_acknowledgement`. Accepting a subject invitation writes
  `parent_invite`; the first-run cold acknowledgement writes `self_13_plus`.
- `public.profile_guardians.is_subject` (issue #802): the durable membership
  fact that the accepting account is the profile's subject, stamped only by
  `accept_guardian_invitation`.
- The local `SettingsKeys.minimumAgeAcknowledged` flag remains the offline
  cache on the device.

## What this is not

- Not a technical age-verification gate, and not a second sign-up approval:
  the under-13 operator still accepts the invitation herself. The consent
  record is the parent's invitation, not a checked age.
- Not a substitute for the store declarations or a legal sign-off.

## What would strengthen it later

- **A parent-facing consent step at invitation time.** Today the parent's
  affirmative act is implicit in creating the profile and tapping invite;
  a dedicated notice-and-consent screen (stating what is collected, the
  retention/deletion path, and how to revoke) would make the consent
  explicit and auditable.
- **Recording the consenting parent.** The membership already names the
  inviting account; surfacing the inviting guardian's identity and the
  invitation timestamp alongside the `parent_invite` row would tie the
  record to a person.
- **Email-plus confirmation to the parent.** A confirmation link or code
  sent to the inviting account's confirmed email — the FTC's "email plus"
  method — is the most direct way to move this from a credible internal
  posture to a recognized verifiable-parental-consent mechanism.
- **A revocation path surfaced in the app.** The parent can already remove
  the membership; stating that removal withdraws consent, in-app, would
  close the loop.

## Store declarations

The Apple age-rating / Play Families and Data safety implications of
under-13 use are **not** duplicated here. They are tracked in issue #21's
checklist (see `docs/ops/supabase-go-live.md`, "Issue #269 (minimum-age
statement)"), which this note deliberately folds into by reference rather
than restating.
