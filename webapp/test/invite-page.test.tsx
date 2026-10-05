import { QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { AppIntlProvider } from '../src/i18n/i18n';
import messages from '../src/i18n/messages.en.json';
import { QueryClient } from '@tanstack/react-query';
import { SharingError } from '../src/lib/sharing';
import { InvitePage } from '../src/pages/InvitePage';

/**
 * Invite-acceptance page tests (issue #1255): the preview states, the #957
 * subject acknowledgement and its best-effort consent record, the failure
 * copy, and the kind=claim route.
 */

const ULID = '01ARZ3NDEKTSV4RRFFQ69G5FAV';
const ME = '0f0f0f0f-0f0f-4f0f-8f0f-0f0f0f0f0f0f';

const fakeClient = { auth: { currentUser: { id: ME } } };

vi.mock('../src/lib/supabase', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  getSupabaseClient: () => fakeClient,
}));

const sharingMocks = vi.hoisted(() => ({
  previewGuardianInvitation: vi.fn(),
  acceptGuardianInvitation: vi.fn(),
  recordMinimumAgeAcknowledgement: vi.fn(),
  acceptOwnershipTransfer: vi.fn(),
}));

vi.mock('../src/lib/sharing', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  ...sharingMocks,
}));

// Issue #1282: the membership re-pull runs through this one queries-module
// helper — mocked here so the page tests pin *that* the mutations trigger
// it (the helper's own behavior is unit-tested in domain.test.ts through
// SyncedDataCache.repullAll).
const queriesMocks = vi.hoisted(() => ({
  repullMembershipData: vi.fn(() => Promise.resolve()),
}));

vi.mock('../src/lib/queries', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  repullMembershipData: queriesMocks.repullMembershipData,
}));

// The page now asks whether anyone is signed in before it shows a form.
// Signed in is the default here, as it was implicitly for every test below;
// the signed-out cases flip it.
const sessionState = vi.hoisted(() => ({
  value: { data: { signedIn: true, email: 'a@b.co', userId: 'me' } } as {
    data: { signedIn: boolean; email: string | null; userId: string | null } | undefined;
    isError?: boolean;
  },
}));

vi.mock('../src/lib/authQueries', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  // The slice of the query result the page reads: pending until there is
  // an answer, unless the check itself failed.
  useAuthSession: () => ({
    data: sessionState.value.data,
    isError: sessionState.value.isError === true,
    isPending: sessionState.value.data === undefined && sessionState.value.isError !== true,
  }),
}));

function renderAt(path: string) {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <AppIntlProvider>
      <QueryClientProvider client={queryClient}>
        <MemoryRouter initialEntries={[path]}>
          <Routes>
            <Route path="/" element={<div>home</div>} />
            <Route path="/invite" element={<InvitePage />} />
            <Route path="/sign-in" element={<div>sign-in page</div>} />
          </Routes>
        </MemoryRouter>
      </QueryClientProvider>
    </AppIntlProvider>,
  );
}

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
  sessionState.value = { data: { signedIn: true, email: 'a@b.co', userId: 'me' } };
});

// An invited guardian is often someone who has never used lunarlog. They
// arrive at this page signed out. It used to show them the accept form
// anyway: the preview failed, Accept failed, and nothing said to sign in.
describe('InvitePage for a visitor who is not signed in', () => {
  const next = (path: string) => `next=${encodeURIComponent(path)}`;

  it('says to sign in, and offers both ways in with this invitation as the return path', () => {
    sessionState.value = { data: { signedIn: false, email: null, userId: null } };
    renderAt(`/invite?code=${ULID}`);
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent(
      messages['sharingAcceptInviteTitle'],
    );
    expect(screen.getByText(messages['webInviteSignedOutBody'])).toBeInTheDocument();
    expect(
      screen.getByRole('link', { name: messages['accountSectionSignIn'] }),
    ).toHaveAttribute('href', `/sign-in?${next(`/invite?code=${ULID}`)}`);
    expect(
      screen.getByRole('link', { name: messages['accountSignInToggleCreateInstead'] }),
    ).toHaveAttribute('href', `/sign-up?${next(`/invite?code=${ULID}`)}`);
  });

  it('shows no accept form and makes no request', () => {
    sessionState.value = { data: { signedIn: false, email: null, userId: null } };
    renderAt(`/invite?code=${ULID}`);
    expect(
      screen.queryByRole('button', { name: messages['sharingAcceptInviteAccept'] }),
    ).toBeNull();
    expect(sharingMocks.previewGuardianInvitation).not.toHaveBeenCalled();
    expect(sharingMocks.acceptGuardianInvitation).not.toHaveBeenCalled();
  });

  it('keeps the whole link in the return path for an ownership claim', () => {
    sessionState.value = { data: { signedIn: false, email: null, userId: null } };
    renderAt(`/invite?code=${ULID}&kind=claim`);
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent(
      messages['sharingClaimProfileTitle'],
    );
    expect(
      screen.getByRole('link', { name: messages['accountSectionSignIn'] }),
    ).toHaveAttribute('href', `/sign-in?${next(`/invite?code=${ULID}&kind=claim`)}`);
    expect(sharingMocks.acceptOwnershipTransfer).not.toHaveBeenCalled();
  });

  it('waits, without a form, while the session is still being worked out', () => {
    sessionState.value = { data: undefined };
    renderAt(`/invite?code=${ULID}`);
    expect(screen.getByText(messages['sharingAcceptInvitePreviewLoading'])).toBeInTheDocument();
    expect(
      screen.queryByRole('button', { name: messages['sharingAcceptInviteAccept'] }),
    ).toBeNull();
    expect(screen.queryByRole('link', { name: messages['accountSectionSignIn'] })).toBeNull();
    expect(sharingMocks.previewGuardianInvitation).not.toHaveBeenCalled();
  });

  it('treats a session check that failed as signed out, not as loading for ever', () => {
    sessionState.value = { data: undefined, isError: true };
    renderAt(`/invite?code=${ULID}`);
    expect(screen.getByText(messages['webInviteSignedOutBody'])).toBeInTheDocument();
    expect(
      screen.getByRole('link', { name: messages['accountSectionSignIn'] }),
    ).toBeInTheDocument();
    expect(screen.queryByText(messages['sharingAcceptInvitePreviewLoading'])).toBeNull();
  });

  it('still reports a link with no code as invalid, signed in or not', () => {
    sessionState.value = { data: { signedIn: false, email: null, userId: null } };
    renderAt('/invite');
    expect(screen.getByText(messages['sharingFailureInvalidToken'])).toBeInTheDocument();
  });
});

