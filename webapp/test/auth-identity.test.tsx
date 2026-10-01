import { QueryClientProvider } from '@tanstack/react-query';
import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { createElement, type ReactNode } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import {
  AUTH_SESSION_QUERY_KEY,
  useResetWebDataOnIdentityChange,
  type AuthStatus,
} from '../src/lib/authQueries';
import { emptySyncedData, getSyncedDataCache } from '../src/lib/domain';
import { createAppQueryClient, SYNCED_DATA_QUERY_KEY } from '../src/lib/queries';
import type { ProfileRow } from '../src/lib/schemas';
import type { AppSupabaseClient } from '../src/lib/supabase';
import { AppIntlProvider } from '../src/i18n/i18n';
import messages from '../src/i18n/messages.en.json';

/**
 * The identity boundary (issue #1281): the synced-data snapshot, the pull
 * cursors, and the TanStack cache belong to exactly one signed-in account.
 * Sign-out drops them in a `finally` (even when the POST fails), every
 * sign-in path drops them on session adoption, and the shell's identity
 * watcher drops them whenever the session's user id changes — all in one
 * tab, with no reload. The auth client is mocked; the domain cache and the
 * query client are the real ones, so the assertions cover the actual
 * module state two accounts would share.
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

// The mocked module re-exports the real AuthError, so failures render the
// same mapped copy as production.
import { AuthError } from '../src/lib/auth';
import { SignInPage } from '../src/pages/SignInPage';

const USER_A = { id: 'user-aaaaaaaa', email: 'a@b.co' } as const;
const USER_B = { id: 'user-bbbbbbbb', email: 'b@b.co' } as const;

const ULID_A = '01ARZ3NDEKTSV4RRFFQ69G5FAV';
const ULID_B = '01ARZ3NDEKTSV4RRFFQ69G5FAW';

function profileRow(overrides: Partial<ProfileRow> = {}): ProfileRow {
  return {
    id: ULID_A,
    user_id: '00000000-0000-0000-0000-000000000001',
    display_name: 'Maya',
    is_minor: false,
    sort_order: 0,
    archived_at: null,
    created_at: '2026-09-01T00:00:00Z',
    updated_at: '2026-09-01T00:00:00Z',
    deleted_at: null,
    server_version: 1,
    mode: 'standard',
    birth_year: 1988,
    relationship: 'self',
    ...overrides,
  };
}

type RpcHandler = (
  name: string,
  params: Record<string, unknown>,
) => Promise<{ data: unknown; error: { message: string } | null }>;

/** The rpc-only fake (domain.test.ts's shape): refresh pulls over sync_pull. */
function fakeRpcClient(handler: RpcHandler) {
  const calls: { name: string; params: Record<string, unknown> }[] = [];
  const rpc = vi
    .fn()
    .mockImplementation(async (name: string, params: Record<string, unknown>) => {
      calls.push({ name, params });
      return handler(name, params);
    });
  return { client: { rpc } as unknown as AppSupabaseClient, calls };
}

/** Pulls one profile at server_version 7 into the real shared cache. */
async function seedSharedCache(): Promise<void> {
  const { client } = fakeRpcClient(async () => ({
    data: { profiles: [profileRow({ server_version: 7 })] },
    error: null,
  }));
  await getSyncedDataCache().refresh(client);
  expect(getSyncedDataCache().current().profiles).toHaveLength(1);
}

function renderWithQueryClient(ui: React.ReactElement) {
  const queryClient = createAppQueryClient();
  function Wrapper({ children }: { children: ReactNode }) {
    return createElement(
      AppIntlProvider,
      null,
      createElement(QueryClientProvider, { client: queryClient }, children),
    );
  }
  const view = render(ui, { wrapper: Wrapper });
  return { queryClient, ...view };
}

function renderSignInPage() {
  return renderWithQueryClient(createElement(MemoryRouter, null, createElement(SignInPage)));
}

function fill(label: string, value: string) {
  fireEvent.change(screen.getByLabelText(label), { target: { value } });
}

function submitAs(email: string) {
  fill(messages['accountSignInEmailLabel'] ?? '', email);
  fill(messages['accountSignInPasswordLabel'] ?? '', 'long enough password');
  fireEvent.click(screen.getByRole('button', { name: messages['accountSignInAction'] }));
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
  getSyncedDataCache().reset();
});

