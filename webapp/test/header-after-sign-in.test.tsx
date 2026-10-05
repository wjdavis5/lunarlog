import { QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { AppIntlProvider } from '../src/i18n/i18n';
import messages from '../src/i18n/messages.en.json';
import { createAppQueryClient } from '../src/lib/queries';

/**
 * The header follows the session without a reload.
 *
 * Signing in on the page (a password, an emailed code) and signing out both
 * cross an identity boundary, where everything cached for the old session
 * is dropped. The header sits above every page and is never unmounted, so
 * it has to notice the boundary too. It did not: emptying the query cache
 * left the header reading a session query that was no longer in the cache,
 * so after signing in it went on offering "Sign in", with no "Today" or
 * "Account" link, until the page was reloaded.
 *
 * These tests run the real shell, router and auth hooks. Only the auth
 * client (the network) and the home page are replaced.
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
  forgetSession: vi.fn(),
}));

vi.mock('../src/lib/auth', async () => {
  const actual = await vi.importActual<typeof import('../src/lib/auth')>('../src/lib/auth');
  return { ...actual, webAuth: fakes };
});

vi.mock('../src/pages/TodayPage', () => ({
  TodayPage: () => <main data-testid="home-stub" />,
}));

import { App } from '../src/App';
import { AUTH_SESSION_QUERY_KEY } from '../src/lib/authQueries';

const SIGN_IN = messages['accountSectionSignIn'];
const SIGN_OUT = messages['webAuthSignOutAction'];
const ACCOUNT = messages['accountSectionTitle'];
const TODAY = messages['calendarTodayTooltip'];

/** The fake client's session, as the real one keeps it: in memory. */
function setSession(signedIn: boolean) {
  fakes.getToken.mockResolvedValue(signedIn ? 'token' : null);
  fakes.getUser.mockReturnValue(signedIn ? { id: 'u1', email: 'a@b.co' } : null);
}

/**
 * Renders the app and waits for the header's first read of the session to
 * land. Without the wait a test changes the session while that first read
 * is still in flight, and the header then picks the new session up by
 * accident: the bug only shows once the header is showing a settled state.
 */
async function renderApp() {
  const queryClient = createAppQueryClient();
  render(
    <AppIntlProvider>
      <QueryClientProvider client={queryClient}>
        <App />
      </QueryClientProvider>
    </AppIntlProvider>,
  );
  await waitFor(() => expect(queryClient.getQueryData(AUTH_SESSION_QUERY_KEY)).toBeDefined());
}

function header() {
  return within(screen.getByRole('banner'));
}

function fill(label: string | undefined, value: string) {
  fireEvent.change(screen.getByLabelText(label ?? 'missing'), { target: { value } });
}

beforeEach(() => {
  setSession(false);
  fakes.signInWithPassword.mockImplementation(async () => {
    setSession(true);
  });
  fakes.verifyOtp.mockImplementation(async () => {
    setSession(true);
  });
  fakes.signOut.mockImplementation(async () => {
    setSession(false);
  });
});

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
});

describe('the header after the session changes', () => {
  it('shows the signed-in links as soon as a password sign-in succeeds', async () => {
    await renderApp();
    // The app has one router for the module, so each test walks to its page.
    fireEvent.click(await header().findByRole('link', { name: SIGN_IN }));
    fill(messages['accountSignInEmailLabel'], 'a@b.co');
    fill(messages['accountSignInPasswordLabel'], 'long enough password');
    fireEvent.click(screen.getByRole('button', { name: messages['accountSignInAction'] }));

    await waitFor(() => expect(fakes.signInWithPassword).toHaveBeenCalledOnce());
    expect(await header().findByRole('link', { name: ACCOUNT })).toHaveAttribute(
      'href',
      '/account',
    );
    expect(header().getByRole('link', { name: TODAY })).toHaveAttribute('href', '/');
    expect(header().getByRole('link', { name: SIGN_OUT })).toHaveAttribute('href', '/sign-in');
    expect(header().queryByRole('link', { name: SIGN_IN })).toBeNull();
  });

  it('goes back to the signed-out links as soon as sign-out succeeds', async () => {
    setSession(true);
    await renderApp();
    fireEvent.click(await header().findByRole('link', { name: SIGN_OUT }));
    // The sign-in page, signed in, is where the sign-out choices live.
    fireEvent.click(await screen.findByRole('button', { name: SIGN_OUT }));

    await waitFor(() => expect(fakes.signOut).toHaveBeenCalledOnce());
    expect(await header().findByRole('link', { name: SIGN_IN })).toHaveAttribute(
      'href',
      '/sign-in',
    );
    expect(header().queryByRole('link', { name: ACCOUNT })).toBeNull();
    expect(header().queryByRole('link', { name: TODAY })).toBeNull();
  });
});
