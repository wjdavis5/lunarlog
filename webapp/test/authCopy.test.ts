import { describe, expect, it } from 'vitest';

import { AuthError, DeletionError } from '../src/lib/auth';
import { authCopyFor, deletionCopyFor, kMinPasswordLength } from '../src/lib/authCopy';
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

// The rendered form (issue #1295): fills the catalogue's FormatJS-style
// `{name}` placeholders from the values the mapping carries — react-intl
// prints the raw placeholder when a value is missing, which is the bug
// pinned here. Pure, so no DOM.
function renderedCopy(code: string, status = 400): string | undefined {
  const copy = authCopyFor(new AuthError(code, status));
  const message = messages[copy.id];
  if (message === undefined) return undefined;
  return message.replace(/\{(\w+)\}/g, (placeholder, name: string) =>
    copy.values !== undefined && name in copy.values ? String(copy.values[name]) : placeholder,
  );
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
    expect(copyCode('identity_already_exists')).toBe(messages['authFailureIdentityTaken']);
    expect(copyCode('over_request_rate_limit')).toBe(messages['authFailureRateLimited']);
    expect(copyCode('manual_linking_disabled')).toBe(messages['authFailureMisconfigured']);
    expect(copyCode('email_provider_disabled')).toBe(messages['authFailureMisconfigured']);
    expect(copyCode('otp_expired')).toBe(messages['authFailureInvalidCode']);
    expect(copyCode('otp_disabled')).toBe(messages['authFailureInvalidCode']);
    expect(copyCode('flow_state_not_found')).toBe(messages['authFailureExpiredLink']);
    expect(copyCode('bad_code_verifier')).toBe(messages['authFailureExpiredLink']);
  });

  it('renders the weak-password copy with its value, not the placeholder (issue #1295)', () => {
    // The catalogue carries the raw placeholder; the mapping's values must
    // turn it into the real minimum on screen.
    expect(messages['authFailureWeakPassword']).toContain('{minLength}');
    const rendered = renderedCopy('weak_password');
    expect(rendered).toContain(String(kMinPasswordLength));
    expect(rendered).not.toContain('{minLength}');
  });

  it('renders a value-less copy unchanged (issue #1295)', () => {
    expect(renderedCopy('invalid_credentials')).toBe(messages['authFailureWrongPassword']);
  });

  it('maps the web-only codes the Worker emits', () => {
    // The different-browser PKCE case gets the issue's dedicated copy.
    expect(copyCode('verifier_missing')).toBe(messages['webAuthDifferentBrowserError']);
    expect(copyCode('verifier_missing')).toContain('different browser');
    expect(copyCode('verifier_missing')).toContain('8-digit code');
  });

  it('maps the Worker revocation code to the consequence-naming copy (issue #1342)', () => {
    // The revocation_failed 502 (issue #1333) is the "other devices may
    // still be signed in" signal — the copy must say that consequence, and
    // the way through (a bare retry has no session to revoke with).
    expect(copyCode('revocation_failed', 502)).toBe(
      messages['webAuthSignOutEverywhereRevocationFailed'],
    );
    expect(copyCode('revocation_failed', 502)).toContain('other devices');
    expect(copyCode('revocation_failed', 502)).toContain('Sign in and try again');
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

describe('deletionCopyFor (issue #1256)', () => {
  function deletionCopy(code: string, status = 400): string | undefined {
    return messages[deletionCopyFor(new DeletionError(code, status)).id];
  }

  it('lands the nothing-was-touched codes on their nothing-was-deleted copy', () => {
    expect(deletionCopy('apple_code_required')).toBe(
      messages['accountDeletionAppleCodeRequired'],
    );
    expect(deletionCopy('attachment_cleanup_failed')).toBe(
      messages['accountDeletionAttachmentCleanupFailed'],
    );
    expect(deletionCopy('attachment_cleanup_unbounded')).toBe(
      messages['accountDeletionAttachmentCleanupUnbounded'],
    );
    expect(deletionCopy('mfa_required')).toBe(messages['accountDeletionMfaRequired']);
    // The nothing-was-deleted copy really says nothing was deleted.
    expect(deletionCopy('apple_code_required')).toContain('Nothing was deleted');
  });

  it('lands the after-the-RPC codes on their data-already-deleted copy', () => {
    expect(deletionCopy('apple_revoke_failed')).toBe(
      messages['accountDeletionAppleRevokeFailed'],
    );
    expect(deletionCopy('apple_revocation_marker_failed')).toBe(
      messages['accountDeletionRevocationMarkerFailed'],
    );
    expect(deletionCopy('delete_user_failed')).toBe(
      messages['accountDeletionDeleteUserFailed'],
    );
  });

  it('maps the outcome-unknown trio the way the app does', () => {
    expect(deletionCopy('unauthorized')).toBe(messages['accountDeletionSessionExpired']);
    expect(deletionCopy('timeout')).toBe(messages['accountDeletionTimeout']);
    expect(deletionCopy('network')).toBe(messages['accountDeletionNetworkFailure']);
  });

  it('collapses every unrecognised code (identity_check_failed included) onto the unknown copy', () => {
    expect(deletionCopy('identity_check_failed', 500)).toBe(messages['accountDeletionUnknown']);
    expect(deletionCopy('mystery')).toBe(messages['accountDeletionUnknown']);
  });
});
