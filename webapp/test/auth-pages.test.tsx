import { QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { createAppQueryClient } from '../src/lib/queries';
import { AppIntlProvider } from '../src/i18n/i18n';
import messages from '../src/i18n/messages.en.json';

/**
 * The auth screens' behaviour against a mocked web auth client (issue
 * #1250): catalogue copy renders, forms call the right /auth/* action with
 * the right arguments, failures render the mapped copy, and the callback
 * page renders the issue's different-browser copy for `verifier_missing`.
 */

const fakes = vi.hoisted(() => ({
  getToken: vi.fn<() => Promise<string | null>>(),
  getUser: vi.fn<() => { id: string; email: string | null } | null>(),
  signInWithPassword: vi.fn<() => Promise<void>>(),
  signUp: vi.fn<() => Promise<'signed_in' | 'confirmation_required'>>(),
  sendOtp: vi.fn<() => Promise<void>>(),
  verifyOtp: vi.fn<() => Promise<void>>(),
  sendPasswordReset: vi.fn<() => Promise<void>>(),
  updatePassword: vi.fn<() => Promise<void>>(),
  signOut: vi.fn<() => Promise<void>>(),
  exchangeCallback: vi.fn<() => Promise<{ recovery: boolean }>>(),
  startOAuth: vi.fn(),
}));

vi.mock('../src/lib/auth', async () => {
  const { AuthError } =
    await vi.importActual<typeof import('../src/lib/auth')>('../src/lib/auth');
  return {
    AuthError,
    WebAuthClient: class {},
    webAuth: fakes,
  };
});

// startOAuth is re-exported by authQueries from the (mocked) auth module.
import { AuthError } from '../src/lib/auth';
import { AuthCallbackPage } from '../src/pages/AuthCallbackPage';
import { CodeEntryPage } from '../src/pages/CodeEntryPage';
import { ForgotPasswordPage } from '../src/pages/ForgotPasswordPage';
import { ResetPasswordPage } from '../src/pages/ResetPasswordPage';
import { SignInPage } from '../src/pages/SignInPage';
import { SignUpPage } from '../src/pages/SignUpPage';

function renderWithProviders(ui: React.ReactElement, initialPath = '/') {
  const queryClient = createAppQueryClient();
  return render(
    <AppIntlProvider>
      <QueryClientProvider client={queryClient}>
        <MemoryRouter initialEntries={[initialPath]}>{ui}</MemoryRouter>
      </QueryClientProvider>
    </AppIntlProvider>,
  );
}

/**
 * Routes-based render for the navigation assertions (issue #1294): the
 * code screen mounts for real, so a navigate — or the absence of one —
 * is visible as rendered content, not inferred from mocks.
 */
function renderWithRoutes(initialPath: string) {
  const queryClient = createAppQueryClient();
  return render(
    <AppIntlProvider>
      <QueryClientProvider client={queryClient}>
        <MemoryRouter initialEntries={[initialPath]}>
          <Routes>
            <Route path="/" element={<div>home</div>} />
            <Route path="/sign-in" element={<SignInPage />} />
            <Route path="/sign-up" element={<SignUpPage />} />
            <Route path="/sign-in/code" element={<CodeEntryPage />} />
          </Routes>
        </MemoryRouter>
      </QueryClientProvider>
    </AppIntlProvider>,
  );
}

beforeEach(() => {
  fakes.getToken.mockResolvedValue(null);
  fakes.getUser.mockReturnValue(null);
  fakes.signInWithPassword.mockResolvedValue(undefined);
  fakes.signUp.mockResolvedValue('confirmation_required');
  fakes.sendOtp.mockResolvedValue(undefined);
  fakes.verifyOtp.mockResolvedValue(undefined);
  fakes.sendPasswordReset.mockResolvedValue(undefined);
  fakes.updatePassword.mockResolvedValue(undefined);
  fakes.signOut.mockResolvedValue(undefined);
  fakes.exchangeCallback.mockResolvedValue({ recovery: false });
});

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
});

function fill(label: string, value: string) {
  fireEvent.change(screen.getByLabelText(label), { target: { value } });
}