describe('AcceptInviteForm (issue #1255)', () => {
  it('a missing code reads as an invalid link', () => {
    renderAt('/invite');
    expect(screen.getByText(messages['sharingFailureInvalidToken'] ?? '')).toBeInTheDocument();
    expect(sharingMocks.previewGuardianInvitation).not.toHaveBeenCalled();
  });

  it('a claim link without a code reads as an invalid transfer link', () => {
    renderAt('/invite?kind=claim');
    expect(screen.getByText(messages['transferFailureInvalidToken'] ?? '')).toBeInTheDocument();
    expect(sharingMocks.acceptOwnershipTransfer).not.toHaveBeenCalled();
  });

  it('a subject preview shows the plain-language promise and the parent-invite acknowledgement', async () => {
    sharingMocks.previewGuardianInvitation.mockResolvedValue({
      profile_display_name: 'Maya',
      role: 'caregiver',
      expires_at: '2026-10-02T00:00:00Z',
      is_subject: true,
    });
    renderAt('/invite?code=T0KEN');
    const intro = (messages['webInviteSubjectIntro'] ?? '').replace('{profile}', 'Maya');
    expect(await screen.findByText(intro)).toBeInTheDocument();
    expect(
      screen.getByText(messages['firstRunAgeAcknowledgementParentInviteLabel'] ?? ''),
    ).toBeInTheDocument();
    expect(
      screen.getByText(messages['firstRunAgeAcknowledgementParentInviteHint'] ?? ''),
    ).toBeInTheDocument();
  });

  it('an ordinary preview shows the role sentence and no acknowledgement', async () => {
    sharingMocks.previewGuardianInvitation.mockResolvedValue({
      profile_display_name: 'Maya',
      role: 'co_parent',
      expires_at: '2026-10-02T00:00:00Z',
      is_subject: false,
    });
    renderAt('/invite?code=T0KEN');
    const roleLabel = messages['guardianRoleLabelCoParent'] ?? '';
    const intro = (messages['webInvitePreviewIntro'] ?? '')
      .replace('{profileName}', 'Maya')
      .replace('{roleLabel}', roleLabel);
    expect(await screen.findByText(intro)).toBeInTheDocument();
    expect(
      screen.queryByText(messages['firstRunAgeAcknowledgementParentInviteLabel'] ?? ''),
    ).not.toBeInTheDocument();
  });

  it('a null preview reads as unavailable but accepting stays possible', async () => {
    sharingMocks.previewGuardianInvitation.mockResolvedValue(null);
    renderAt('/invite?code=T0KEN');
    expect(
      await screen.findByText(messages['sharingAcceptInvitePreviewUnavailable'] ?? ''),
    ).toBeInTheDocument();
    expect(screen.getByText(messages['sharingAcceptInviteAccept'] ?? '')).toBeInTheDocument();
  });

  it('a failed preview still allows accepting (the courtesy, never a gate)', async () => {
    sharingMocks.previewGuardianInvitation.mockRejectedValue(new SharingError('network'));
    renderAt('/invite?code=T0KEN');
    expect(
      await screen.findByText(messages['sharingAcceptInvitePreviewError'] ?? ''),
    ).toBeInTheDocument();
    expect(screen.getByText(messages['sharingAcceptInviteAccept'] ?? '')).toBeInTheDocument();
  });

  it('accepting a subject invitation records the parent-invite consent and navigates home', async () => {
    sharingMocks.previewGuardianInvitation.mockResolvedValue({
      profile_display_name: 'Maya',
      role: 'caregiver',
      expires_at: '2026-10-02T00:00:00Z',
      is_subject: true,
    });
    sharingMocks.acceptGuardianInvitation.mockResolvedValue({
      profile_id: ULID,
      profile_name: 'Maya',
      role: 'caregiver',
      is_subject: true,
    });
    sharingMocks.recordMinimumAgeAcknowledgement.mockResolvedValue(undefined);
    renderAt('/invite?code=T0KEN');
    fireEvent.click(await screen.findByText(messages['sharingAcceptInviteAccept'] ?? ''));
    await waitFor(() => {
      expect(sharingMocks.acceptGuardianInvitation).toHaveBeenCalledWith(
        fakeClient,
        'T0KEN',
        null,
      );
    });
    await waitFor(() => {
      expect(sharingMocks.recordMinimumAgeAcknowledgement).toHaveBeenCalledWith(
        fakeClient,
        expect.objectContaining({ consentVia: 'parent_invite' }),
      );
    });
    // The membership re-pull ran before the navigation (issue #1282): the
    // joined profile's history can only arrive on a from-zero pull.
    expect(queriesMocks.repullMembershipData).toHaveBeenCalledTimes(1);
    // Navigated home after the accept and its re-pull.
    await screen.findByText('home');
  });

  it('a typed accept failure renders its reviewed copy', async () => {
    sharingMocks.previewGuardianInvitation.mockResolvedValue(null);
    sharingMocks.acceptGuardianInvitation.mockRejectedValue(
      new SharingError('alreadyAccepted'),
    );
    renderAt('/invite?code=T0KEN');
    fireEvent.click(await screen.findByText(messages['sharingAcceptInviteAccept'] ?? ''));
    expect(
      await screen.findByText(messages['sharingFailureAlreadyAccepted'] ?? ''),
    ).toBeInTheDocument();
    // The re-pull is a success-path consequence — a failed accept made no
    // membership change to converge.
    expect(queriesMocks.repullMembershipData).not.toHaveBeenCalled();
  });

  // Issue #1504: a revoked invitation used to be mapped to the network
  // failure, so the form told the invitee to check her connection.
  it('a revoked invitation says to ask for a new one, not to check the connection', async () => {
    sharingMocks.previewGuardianInvitation.mockResolvedValue(null);
    sharingMocks.acceptGuardianInvitation.mockRejectedValue(new SharingError('revoked'));
    renderAt('/invite?code=T0KEN');
    fireEvent.click(await screen.findByText(messages['sharingAcceptInviteAccept'] ?? ''));
    expect(
      await screen.findByText('This invitation is no longer valid. Ask for a new one.'),
    ).toBeInTheDocument();
    expect(screen.queryByText(messages['commonNetworkError'] ?? '')).toBeNull();
  });
});

