import { QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter, Route, Routes, useLocation } from 'react-router';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { AppIntlProvider } from '../src/i18n/i18n';
import messages from '../src/i18n/messages.en.json';
import { createAppQueryClient } from '../src/lib/queries';

/**
 * A page that needs a session sends a signed-out visitor to sign in with a
 * `next` path (the invitation page is the first). These tests follow that
 * path through the sign-in pages: it is honoured when it is a path on this
 * site, carried between the pages, and ignored when it is anything else.
 */

const fakes = vi.hoisted(() => ({
  getToken: vi.fn<() => Promise<string | null>>(),
  getUser: vi.fn<() => { id: string; email: string | null } | null>(),
  signInWithPassword: vi.fn<() => Promise<void>>(),
  signUp: vi.fn<() => Promise<'signed_in' | 'confirmation_required'>>(),
  sendOtp: vi.fn<() => Promise<void>>(),
  verifyOtp: vi.fn<() => Promise<void>>(),
  signOut: vi.fn<() => Promise<void>>(),
  startOAuth: vi.fn(),
}));

vi.mock('../src/lib/auth', async () => {
  const { AuthError } =
    await vi.importActual<typeof import('../src/lib/auth')>('../src/lib/auth');
  return { AuthError, WebAuthClient: class {}, webAuth: fakes };
});

import { CodeEntryPage } from '../src/pages/CodeEntryPage';
import { SignInPage } from '../src/pages/SignInPage';
import { SignUpPage } from '../src/pages/SignUpPage';

const INVITE = '/invite?code=ABC123&kind=claim';
const NEXT = encodeURIComponent(INVITE);

/** Shows where the router ended up, query included. */
function Landing(props: { name: string }) {
  const location = useLocation();
  return (
    <div data-testid="landing">
      {props.name} {location.pathname}
      {location.search}
    </div>
  );
}

function renderAt(path: string) {
  return render(
    <AppIntlProvider>
      <QueryClientProvider client={createAppQueryClient()}>
        <MemoryRouter initialEntries={[path]}>
          <Routes>
            <Route path="/" element={<Landing name="home" />} />
            <Route path="/invite" element={<Landing name="invite" />} />
            <Route path="/sign-in" element={<SignInPage />} />
            <Route path="/sign-up" element={<SignUpPage />} />
            <Route path="/sign-in/code" element={<CodeEntryPage />} />
          </Routes>
        </MemoryRouter>
      </QueryClientProvider>
    </AppIntlProvider>,
  );
}

function fill(label: string, value: string) {
  fireEvent.change(screen.getByLabelText(label), { target: { value } });
}

function signedIn() {
  fakes.getToken.mockResolvedValue('access-1');
  fakes.getUser.mockReturnValue({ id: 'u1', email: 'a@b.co' });
}

beforeEach(() => {
  fakes.getToken.mockResolvedValue(null);
  fakes.getUser.mockReturnValue(null);
  fakes.signInWithPassword.mockResolvedValue(undefined);
  fakes.signUp.mockResolvedValue('confirmation_required');
  fakes.sendOtp.mockResolvedValue(undefined);
  fakes.verifyOtp.mockResolvedValue(undefined);
  fakes.signOut.mockResolvedValue(undefined);
});

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
});