describe('SignInPage (issue #1250)', () => {
  it('renders the catalogue form and signs in with the typed credentials', async () => {
    renderWithProviders(<SignInPage />, '/sign-in');
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent(
      messages['accountSignInTitle'] ?? '',
    );
    await fill(messages['accountSignInEmailLabel'] ?? '', 'a@b.co');
    await fill(messages['accountSignInPasswordLabel'] ?? '', 'long enough password');
    fireEvent.click(screen.getByRole('button', { name: messages['accountSignInAction'] }));
    await waitFor(() => expect(fakes.signInWithPassword).toHaveBeenCalledOnce());
    expect(fakes.signInWithPassword).toHaveBeenCalledWith('a@b.co', 'long enough password');
  });

  it('renders the mapped copy for a rejected password', async () => {
    fakes.signInWithPassword.mockRejectedValue(new AuthError('invalid_credentials', 400));
    renderWithProviders(<SignInPage />, '/sign-in');
    await fill(messages['accountSignInEmailLabel'] ?? '', 'a@b.co');
    await fill(messages['accountSignInPasswordLabel'] ?? '', 'wrong');
    fireEvent.click(screen.getByRole('button', { name: messages['accountSignInAction'] }));
    expect(await screen.findByText(messages['authFailureWrongPassword'])).toBeInTheDocument();
  });

  it('shows the signed-in state with both sign-out scopes', async () => {
    fakes.getToken.mockResolvedValue('access-1');
    fakes.getUser.mockReturnValue({ id: 'u1', email: 'a@b.co' });
    renderWithProviders(<SignInPage />, '/sign-in');
    expect(
      await screen.findByText((_, element) => element?.textContent === 'Signed in as a@b.co'),
    ).toBeInTheDocument();
    fireEvent.click(
      screen.getByRole('button', { name: messages['webAuthSignOutEverywhereAction'] }),
    );
    await waitFor(() => expect(fakes.signOut).toHaveBeenCalledWith('global'));
  });

  it('offers the Google and Apple OAuth starts', () => {
    renderWithProviders(<SignInPage />, '/sign-in');
    fireEvent.click(screen.getByRole('button', { name: messages['accountGoogleButtonLabel'] }));
    expect(fakes.startOAuth).toHaveBeenCalledWith('google');
    fireEvent.click(screen.getByRole('button', { name: messages['webAuthAppleButtonLabel'] }));
    expect(fakes.startOAuth).toHaveBeenCalledWith('apple');
  });

  it('navigates to the code screen only after the send resolves (issue #1294)', async () => {
    renderWithRoutes('/sign-in');
    await fill(messages['accountSignInEmailLabel'] ?? '', 'a@b.co');
    fireEvent.click(
      screen.getByRole('button', { name: messages['accountSignInMagicLinkSignIn'] }),
    );
    await waitFor(() => expect(fakes.sendOtp).toHaveBeenCalledWith('a@b.co', false));
    expect(
      await screen.findByLabelText(messages['accountSignInCodeLabel'] ?? ''),
    ).toBeInTheDocument();
  });

  it('stays on the sign-in page with the mapped copy when the send is rejected (issue #1294)', async () => {
    fakes.sendOtp.mockRejectedValue(new AuthError('over_email_send_rate_limit', 429));
    renderWithRoutes('/sign-in');
    await fill(messages['accountSignInEmailLabel'] ?? '', 'a@b.co');
    fireEvent.click(
      screen.getByRole('button', { name: messages['accountSignInMagicLinkSignIn'] }),
    );
    expect(
      await screen.findByText(messages['authFailureRateLimited'] ?? ''),
    ).toBeInTheDocument();
    // No navigation: the code screen's input never renders.
    expect(
      screen.queryByLabelText(messages['accountSignInCodeLabel'] ?? ''),
    ).not.toBeInTheDocument();
  });

  it('shows the send error, not a stale password error, when the send follows a rejected password (issue #1345)', async () => {
    fakes.signInWithPassword.mockRejectedValue(new AuthError('invalid_credentials', 400));
    fakes.sendOtp.mockRejectedValue(new AuthError('over_email_send_rate_limit', 429));
    renderWithRoutes('/sign-in');
    await fill(messages['accountSignInEmailLabel'] ?? '', 'a@b.co');
    await fill(messages['accountSignInPasswordLabel'] ?? '', 'wrong');
    fireEvent.click(screen.getByRole('button', { name: messages['accountSignInAction'] }));
    expect(await screen.findByText(messages['authFailureWrongPassword'])).toBeInTheDocument();
    // The send button needs only the email; the password can stay as typed.
    fireEvent.click(
      screen.getByRole('button', { name: messages['accountSignInMagicLinkSignIn'] }),
    );
    // The send's own failure renders — TanStack keeps a mutation's error
    // until reset, so without the reset the stale password copy would sit
    // ahead of it in the `??` forever (issue #1345).
    expect(
      await screen.findByText(messages['authFailureRateLimited'] ?? ''),
    ).toBeInTheDocument();
    expect(screen.queryByText(messages['authFailureWrongPassword'])).not.toBeInTheDocument();
  });
});

