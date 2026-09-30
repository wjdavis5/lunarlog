import { describe, expect, it } from 'vitest';

import { AuthError } from '../src/lib/auth';
import { authCopyFor, kMinPasswordLength } from '../src/lib/authCopy';
import messages from '../src/i18n/messages.en.json';

/**
 * The auth failure copy table (issue #1250): the Worker's and GoTrue's
 * machine codes land on the same catalogue strings the app uses, plus the
 * web-only different-browser code the issue names. Every mapped id must
 * exist in the catalogue — the MessageId type enforces it at compile time,
 * this pins the rendered strings.
 */
function copyCode(code: string, status = 400): string | undefined {
  return messages[authCopyFor(new AuthError(code, status)).id];
}

describe('authCopyFor (issue #1250)', () => {
  it('maps the GoTrue codes the app maps, to the same copy', () => {
    expect(copyCode('invalid_credentials')).toBe(messages['authFailureWrongPassword']);
    // The weak-password copy takes the length placeholder; the mapping
    // carries the project's 12.
    const weak = authCopyFor(new AuthError('weak_password', 400));
    expect(weak.id).toBe('authFailureWeakPassword');
    expect(weak.values?.minLength).toBe(kMinPasswordLength);
    expect(copyCode('signup_disabled')).toBe(messages['authFailureSignUpClosed']);
    expect(copyCode('identity_already_exists')).toBe(
      messages['authFailureIdentityTaken'],
    );
    expect(copyCode('over_request_rate_limit')).toBe(
      messages['authFailureRateLimited'],
    );
    expect(copyCode('manual_linking_disabled')).toBe(
      messages['authFailureMisconfigured'],
    );
    expect(copyCode('email_provider_disabled')).toBe(
      messages['authFailureMisconfigured'],
    );
    expect(copyCode('otp_expired')).toBe(messages['authFailureInvalidCode']);
    expect(copyCode('otp_disabled')).toBe(messages['authFailureInvalidCode']);
    expect(copyCode('flow_state_not_found')).toBe(messages['authFailureExpiredLink']);
    expect(copyCode('bad_code_verifier')).toBe(messages['authFailureExpiredLink']);
  });

  it('maps the web-only codes the Worker emits', () => {
    // The different-browser PKCE case gets the issue's dedicated copy.
    expect(copyCode('verifier_missing')).toBe(messages['webAuthDifferentBrowserError']);
    expect(copyCode('verifier_missing')).toContain('different browser');
    expect(copyCode('verifier_missing')).toContain('8-digit code');
  });

  it('buckets a code-less 429 as rate limited and everything else as generic', () => {
    expect(copyCode('unknown', 429)).toBe(messages['authFailureRateLimited']);
    expect(copyCode('mystery')).toBe(messages['commonSomethingWentWrong']);
  });

  it('the different-browser copy exists in the catalogue', () => {
    expect(messages['webAuthDifferentBrowserError']).toBeDefined();
    expect(messages['webAuthAppleButtonLabel']).toBe('Sign in with Apple');
    expect(messages['webAuthSignOutEverywhereAction']).toBe('Sign out everywhere');
  });
});