describe('sign in, then back to where you were headed', () => {
  it('a password sign-in lands on the invitation, not the home page', async () => {
    renderAt(`/sign-in?next=${NEXT}`);
    fill(messages['accountSignInEmailLabel'], 'a@b.co');
    fill(messages['accountSignInPasswordLabel'], 'long enough password');
    // The session resolves signed-in once the sign-in call has landed.
    fakes.signInWithPassword.mockImplementation(async () => {
      signedIn();
    });
    fireEvent.click(screen.getByRole('button', { name: messages['accountSignInAction'] }));
    await waitFor(() =>
      expect(screen.getByTestId('landing')).toHaveTextContent(`invite ${INVITE}`),
    );
  });

  it('someone already signed in goes straight through', async () => {
    signedIn();
    renderAt(`/sign-in?next=${NEXT}`);
    await waitFor(() =>
      expect(screen.getByTestId('landing')).toHaveTextContent(`invite ${INVITE}`),
    );
  });

  it('without a return path the signed-in page is unchanged', async () => {
    signedIn();
    renderAt('/sign-in');
    expect(
      await screen.findByRole('button', { name: messages['webAuthSignOutAction'] }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole('link', { name: messages['webAuthContinueAction'] }),
    ).toHaveAttribute('href', '/');
  });

  it.each([
    ['another site', 'https://evil.example/invite'],
    ['a protocol-relative address', '//evil.example/invite'],
    ['a dot segment hiding a protocol-relative address', '/.//evil.example/invite'],
    ['an encoded slash hiding one', '/%2Fevil.example/invite'],
    ['a sign-in loop', '/sign-in'],
    ['a sign-in loop in other letter case', '/Sign-In/'],
  ])('ignores %s in next and shows the ordinary signed-in page', async (_label, bad) => {
    signedIn();
    renderAt(`/sign-in?next=${encodeURIComponent(bad)}`);
    expect(
      await screen.findByRole('button', { name: messages['webAuthSignOutAction'] }),
    ).toBeInTheDocument();
    expect(screen.queryByTestId('landing')).toBeNull();
  });

  it('carries the return path to the sign-up page and back', () => {
    renderAt(`/sign-in?next=${NEXT}`);
    expect(
      screen.getByRole('link', { name: messages['accountSignInToggleCreateInstead'] }),
    ).toHaveAttribute('href', `/sign-up?next=${NEXT}`);
    cleanup();
    renderAt(`/sign-up?next=${NEXT}`);
    expect(
      screen.getByRole('link', { name: messages['accountSignInToggleHaveAccount'] }),
    ).toHaveAttribute('href', `/sign-in?next=${NEXT}`);
  });

  it('carries it through the emailed code: send, verify, land on the invitation', async () => {
    renderAt(`/sign-in?next=${NEXT}`);
    fill(messages['accountSignInEmailLabel'], 'a@b.co');
    fireEvent.click(
      screen.getByRole('button', { name: messages['accountSignInMagicLinkSignIn'] }),
    );
    // The code screen, still holding the return path.
    const code = await screen.findByLabelText(messages['accountSignInCodeLabel']);
    fireEvent.change(code, { target: { value: '12345678' } });
    fireEvent.click(
      screen.getByRole('button', { name: messages['accountSignInVerifyCodeAction'] }),
    );
    await waitFor(() =>
      expect(screen.getByTestId('landing')).toHaveTextContent(`invite ${INVITE}`),
    );
  });

  it('a new account that needs no confirmation carries on to the invitation', async () => {
    fakes.signUp.mockResolvedValue('signed_in');
    renderAt(`/sign-up?next=${NEXT}`);
    fill(messages['accountSignInEmailLabel'], 'a@b.co');
    fill(messages['accountSignInPasswordLabel'], 'long enough password');
    fireEvent.click(
      screen.getByRole('button', { name: messages['accountSignInCreateAccountAction'] }),
    );
    await waitFor(() =>
      expect(screen.getByTestId('landing')).toHaveTextContent(`invite ${INVITE}`),
    );
  });

  it('a new account that must confirm first keeps the return path on its code link', async () => {
    renderAt(`/sign-up?next=${NEXT}`);
    fill(messages['accountSignInEmailLabel'], 'a@b.co');
    fill(messages['accountSignInPasswordLabel'], 'long enough password');
    fireEvent.click(
      screen.getByRole('button', { name: messages['accountSignInCreateAccountAction'] }),
    );
    const link = await screen.findByRole('link', {
      name: messages['accountSignInVerifyCodeAction'],
    });
    expect(link.getAttribute('href')).toContain(`next=${NEXT}`);
    expect(link.getAttribute('href')).toContain('mode=signup');
  });

  it('the code screen with no return path still lands on the home page', async () => {
    renderAt('/sign-in/code?email=a%40b.co');
    fireEvent.change(screen.getByLabelText(messages['accountSignInCodeLabel']), {
      target: { value: '12345678' },
    });
    fireEvent.click(
      screen.getByRole('button', { name: messages['accountSignInVerifyCodeAction'] }),
    );
    await waitFor(() => expect(screen.getByTestId('landing')).toHaveTextContent('home /'));
  });
});