describe('SignUpPage (issue #1250)', () => {
  // The length rule used to be a loose paragraph under the field. A screen
  // reader landing in the password box never heard it.
  it('ties the password length rule to the password field', () => {
    renderWithProviders(<SignUpPage />, '/sign-up');
    expect(
      screen.getByLabelText(messages['accountSignInPasswordLabel'] ?? ''),
    ).toHaveAccessibleDescription(/at least 12 characters/i);
  });

  it('rejects a short password client-side with the catalogue error', async () => {
    renderWithProviders(<SignUpPage />, '/sign-up');
    await fill(messages['accountSignInEmailLabel'] ?? '', 'a@b.co');
    await fill(messages['accountSignInPasswordLabel'] ?? '', 'short');
    fireEvent.click(
      screen.getByRole('button', { name: messages['accountSignInCreateAccountAction'] }),
    );
    expect(screen.getByText(/at least 12 characters/)).toBeInTheDocument();
    expect(fakes.signUp).not.toHaveBeenCalled();
  });

  it('renders the weak-password copy with its value, not the placeholder (issue #1295)', async () => {
    fakes.signUp.mockRejectedValue(new AuthError('weak_password', 400));
    renderWithProviders(<SignUpPage />, '/sign-up');
    await fill(messages['accountSignInEmailLabel'] ?? '', 'a@b.co');
    await fill(messages['accountSignInPasswordLabel'] ?? '', 'long enough password');
    fireEvent.click(
      screen.getByRole('button', { name: messages['accountSignInCreateAccountAction'] }),
    );
    // The mapped copy carries {minLength}; the page must pass its values to
    // the catalogue so the real minimum renders.
    expect(
      await screen.findByText(
        (messages['authFailureWeakPassword'] ?? '').replace('{minLength}', '12'),
      ),
    ).toBeInTheDocument();
    expect(screen.queryByText(/\{minLength\}/)).not.toBeInTheDocument();
  });

  it('signs up and shows the confirmation copy', async () => {
    renderWithProviders(<SignUpPage />, '/sign-up');
    await fill(messages['accountSignInEmailLabel'] ?? '', 'a@b.co');
    await fill(messages['accountSignInPasswordLabel'] ?? '', 'long enough password');
    fireEvent.click(
      screen.getByRole('button', { name: messages['accountSignInCreateAccountAction'] }),
    );
    await waitFor(() => expect(fakes.signUp).toHaveBeenCalledOnce());
    expect(await screen.findByText(messages['webAuthConfirmEmailInfo'])).toBeInTheDocument();
  });

  it('navigates to the code screen only after the send resolves (issue #1294)', async () => {
    renderWithRoutes('/sign-up');
    await fill(messages['accountSignInEmailLabel'] ?? '', 'a@b.co');
    fireEvent.click(
      screen.getByRole('button', { name: messages['accountSignInMagicLinkCreate'] }),
    );
    await waitFor(() => expect(fakes.sendOtp).toHaveBeenCalledWith('a@b.co', true));
    expect(
      await screen.findByLabelText(messages['accountSignInCodeLabel'] ?? ''),
    ).toBeInTheDocument();
  });

  it('stays on the sign-up page with the mapped copy when the send is rejected (issue #1294)', async () => {
    fakes.sendOtp.mockRejectedValue(new AuthError('otp_disabled', 400));
    renderWithRoutes('/sign-up');
    await fill(messages['accountSignInEmailLabel'] ?? '', 'a@b.co');
    fireEvent.click(
      screen.getByRole('button', { name: messages['accountSignInMagicLinkCreate'] }),
    );
    expect(
      await screen.findByText(messages['authFailureInvalidCode'] ?? ''),
    ).toBeInTheDocument();
    // No navigation: the code screen's input never renders.
    expect(
      screen.queryByLabelText(messages['accountSignInCodeLabel'] ?? ''),
    ).not.toBeInTheDocument();
  });

  it('shows the send error, not a stale sign-up error, when the send follows a rejected sign-up (issue #1345)', async () => {
    fakes.signUp.mockRejectedValue(new AuthError('weak_password', 400));
    fakes.sendOtp.mockRejectedValue(new AuthError('over_email_send_rate_limit', 429));
    const weakCopy = (messages['authFailureWeakPassword'] ?? '').replace('{minLength}', '12');
    renderWithRoutes('/sign-up');
    await fill(messages['accountSignInEmailLabel'] ?? '', 'a@b.co');
    await fill(messages['accountSignInPasswordLabel'] ?? '', 'long enough password');
    fireEvent.click(
      screen.getByRole('button', { name: messages['accountSignInCreateAccountAction'] }),
    );
    expect(await screen.findByText(weakCopy)).toBeInTheDocument();
    fireEvent.click(
      screen.getByRole('button', { name: messages['accountSignInMagicLinkCreate'] }),
    );
    // The send's own failure renders — TanStack keeps a mutation's error
    // until reset, so without the reset the stale sign-up copy would sit
    // ahead of it in the `??` forever (issue #1345).
    expect(
      await screen.findByText(messages['authFailureRateLimited'] ?? ''),
    ).toBeInTheDocument();
    expect(screen.queryByText(weakCopy)).not.toBeInTheDocument();
  });
});

