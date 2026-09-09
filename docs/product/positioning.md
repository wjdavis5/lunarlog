# Product positioning — sync and family collaboration

Captures the repositioning done in issue #122. This is a framing document,
not a new source of technical fact — every claim here is backed by
`README.md`, `PRIVACY.md`, `AGENTS.md`, or an issue, cited inline.

## Audience

Families with one or more adult guardians tracking menstrual cycles for
themselves and/or minors in their care, where more than one adult
(co-parents, other caregivers) needs visibility into or a hand in logging
that data — not a single-user, single-device tracker. (`README.md`
"Family sharing"; roles `primary_guardian`/`co_parent`/`caregiver`/`viewer`.)

## The family-collaboration story

Sync and multi-guardian collaboration are the product's priority and its
differentiator, not an add-on layered on top of a single-user app:

- **An account is the product's core loop.** Signing in (Supabase Auth) is
  how a device joins the household and how a profile is shared with other
  guardians — not an optional upgrade path. (`README.md` "Accounts";
  `AGENTS.md` Project Overview.)
- **Roles, invitations, and attribution are deep, not bolted on.** A profile
  can be shared via a single-use invite link with roles
  `primary_guardian`/`co_parent`/`caregiver`/`viewer`; concurrent edits from
  two guardians merge tags rather than silently overwriting one caregiver's
  work. (`README.md` "Family sharing".)
- **Ownership can move with the family.** A parent who created a minor's
  profile can transfer ownership of it to the minor's own account, keeping
  every past entry's original attribution intact. (`README.md` "Accounts";
  `PRIVACY.md` Section 5, Issue #4.)
- **Caregivers can be notified, not just invited.** Optional push alerts
  tell a caregiver when another guardian logs an entry, or when an expected
  entry hasn't arrived — only on a build compiled with every `FCM_*`
  `--dart-define`; a build with no push configuration never contacts FCM
  at all. (`PRIVACY.md` Section 4, Firebase Cloud Messaging row.)
- **Offline is a reliability property of that same account-centric product,
  not a competing identity.** Logging, viewing history, and predictions all
  keep working without a network; that resilience does not require avoiding
  an account — sharing a profile with another guardian does require signing
  in. (`README.md` opening paragraph; `PRIVACY.md` Section 1, "Resilient
  Offline".)
- **Export is account-independent, by design, for continuity — not
  evidence against sync being the default.** "Export my data" works fully
  offline and without an account; this is data portability, not a second
  product identity. Reading an exported file back in is being built
  (issue #140, PR #325 open); it is not in the shipped app yet.
  (`README.md` "Accounts"; `PRIVACY.md` Section 7, "Data Export &
  Retention & Deletion Rights".)

## What lunarlog deliberately does not do

- **No fertility or ovulation inference in the base product today.** The app
  tracks cycles and flow and estimates the next period; fertile-window and
  ovulation estimation is planned scope but does not exist in the app as of
  this writing (issue #143, open). The earlier policy guarantee that no
  fertility feature would ever exist was removed by owner decision (issue
  #142, closed) — this is a scope change under active tracking, not a
  currently-shipped claim. (`PRIVACY.md` Section 1, "Estimates From Your Own
  Logged Data"; `README.md` opening paragraph.)
- **No advertising, data brokers, or behavioral tracking**, regardless of
  sync being the default framing. (`PRIVACY.md` Section 1, "No Advertising
  or Data Brokers"; Section 3.)
- **No forced account.** A build with no cloud `--dart-define`s has no
  account section, no sync, and no crash reporting at all — this is
  positioned as a development configuration for iterating without cloud
  credentials, not a supported product mode, but it remains literally true
  that an account is not compiled-in-mandatory. (`README.md` "Build / run";
  `AGENTS.md` Project Overview.)
- **No third-party data sale or unscoped sharing.** Only Supabase, Sentry,
  Resend, Apple/Google (sign-in), and FCM (optional caregiver push) ever
  receive data, each for a named app-functionality purpose. (`PRIVACY.md`
  Section 4.)
- **No Clue import yet.** A Clue/Apple Health/Health Connect import is being
  built (issues #190, #167, #172) with a provenance label already disclosed
  in the schema (`PRIVACY.md` Section 2.A, September 9, 2026 change-history
  entry) — it does not exist in the shipped app yet.
- **No open-ended health-platform sync.** Profile-to-device-owner binding
  and a guardian-write guard for health-platform sync landed (issue #153,
  closed) as groundwork; this document does not claim a general Apple
  Health / Health Connect sync feature is live for end users.

## Non-goals of this document

This file is a positioning summary, not a new privacy commitment or a
replacement for `PRIVACY.md`. Where anything here and `PRIVACY.md` disagree,
`PRIVACY.md` is the authority — file a correction to this document, not the
other way around.
