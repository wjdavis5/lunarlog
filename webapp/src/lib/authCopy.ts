// Auth failure copy for the web client (issue #1250): maps the /auth/*
// Worker's machine error codes onto catalogue message ids — the same
// strings the app maps its AuthFailure kinds onto (lib/ui/l10n/
// auth_failure_copy.dart and lib/data/auth/supabase_auth_providers.dart's
// GoTrue-code table), plus the two web-only codes the Worker itself emits.
// Pure, so the tests exercise the table without a DOM.

import type { AuthError } from './auth';
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