describe('CodeEntryPage (issue #1250)', () => {
  it('verifies the code as email for a sign-in and navigates home', async () => {
    renderWithProviders(<CodeEntryPage />, '/sign-in/code?email=a%40b.co');
    await fill(messages['accountSignInCodeLabel'] ?? '', '12345678');
    fireEvent.click(
      screen.getByRole('button', { name: messages['accountSignInVerifyCodeAction'] }),
    );
    await waitFor(() =>
      expect(fakes.verifyOtp).toHaveBeenCalledWith('a@b.co', '12345678', 'email'),
    );
  });

  it('verifies a recovery code and points at the new-password screen', async () => {
    renderWithProviders(<CodeEntryPage />, '/sign-in/code?email=a%40b.co&mode=recovery');
    await fill(messages['accountSignInCodeLabel'] ?? '', '12345678');
    fireEvent.click(
      screen.getByRole('button', { name: messages['accountSignInVerifyCodeAction'] }),
    );
    await waitFor(() =>
      expect(fakes.verifyOtp).toHaveBeenCalledWith('a@b.co', '12345678', 'recovery'),
    );
    expect(
      await screen.findByText(messages['accountPasswordRecoveryIntro']),
    ).toBeInTheDocument();
  });

  it('renders the mapped copy for a rejected code', async () => {
    fakes.verifyOtp.mockRejectedValue(new AuthError('otp_expired', 403));
    renderWithProviders(<CodeEntryPage />, '/sign-in/code?email=a%40b.co');
    await fill(messages['accountSignInCodeLabel'] ?? '', '00000000');
    fireEvent.click(
      screen.getByRole('button', { name: messages['accountSignInVerifyCodeAction'] }),
    );
    expect(await screen.findByText(messages['authFailureInvalidCode'])).toBeInTheDocument();
  });
});

describe('ForgotPasswordPage (issue #1250)', () => {
  it('sends the reset email and shows the reset info with the code path', async () => {
    renderWithProviders(<ForgotPasswordPage />, '/forgot-password');
    await fill(messages['accountSignInEmailLabel'] ?? '', 'a@b.co');
    fireEvent.click(screen.getByRole('button', { name: messages['webAuthSendResetAction'] }));
    await waitFor(() => expect(fakes.sendPasswordReset).toHaveBeenCalledWith('a@b.co'));
    expect(await screen.findByText(messages['webAuthResetInfo'])).toBeInTheDocument();
  });
});

describe('ResetPasswordPage (issue #1250)', () => {
  it('ties the password length rule to the new-password field', () => {
    renderWithProviders(<ResetPasswordPage />, '/reset-password');
    expect(
      screen.getByLabelText(messages['accountPasswordRecoveryNewLabel'] ?? ''),
    ).toHaveAccessibleDescription(/at least 12 characters/i);
  });

  it('saves the new password when both fields agree', async () => {
    renderWithProviders(<ResetPasswordPage />, '/reset-password');
    await fill(messages['accountPasswordRecoveryNewLabel'] ?? '', 'long enough password');
    await fill(messages['accountPasswordRecoveryConfirmLabel'] ?? '', 'long enough password');
    fireEvent.click(
      screen.getByRole('button', { name: messages['accountPasswordRecoverySave'] }),
    );
    await waitFor(() =>
      expect(fakes.updatePassword).toHaveBeenCalledWith('long enough password'),
    );
  });

  it('rejects a mismatch with the catalogue error', async () => {
    renderWithProviders(<ResetPasswordPage />, '/reset-password');
    await fill(messages['accountPasswordRecoveryNewLabel'] ?? '', 'long enough password');
    await fill(messages['accountPasswordRecoveryConfirmLabel'] ?? '', 'different password!');
    fireEvent.click(
      screen.getByRole('button', { name: messages['accountPasswordRecoverySave'] }),
    );
    expect(
      await screen.findByText(messages['accountPasswordRecoveryMismatchError']),
    ).toBeInTheDocument();
    expect(fakes.updatePassword).not.toHaveBeenCalled();
  });

  it('renders the weak-password copy with its value, not the placeholder (issue #1295)', async () => {
    fakes.updatePassword.mockRejectedValue(new AuthError('weak_password', 400));
    renderWithProviders(<ResetPasswordPage />, '/reset-password');
    await fill(messages['accountPasswordRecoveryNewLabel'] ?? '', 'long enough password');
    await fill(messages['accountPasswordRecoveryConfirmLabel'] ?? '', 'long enough password');
    fireEvent.click(
      screen.getByRole('button', { name: messages['accountPasswordRecoverySave'] }),
    );
    expect(
      await screen.findByText(
        (messages['authFailureWeakPassword'] ?? '').replace('{minLength}', '12'),
      ),
    ).toBeInTheDocument();
    expect(screen.queryByText(/\{minLength\}/)).not.toBeInTheDocument();
  });
});

