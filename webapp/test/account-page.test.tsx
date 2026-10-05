import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { AppIntlProvider } from '../src/i18n/i18n';
import messages from '../src/i18n/messages.en.json';
import { AUTH_SESSION_QUERY_KEY, IDENTITIES_QUERY_KEY } from '../src/lib/authQueries';
import { AccountPage } from '../src/pages/AccountPage';

/**
 * Page tests for the web account surface (issue #1256). The auth client's
 * `webAuth` singleton is fully mocked (the client's own contract is
 * auth.test.ts's business); everything else — the query wiring, the copy
 * mapping, the Apple-ceremony landing, the flow guards — runs for real.
 */

const authMocks = vi.hoisted(() => ({
  getToken: vi.fn(),
  getUser: vi.fn(() => ({ id: 'u1', email: 'a@example.com' })),
  getIdentities: vi.fn(),
  startIdentityLink: vi.fn(),
  unlinkIdentity: vi.fn(async () => undefined),
  signOut: vi.fn(async () => undefined),
  updatePassword: vi.fn(async () => undefined),
  deleteAccount: vi.fn(async () => undefined),
  completeAppleDelete: vi.fn(async () => undefined),
  startAppleDelete: vi.fn(),
  forgetSession: vi.fn(),
  restoreSession: vi.fn(),
}));

vi.mock('../src/lib/auth', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  webAuth: authMocks,
}));

const supabaseMocks = vi.hoisted(() => ({
  getSupabaseClient: vi.fn(() => ({ rpc: vi.fn() })),
}));

vi.mock('../src/lib/supabase', () => supabaseMocks);

const exportMocks = vi.hoisted(() => ({
  downloadAccountExport: vi.fn(async () => undefined),
}));

vi.mock('../src/lib/export', () => exportMocks);

const IDENTITIES = { email: 'a@example.com', providers: ['email', 'google'] };

function renderPage(
  options: { signedIn?: boolean; identities?: typeof IDENTITIES | Error; entry?: string } = {},
) {
  const { signedIn = false, identities, entry = '/account' } = options;
  const queryClient = new QueryClient({
    // staleTime: Infinity keeps the seeded session data authoritative — the
    // mocked getToken's null answer must never race a background refetch
    // into flipping the page signed-out mid-test. Invalidation still
    // refetches (the unlink test relies on that).
    defaultOptions: { queries: { retry: false, staleTime: Infinity } },
  });
  queryClient.setQueryData(AUTH_SESSION_QUERY_KEY, {
    signedIn,
    email: signedIn ? 'a@example.com' : null,
    userId: signedIn ? 'u1' : null,
  });
  authMocks.getIdentities.mockReset();
  if (identities instanceof Error) {
    authMocks.getIdentities.mockRejectedValue(identities);
  } else if (identities !== undefined) {
    authMocks.getIdentities.mockResolvedValue(identities);
  } else {
    authMocks.getIdentities.mockResolvedValue({ email: null, providers: [] });
  }
  const view = render(
    <AppIntlProvider>
      <QueryClientProvider client={queryClient}>
        <MemoryRouter initialEntries={[entry]}>
          <Routes>
            <Route path="/" element={<div>home</div>} />
            <Route path="/account" element={<AccountPage />} />
            <Route path="/sign-in" element={<div>sign-in</div>} />
          </Routes>
        </MemoryRouter>
      </QueryClientProvider>
    </AppIntlProvider>,
  );
  return { queryClient, view };
}

async function renderSignedIn(identities: typeof IDENTITIES | Error = IDENTITIES) {
  const { queryClient, view } = renderPage({ signedIn: true, identities });
  await screen.findByText(
    messages['accountSectionSignedInAs'].replace('{email}', 'a@example.com'),
  );
  return { queryClient, view };
}