describe('ClaimTransferForm (kind=claim, issue #1255)', () => {
  it('renders the claim copy for a claim link', () => {
    renderAt('/invite?code=T0KEN&kind=claim');
    expect(
      screen.getByRole('heading', { name: messages['sharingClaimProfileTitle'] ?? '' }),
    ).toBeInTheDocument();
    expect(screen.getByText(messages['claimProfileBody'] ?? '')).toBeInTheDocument();
    expect(
      screen.getByText(messages['claimProfileBecomeGuardianAction'] ?? ''),
    ).toBeInTheDocument();
    expect(sharingMocks.previewGuardianInvitation).not.toHaveBeenCalled();
  });

  it('a claim failure carries the transfer copy, not the invitation copy', async () => {
    sharingMocks.acceptOwnershipTransfer.mockRejectedValue(new SharingError('alreadyArmed'));
    renderAt('/invite?code=T0KEN&kind=claim');
    fireEvent.click(screen.getByText(messages['claimProfileBecomeGuardianAction'] ?? ''));
    expect(
      await screen.findByText(messages['transferFailureAlreadyArmed'] ?? ''),
    ).toBeInTheDocument();
    expect(queriesMocks.repullMembershipData).not.toHaveBeenCalled();
  });

  it('claiming re-pulls membership data and navigates home through the done state', async () => {
    sharingMocks.acceptOwnershipTransfer.mockResolvedValue({
      profile_id: ULID,
      profile_name: 'Maya',
      parent_role: 'co_parent',
      day_entries_rehomed: 0,
    });
    renderAt('/invite?code=T0KEN&kind=claim');
    fireEvent.click(screen.getByText(messages['claimProfileBecomeGuardianAction'] ?? ''));
    // The claim inserts this account's guardianship without bumping the
    // profile's server_version (issue #1282) — the from-zero re-pull is
    // what converges the snapshot.
    await waitFor(() => {
      expect(queriesMocks.repullMembershipData).toHaveBeenCalledTimes(1);
    });
    fireEvent.click(await screen.findByText(messages['sharingInviteGuardianDone'] ?? ''));
    await screen.findByText('home');
  });
});