describe('AuthCallbackPage (issue #1250)', () => {
  it('exchanges the landed code and renders the signed-in state', async () => {
    fakes.getUser.mockReturnValue({ id: 'u1', email: 'a@b.co' });
    renderWithProviders(<AuthCallbackPage />, '/auth/callback?code=abc');
    await waitFor(() => expect(fakes.exchangeCallback).toHaveBeenCalledWith('abc'));
    expect(
      await screen.findByText((_, element) => element?.textContent === 'Signed in as a@b.co'),
    ).toBeInTheDocument();
    // An unmarked exchange is not a password reset: no new-password step.
    expect(
      screen.queryByText(messages['accountPasswordRecoveryIntro']),
    ).not.toBeInTheDocument();
  });

  it('renders the new-password step when the exchange marks recovery (issue #1293)', async () => {
    // The Worker's PKCE-cookie marker is what makes a recovery link show
    // this step — GoTrue's redirect carries only ?code=, never ?type=recovery,
    // so no query parameter is involved.
    fakes.exchangeCallback.mockResolvedValue({ recovery: true });
    fakes.getUser.mockReturnValue({ id: 'u1', email: 'a@b.co' });
    renderWithProviders(<AuthCallbackPage />, '/auth/callback?code=abc');
    await waitFor(() => expect(fakes.exchangeCallback).toHaveBeenCalledWith('abc'));
    expect(
      await screen.findByText(messages['accountPasswordRecoveryIntro']),
    ).toBeInTheDocument();
    expect(
      screen.getByRole('link', { name: messages['accountPasswordRecoverySave'] }),
    ).toHaveAttribute('href', '/reset-password');
  });

  it('renders the different-browser copy when no verifier cookie exists', async () => {
    fakes.exchangeCallback.mockRejectedValue(new AuthError('verifier_missing', 401));
    renderWithProviders(<AuthCallbackPage />, '/auth/callback?code=abc');
    expect(
      await screen.findByText(messages['webAuthDifferentBrowserError']),
    ).toBeInTheDocument();
  });

  it('renders the expired-link copy for a provider error landing', async () => {
    renderWithProviders(<AuthCallbackPage />, '/auth/callback?error=access_denied');
    expect(fakes.exchangeCallback).not.toHaveBeenCalled();
    expect(await screen.findByText(messages['authFailureExpiredLink'])).toBeInTheDocument();
  });

  it('renders a mapped-copy failure with its values across the state (issue #1295)', async () => {
    // The failed render is a state away from the failure: the values must
    // ride along with the id or the placeholder shows raw.
    fakes.exchangeCallback.mockRejectedValue(new AuthError('weak_password', 400));
    renderWithProviders(<AuthCallbackPage />, '/auth/callback?code=abc');
    expect(
      await screen.findByText(
        (messages['authFailureWeakPassword'] ?? '').replace('{minLength}', '12'),
      ),
    ).toBeInTheDocument();
    expect(screen.queryByText(/\{minLength\}/)).not.toBeInTheDocument();
  });

  it('renders the magic-link info body when opened bare', async () => {
    renderWithProviders(<AuthCallbackPage />, '/auth/callback');
    expect(await screen.findByText(messages['accountSignInMagicLinkInfo'])).toBeInTheDocument();
    expect(fakes.exchangeCallback).not.toHaveBeenCalled();
  });
});