describe('AccountPage (issue #1256)', () => {
  beforeEach(() => {
    // A signed-in user's getToken renews from the refresh cookie and keeps
    // resolving a token — every auth mutation's success invalidates the
    // session query, and the refetch must land back on signed-in.
    authMocks.getToken.mockResolvedValue('access-1');
    authMocks.getIdentities.mockReset();
    authMocks.startIdentityLink.mockReset();
    authMocks.unlinkIdentity.mockReset();
    authMocks.deleteAccount.mockReset();
    authMocks.completeAppleDelete.mockReset();
    authMocks.startAppleDelete.mockReset();
    authMocks.signOut.mockReset();
    authMocks.updatePassword.mockReset();
    supabaseMocks.getSupabaseClient.mockClear();
    exportMocks.downloadAccountExport.mockClear();
  });

  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it('signed out shows only the sign-in prompt', async () => {
    renderPage({ signedIn: false });

    // The prompt is a link to the sign-in screen (the bare words "Sign in"
    // are ambiguous — the catalogue's two ids render the same string).
    expect(
      await screen.findByRole('link', { name: messages['accountSignInTitle'] }),
    ).toHaveAttribute('href', '/sign-in');
    expect(screen.queryByText(messages['yourDataExportTitle'])).toBeNull();
    expect(authMocks.getIdentities).not.toHaveBeenCalled();
  });

  it('signed in renders the linked methods: the email row never removable, linked providers removable', async () => {
    await renderSignedIn();

    expect(screen.getByText(messages['accountProviderLabelEmail'])).toBeDefined();
    expect(screen.getByText(messages['accountProviderLabelGoogle'])).toBeDefined();
    // Google is linked: the remove affordance carries its label.
    expect(
      await screen.findByText(
        messages['accountSectionRemoveProvider'].replace('{provider}', 'Google'),
      ),
    ).toBeDefined();
    // Apple is not linked: the add affordance instead.
    expect(screen.getByText(messages['accountSectionAddApple'])).toBeDefined();
    // The line inviting another way to sign in sits under the one method
    // that can still be added, not under Email or the linked Google.
    const invitations = screen.getAllByText(messages['accountSectionLinkSubtitle']);
    expect(invitations).toHaveLength(1);
    expect(invitations[0]?.closest('li')).toHaveTextContent(
      messages['accountProviderLabelApple'],
    );
    // The email row carries no remove button at all.
    expect(
      screen.queryByText(
        messages['accountSectionRemoveProvider'].replace('{provider}', 'Email'),
      ),
    ).toBeNull();
  });

  it('linking hands the provider URL to the browser', async () => {
    await renderSignedIn({ email: 'a@example.com', providers: ['email'] });
    authMocks.startIdentityLink.mockResolvedValue(
      'https://appleid.apple.com/auth/authorize?x=1',
    );
    const assigned: string[] = [];
    const originalLocation = window.location;
    Object.defineProperty(window, 'location', {
      configurable: true,
      value: { assign: (url: string) => assigned.push(url) },
    });
    try {
      fireEvent.click(await screen.findByText(messages['accountSectionAddApple']));

      await waitFor(() =>
        expect(assigned).toEqual(['https://appleid.apple.com/auth/authorize?x=1']),
      );
      expect(authMocks.startIdentityLink).toHaveBeenCalledWith('apple');
    } finally {
      Object.defineProperty(window, 'location', {
        configurable: true,
        value: originalLocation,
      });
    }
  });

  it('unlinking confirms inline in the row, then calls the client with the provider', async () => {
    const { queryClient } = await renderSignedIn();

    fireEvent.click(
      await screen.findByText(
        messages['accountSectionRemoveProvider'].replace('{provider}', 'Google'),
      ),
    );
    expect(await screen.findByText(messages['accountSectionRemove'])).toBeDefined();
    fireEvent.click(screen.getByText(messages['accountSectionRemove']));

    await waitFor(() => expect(authMocks.unlinkIdentity).toHaveBeenCalledWith('google'));
    // The methods list refreshes after an unlink (the initial load plus the
    // invalidation's refetch — isInvalidated itself clears once that fast
    // refetch lands).
    await waitFor(() => expect(authMocks.getIdentities).toHaveBeenCalledTimes(2));
    expect(queryClient.getQueryState(IDENTITIES_QUERY_KEY)?.data).toEqual(IDENTITIES);
  });

  it('a failed unlink renders the mapped auth-failure copy', async () => {
    const { AuthError } = await import('../src/lib/auth');
    authMocks.unlinkIdentity.mockRejectedValue(
      new (AuthError as new (code: string, status: number) => Error)(
        'identity_already_exists',
        400,
      ),
    );
    await renderSignedIn();

    fireEvent.click(
      await screen.findByText(
        messages['accountSectionRemoveProvider'].replace('{provider}', 'Google'),
      ),
    );
    fireEvent.click(await screen.findByText(messages['accountSectionRemove']));

    expect(await screen.findByText(messages['authFailureIdentityTaken'])).toBeDefined();
  });

  it('change password validates length and match before calling the client', async () => {
    await renderSignedIn();

    const newPassword = screen.getByLabelText(messages['accountPasswordRecoveryNewLabel']);
    const confirmPassword = screen.getByLabelText(
      messages['accountPasswordRecoveryConfirmLabel'],
    );
    const save = screen.getByText(messages['accountPasswordRecoverySave']);

    // Too short: the length error, no call.
    fireEvent.change(newPassword, { target: { value: 'short' } });
    fireEvent.change(confirmPassword, { target: { value: 'short' } });
    fireEvent.click(save);
    expect(
      await screen.findByText(
        messages['accountPasswordRecoveryLengthError'].replace('{length}', '12'),
      ),
    ).toBeDefined();
    expect(authMocks.updatePassword).not.toHaveBeenCalled();

    // Mismatch: the mismatch error, no call.
    fireEvent.change(newPassword, { target: { value: 'a'.repeat(12) } });
    fireEvent.change(confirmPassword, { target: { value: 'b'.repeat(12) } });
    fireEvent.click(save);
    expect(
      await screen.findByText(messages['accountPasswordRecoveryMismatchError']),
    ).toBeDefined();
    expect(authMocks.updatePassword).not.toHaveBeenCalled();

    // Valid: the call, then the saved line.
    fireEvent.change(confirmPassword, { target: { value: 'a'.repeat(12) } });
    fireEvent.click(save);
    await waitFor(() => expect(authMocks.updatePassword).toHaveBeenCalledWith('a'.repeat(12)));
    expect(await screen.findByText(messages['webDaySaved'])).toBeDefined();
  });

  it('heads the sign-out card with a label, not the dialog question', async () => {
    await renderSignedIn();
    expect(
      screen.getByRole('heading', { level: 2, name: messages['accountSectionSignOut'] }),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole('heading', { name: messages['accountSectionSignOutTitle'] }),
    ).toBeNull();
  });

  it('ties the password length rule to the new-password field', async () => {
    await renderSignedIn();
    expect(
      screen.getByLabelText(messages['accountPasswordRecoveryNewLabel']),
    ).toHaveAccessibleDescription(/at least 12 characters/i);
  });

  it('titles the page in the display face, like the other pages', async () => {
    await renderSignedIn();
    expect(screen.getByRole('heading', { level: 1 })).toHaveClass('display');
  });

  it('sign out and sign out everywhere pass their scopes through', async () => {
    // One scope per render: a landed sign-out drops the page's session data
    // (the mutation's reset), which is the product's behavior, not a bug —
    // the second scope needs its own signed-in page.
    await renderSignedIn();
    fireEvent.click(screen.getByRole('button', { name: messages['accountSectionSignOut'] }));
    await waitFor(() => expect(authMocks.signOut).toHaveBeenCalledWith('local'));

    cleanup();
    await renderSignedIn();
    fireEvent.click(
      screen.getByRole('button', { name: messages['accountSectionSignOutEverywhere'] }),
    );
    await waitFor(() => expect(authMocks.signOut).toHaveBeenCalledWith('global'));
  });

  it('the export tile downloads through the domain-backed exporter and maps its failure', async () => {
    await renderSignedIn();

    fireEvent.click(screen.getByText(messages['settingsExportRangeConfirm']));
    await waitFor(() => expect(exportMocks.downloadAccountExport).toHaveBeenCalledTimes(1));
    expect(supabaseMocks.getSupabaseClient).toHaveBeenCalled();

    // A failure lands on the catalogue's export-failure copy.
    exportMocks.downloadAccountExport.mockRejectedValueOnce(new Error('boom'));
    fireEvent.click(screen.getByText(messages['settingsExportRangeConfirm']));
    expect(await screen.findByText(messages['accountExportFailure'])).toBeDefined();
  });

  it('deletion asks the server first; apple_code_required turns into the Apple ceremony', async () => {
    const { DeletionError } = await import('../src/lib/auth');
    authMocks.deleteAccount.mockRejectedValue(
      new (DeletionError as new (code: string, status: number) => Error)(
        'apple_code_required',
        400,
      ),
    );
    await renderSignedIn();

    // Role-scoped: the card title shares the tile button's string.
    fireEvent.click(screen.getByRole('button', { name: messages['accountSectionDelete'] }));
    // The inline dialog: body, ack, confirm, cancel.
    expect(screen.getByText(messages['webAccountDeleteBody'])).toBeDefined();
    expect(screen.getByText(messages['accountDeleteDialogAck'])).toBeDefined();
    fireEvent.click(
      screen.getByRole('button', { name: messages['accountDeleteDialogConfirm'] }),
    );

    await waitFor(() => expect(authMocks.deleteAccount).toHaveBeenCalledWith(null, 'web'));
    // The nothing-was-deleted copy, then the ceremony's Continue button.
    expect(await screen.findByText(messages['accountDeletionAppleCodeRequired'])).toBeDefined();
    expect(authMocks.startAppleDelete).not.toHaveBeenCalled();
    fireEvent.click(screen.getByText(messages['webAuthContinueAction']));
    expect(authMocks.startAppleDelete).toHaveBeenCalledTimes(1);
  });

  it('a deletion failure after the rows are gone renders its own copy', async () => {
    const { DeletionError } = await import('../src/lib/auth');
    authMocks.deleteAccount.mockRejectedValue(
      new (DeletionError as new (code: string, status: number) => Error)(
        'apple_revoke_failed',
        409,
      ),
    );
    await renderSignedIn();

    fireEvent.click(screen.getByRole('button', { name: messages['accountSectionDelete'] }));
    fireEvent.click(
      await screen.findByRole('button', { name: messages['accountDeleteDialogConfirm'] }),
    );

    expect(await screen.findByText(messages['accountDeletionAppleRevokeFailed'])).toBeDefined();
  });

  it('the Apple landing completes the state check, then deletes with the fresh web code', async () => {
    authMocks.deleteAccount.mockResolvedValue(undefined);

    renderPage({
      signedIn: true,
      identities: IDENTITIES,
      entry: '/account?code=one-time-code&state=state-nonce',
    });
    await screen.findByText(messages['accountSectionTitle']);

    await waitFor(() =>
      expect(authMocks.completeAppleDelete).toHaveBeenCalledWith(
        'one-time-code',
        'state-nonce',
      ),
    );
    await waitFor(() =>
      expect(authMocks.deleteAccount).toHaveBeenCalledWith('one-time-code', 'web'),
    );
  });

  it('a failed state check shows the mapped copy and never deletes', async () => {
    const { AuthError } = await import('../src/lib/auth');
    authMocks.completeAppleDelete.mockRejectedValue(
      new (AuthError as new (code: string, status: number) => Error)('state_mismatch', 403),
    );

    renderPage({
      signedIn: true,
      identities: IDENTITIES,
      entry: '/account?code=c&state=wrong',
    });

    await waitFor(() => expect(authMocks.completeAppleDelete).toHaveBeenCalled());
    // state_mismatch is not one of the table's named codes: the generic copy.
    await waitFor(() =>
      expect(screen.getByText(messages['commonSomethingWentWrong'])).toBeDefined(),
    );
    expect(authMocks.deleteAccount).not.toHaveBeenCalled();
  });
});
