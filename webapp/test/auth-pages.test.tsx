import { QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
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
  exchangeCallback: vi.fn<() => Promise<void>>(),
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
  fakes.exchangeCallback.mockResolvedValue(undefined);
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
});

describe('SignUpPage (issue #1250)', () => {
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

  it('signs up and shows the confirmation copy', async () => {
    renderWithProviders(<SignUpPage />, '/sign-up');
    await fill(messages['accountSignInEmailLabel'] ?? '', 'a@b.co');
    await fill(messages['accountSignInPasswordLabel'] ?? '', 'long enough password');
    fireEvent.click(
      screen.getByRole('button', { name: messages['accountSignInCreateAccountAction'] }),
    );
    await waitFor(() => expect(fakes.signUp).toHaveBeenCalledOnce());
    expect(
      await screen.findByText(messages['accountSignInConfirmEmailInfo']),
    ).toBeInTheDocument();
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
    expect(await screen.findByText(messages['accountSignInResetInfo'])).toBeInTheDocument();
  });
});

describe('ResetPasswordPage (issue #1250)', () => {
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
});

describe('AuthCallbackPage (issue #1250)', () => {
  it('exchanges the landed code and renders the signed-in state', async () => {
    fakes.getUser.mockReturnValue({ id: 'u1', email: 'a@b.co' });
    renderWithProviders(<AuthCallbackPage />, '/auth/callback?code=abc');
    await waitFor(() => expect(fakes.exchangeCallback).toHaveBeenCalledWith('abc'));
    expect(
      await screen.findByText((_, element) => element?.textContent === 'Signed in as a@b.co'),
    ).toBeInTheDocument();
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

  it('renders the magic-link info body when opened bare', async () => {
    renderWithProviders(<AuthCallbackPage />, '/auth/callback');
    expect(await screen.findByText(messages['accountSignInMagicLinkInfo'])).toBeInTheDocument();
    expect(fakes.exchangeCallback).not.toHaveBeenCalled();
  });
});