describe('the sign-out → sign-in identity boundary (issue #1281)', () => {
  it('sign-out drops A synced cache and query, and B signs in from zero cursors — no reload', async () => {
    // A signs in and has pulled: the cache holds A's profile and cursors.
    fakes.getToken.mockResolvedValue('token-a');
    fakes.getUser.mockReturnValue(USER_A);
    await seedSharedCache();
    const { queryClient } = renderSignInPage();
    queryClient.setQueryData(SYNCED_DATA_QUERY_KEY, getSyncedDataCache().current());
    expect(
      await screen.findByText((_, element) => element?.textContent === 'Signed in as a@b.co'),
    ).toBeInTheDocument();

    // The sign-out POST ends the session server-side; the next probe is out.
    fakes.signOut.mockImplementation(async () => {
      fakes.getToken.mockResolvedValue(null);
      fakes.getUser.mockReturnValue(null);
    });
    fireEvent.click(
      screen.getByRole('button', { name: messages['webAuthSignOutEverywhereAction'] }),
    );

    // A's snapshot and every cached query go with A — the signed-out page
    // renders nothing of the old account.
    await waitFor(() => {
      expect(getSyncedDataCache().current()).toEqual(emptySyncedData());
      expect(queryClient.getQueryData(SYNCED_DATA_QUERY_KEY)).toBeUndefined();
    });
    expect(
      await screen.findByRole('button', { name: messages['accountSignInAction'] }),
    ).toBeInTheDocument();

    // B signs in on the same mounted page — no reload.
    fakes.signInWithPassword.mockImplementation(async () => {
      fakes.getToken.mockResolvedValue('token-b');
      fakes.getUser.mockReturnValue(USER_B);
    });
    submitAs('b@b.co');
    expect(
      await screen.findByText((_, element) => element?.textContent === 'Signed in as b@b.co'),
    ).toBeInTheDocument();

    // B's cache is B's own: still empty after the sign-in reset, and the
    // next pull starts from zero cursors — not from A's last positions.
    expect(getSyncedDataCache().current()).toEqual(emptySyncedData());
    // Captured at call time: the pull mutates (and the cache keeps) the
    // same cursors object it sends.
    let firstPullCursors: unknown;
    const { client: pullClient } = fakeRpcClient(async (_name, params) => {
      firstPullCursors ??= structuredClone(params.p_cursors);
      return {
        data: {
          profiles: [profileRow({ id: ULID_B, display_name: 'B-only', server_version: 3 })],
        },
        error: null,
      };
    });
    const snapshot = await getSyncedDataCache().refresh(pullClient);
    expect(firstPullCursors).toEqual({});
    expect(snapshot.profiles.map((row) => row.display_name)).toEqual(['B-only']);
  });

  it('a failed sign-out POST still drops the cache (the reset runs in a finally)', async () => {
    fakes.getToken.mockResolvedValue('token-a');
    fakes.getUser.mockReturnValue(USER_A);
    await seedSharedCache();
    const { queryClient } = renderSignInPage();
    queryClient.setQueryData(SYNCED_DATA_QUERY_KEY, getSyncedDataCache().current());
    expect(
      await screen.findByText((_, element) => element?.textContent === 'Signed in as a@b.co'),
    ).toBeInTheDocument();

    fakes.signOut.mockRejectedValue(new AuthError('network_error', 0));
    fireEvent.click(
      screen.getByRole('button', { name: messages['webAuthSignOutEverywhereAction'] }),
    );
    expect(await screen.findByText(messages['commonSomethingWentWrong'])).toBeInTheDocument();
    expect(getSyncedDataCache().current()).toEqual(emptySyncedData());
    expect(queryClient.getQueryData(SYNCED_DATA_QUERY_KEY)).toBeUndefined();
  });

  it('signing in as B drops data A left cached without a sign-out', async () => {
    // Signed out, but the synced-data cache still holds A — the mix hazard.
    await seedSharedCache();
    const { queryClient } = renderSignInPage();
    queryClient.setQueryData(SYNCED_DATA_QUERY_KEY, getSyncedDataCache().current());
    await screen.findByRole('button', { name: messages['accountSignInAction'] });
    expect(getSyncedDataCache().current().profiles).toHaveLength(1);

    fakes.signInWithPassword.mockImplementation(async () => {
      fakes.getToken.mockResolvedValue('token-b');
      fakes.getUser.mockReturnValue(USER_B);
    });
    submitAs('b@b.co');
    await waitFor(() => {
      expect(getSyncedDataCache().current()).toEqual(emptySyncedData());
      expect(queryClient.getQueryData(SYNCED_DATA_QUERY_KEY)).toBeUndefined();
    });
  });
});

describe('the shell identity watcher (issue #1281)', () => {
  it('drops the cache when the session resolves to a different user id', async () => {
    fakes.getToken.mockResolvedValue('token-a');
    fakes.getUser.mockReturnValue(USER_A);
    await seedSharedCache();
    function Harness() {
      useResetWebDataOnIdentityChange();
      return null;
    }
    const { queryClient } = renderWithQueryClient(createElement(Harness));

    // First resolve: the cache was built under A — nothing is dropped.
    await waitFor(() =>
      expect((queryClient.getQueryData(AUTH_SESSION_QUERY_KEY) as AuthStatus)?.userId).toBe(
        USER_A.id,
      ),
    );
    expect(getSyncedDataCache().current().profiles).toHaveLength(1);

    // A renewal adopts a different account — another tab signed in between
    // and replaced the refresh cookie. No auth mutation ran on this tab.
    fakes.getToken.mockResolvedValue('token-b');
    fakes.getUser.mockReturnValue(USER_B);
    await act(async () => {
      await queryClient.refetchQueries({ queryKey: AUTH_SESSION_QUERY_KEY });
    });
    await waitFor(() =>
      expect((queryClient.getQueryData(AUTH_SESSION_QUERY_KEY) as AuthStatus)?.userId).toBe(
        USER_B.id,
      ),
    );
    expect(getSyncedDataCache().current()).toEqual(emptySyncedData());
  });

  it('keeps the cache when the same account re-resolves', async () => {
    fakes.getToken.mockResolvedValue('token-a');
    fakes.getUser.mockReturnValue(USER_A);
    await seedSharedCache();
    function Harness() {
      useResetWebDataOnIdentityChange();
      return null;
    }
    const { queryClient } = renderWithQueryClient(createElement(Harness));
    await waitFor(() =>
      expect((queryClient.getQueryData(AUTH_SESSION_QUERY_KEY) as AuthStatus)?.userId).toBe(
        USER_A.id,
      ),
    );
    await act(async () => {
      await queryClient.refetchQueries({ queryKey: AUTH_SESSION_QUERY_KEY });
    });
    expect(getSyncedDataCache().current().profiles).toHaveLength(1);
  });
});
