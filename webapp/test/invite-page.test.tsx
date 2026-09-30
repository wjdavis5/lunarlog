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

function renderAt(path: string) {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <AppIntlProvider>
      <QueryClientProvider client={queryClient}>
        <MemoryRouter initialEntries={[path]}>
          <Routes>
            <Route path="/" element={<div>home</div>} />
            <Route path="/invite" element={<InvitePage />} />
          </Routes>
        </MemoryRouter>
      </QueryClientProvider>
    </AppIntlProvider>,
  );
}

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
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
    const intro = (messages['acceptInviteSubjectIntro'] ?? '').replace('{profile}', 'Maya');
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
    const intro = (messages['sharingAcceptInvitePreviewIntro'] ?? '')
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
    // Navigated home after the accept.
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
  });

  it('claiming navigates home through the done state', async () => {
    sharingMocks.acceptOwnershipTransfer.mockResolvedValue({
      profile_id: ULID,
      profile_name: 'Maya',
      parent_role: 'co_parent',
      day_entries_rehomed: 0,
    });
    renderAt('/invite?code=T0KEN&kind=claim');
    fireEvent.click(screen.getByText(messages['claimProfileBecomeGuardianAction'] ?? ''));
    fireEvent.click(await screen.findByText(messages['sharingInviteGuardianDone'] ?? ''));
    await screen.findByText('home');
  });
});
