// Auth failure copy for the web client (issue #1250): maps the /auth/*
// Worker's machine error codes onto catalogue message ids — the same
// strings the app maps its AuthFailure kinds onto (lib/ui/l10n/
// auth_failure_copy.dart and lib/data/auth/supabase_auth_providers.dart's
// GoTrue-code table), plus the two web-only codes the Worker itself emits.
// Pure, so the tests exercise the table without a DOM.
//
// Issue #1256 adds the account-deletion table, mirroring
// `accountDeletionFailureCopy` in lib/ui/account/account_section.dart: the
// delete-account Edge Function's stable codes grouped by what the copy must
// say — nothing was touched, the server data is already gone, or other.

import type { AuthError, DeletionError } from './auth';
import type { MessageId } from '../i18n/message-ids';

/** The project's client-side minimum, matching the app's kMinPasswordLength. */
export const kMinPasswordLength = 12;

/**
 * The catalogue id (and its FormatJS values, when the message takes any)
 * a failed auth call should render.
 */
export interface AuthCopy {
  id: MessageId;
  values?: Record<string, string | number>;
}

/** Maps the Worker's GoTrue/worker codes to catalogue ids. */
export function authCopyFor(error: AuthError): AuthCopy {
  switch (error.code) {
    case 'invalid_credentials':
      return { id: 'authFailureWrongPassword' };
    case 'weak_password':
      return {
        id: 'authFailureWeakPassword',
        values: { minLength: kMinPasswordLength },
      };
    case 'signup_disabled':
      return { id: 'authFailureSignUpClosed' };
    case 'identity_already_exists':
      return { id: 'authFailureIdentityTaken' };
    // Throttled, not rejected (issue #32 AC2): the copy names waiting.
    case 'over_request_rate_limit':
      return { id: 'authFailureRateLimited' };
    // The dashboard is not set up for this operation (issue #32 AC4).
    case 'manual_linking_disabled':
    case 'email_provider_disabled':
      return { id: 'authFailureMisconfigured' };
    // The PKCE link opened in a different browser (or the short-lived
    // verifier cookie expired there): the issue's dedicated copy — open the
    // link where you asked for it, or use the 8-digit code.
    case 'verifier_missing':
      return { id: 'webAuthDifferentBrowserError' };
    // The Worker's global sign-out whose GoTrue revocation never landed
    // (issue #1333's revocation_failed 502, surfaced by issue #1342): this
    // device is out — the cookie cleared either way — but the other
    // devices' sessions were not revoked, and the copy is the only place
    // that consequence still gets said.
    case 'revocation_failed':
      return { id: 'webAuthSignOutEverywhereRevocationFailed' };
    default:
      return rareAuthCopyFor(error);
  }
}

/** The less-common kinds, split out to keep the switch table readable. */
function rareAuthCopyFor(error: AuthError): AuthCopy {
  switch (error.code) {
    // A wrong or expired emailed code.
    case 'otp_expired':
    case 'otp_disabled':
      return { id: 'authFailureInvalidCode' };
    // An expired, reused, or spent link (also the different-browser-adjacent
    // GoTrue shapes: flow state gone, verifier mismatch upstream).
    case 'flow_state_not_found':
    case 'flow_state_expired':
    case 'bad_code_verifier':
    case 'already_used':
      return { id: 'authFailureExpiredLink' };
    // A code-less 429 is throttled too (issue #32 AC2).
    default:
      return error.status === 429
        ? { id: 'authFailureRateLimited' }
        : { id: 'commonSomethingWentWrong' };
  }
}

/**
 * The delete-account Edge Function's codes, mapped the way the app maps its
 * deletion failure kinds (lib/ui/account/account_section.dart's
 * `accountDeletionFailureCopy`): the "nothing was touched" kinds, the
 * "your server data is already gone" kinds, and everything else. The
 * `apple_ceremony_unavailable` Android kind has no web arm — on the web the
 * ceremony is always reachable, so its failure surfaces as a plain
 * `network` code here instead.
 */
export function deletionCopyFor(error: DeletionError): AuthCopy {
  switch (error.code) {
    // Fail-closed before anything was touched: a bare retry (with a fresh
    // Apple code where asked) is always safe.
    case 'apple_code_required':
      return { id: 'accountDeletionAppleCodeRequired' };
    case 'attachment_cleanup_failed':
      return { id: 'accountDeletionAttachmentCleanupFailed' };
    case 'attachment_cleanup_unbounded':
      return { id: 'accountDeletionAttachmentCleanupUnbounded' };
    case 'mfa_required':
      return { id: 'accountDeletionMfaRequired' };
    // The row deletion already ran; only the named last step failed.
    case 'apple_revoke_failed':
      return { id: 'accountDeletionAppleRevokeFailed' };
    case 'apple_revocation_marker_failed':
      return { id: 'accountDeletionRevocationMarkerFailed' };
    case 'delete_user_failed':
      return { id: 'accountDeletionDeleteUserFailed' };
    // An expired session, a call whose outcome is unknown, or an
    // unclassified failure.
    case 'unauthorized':
      return { id: 'accountDeletionSessionExpired' };
    case 'timeout':
      return { id: 'accountDeletionTimeout' };
    case 'network':
      return { id: 'accountDeletionNetworkFailure' };
    default:
      return { id: 'accountDeletionUnknown' };
  }
}
