import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useNavigate, useSearchParams } from 'react-router';

import pkg from '../../package.json';
import { useT } from '../i18n/t';
import { PROFILES_QUERY_KEY } from '../lib/queries';
import {
  acceptGuardianInvitation,
  acceptOwnershipTransfer,
  CONSENT_VIA_PARENT_INVITE,
  MINIMUM_AGE_POLICY_VERSION,
  previewGuardianInvitation,
  recordMinimumAgeAcknowledgement,
  sharingFailureMessageId,
  transferFailureMessageId,
  type ClaimedTransfer,
  type SharingFailureKind,
} from '../lib/sharing';
import { guardianRoleLabelId } from '../lib/roles';
import { getSupabaseClient } from '../lib/supabase';

/**
 * Invite acceptance on the web (issue #1255): `/invite?code=…&profile=…&kind=…`
 * — the same query the app's universal links carry (`lib/domain/sharing/
 * invite_links.dart`). `kind=claim` claims an ownership transfer; anything
 * else redeems a guardian invitation through `preview_guardian_invitation`
 * then `accept_guardian_invitation`, mirroring `AcceptInviteSheet` including
 * the #957 subject-invite acknowledgement and its best-effort consent record.
 * (Prediction-connection links are deferred past web v1 — epic #831 "Later"
 * — and read here as the uniform not-available preview state, R6.)
 */

/** The app-version stamp the consent record carries (`kAppVersionForExport`'s web twin). */
const WEBAPP_VERSION: string = pkg.version;

export function InvitePage() {
  const [params] = useSearchParams();
  const rawToken = params.get('code') ?? '';
  if ((params.get('kind') ?? '') === 'claim') {
    return <ClaimTransferForm rawToken={rawToken} />;
  }
  return <AcceptInviteForm rawToken={rawToken} />;
}

function AcceptInviteForm(props: { rawToken: string }) {
  const t = useT();
  const client = getSupabaseClient();
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const [displayName, setDisplayName] = useState('');
  const [failure, setFailure] = useState<SharingFailureKind | null>(null);

  const preview = useQuery({
    queryKey: ['invitePreview', props.rawToken],
    queryFn: () => {
      if (client === null) throw new Error('Supabase is not configured in this build');
      return previewGuardianInvitation(client, props.rawToken);
    },
    enabled: client !== null && props.rawToken !== '',
    // A courtesy, never a gate: a failed preview still lets the operator
    // accept and surface the RPC's own error (the app's #594 posture).
    retry: false,
  });

  const accept = useMutation({
    mutationFn: async () => {
      if (client === null) throw new Error('Supabase is not configured in this build');
      const name = displayName.trim() === '' ? null : displayName.trim();
      const result = await acceptGuardianInvitation(client, props.rawToken, name);
      // Issue #957: a subject acceptance is the parental-consent record —
      // write `consent_via = parent_invite` best-effort, exactly like the
      // app's `_recordParentInviteConsent` (the membership is already the
      // durable record even if this write fails).
      if (result.is_subject) {
        try {
          await recordMinimumAgeAcknowledgement(client, {
            consentVia: CONSENT_VIA_PARENT_INVITE,
            appVersion: WEBAPP_VERSION,
            policyVersion: MINIMUM_AGE_POLICY_VERSION,
          });
        } catch {
          // Best-effort by contract.
        }
      }
      return result;
    },
    onSuccess: () => {
      // The joined profile appears in the shell's list — the same
      // close-the-sheet outcome the app lands on.
      void queryClient.invalidateQueries({ queryKey: PROFILES_QUERY_KEY });
      navigate('/');
    },
    onError: (error) => setFailure(failureKind(error)),
  });

  if (client === null) {
    return (
      <main className="page">
        <h1 className="headline">{t('sharingAcceptInviteTitle')}</h1>
        <p className="body">{t('sharingAcceptInviteNeutralIntro')}</p>
        <p className="error">{t('sharingFailureNotSignedIn')}</p>
      </main>
    );
  }

  const previewData = preview.data ?? null;
  const isSubject = previewData?.is_subject ?? false;
  const roleLabel = previewData !== null ? t(guardianRoleLabelId(previewData.role)) : '';
  const busy = accept.isPending;

  return (
    <main className="page">
      <h1 className="headline">{t('sharingAcceptInviteTitle')}</h1>

      {props.rawToken === '' ? (
        <p className="error">{t('sharingFailureInvalidToken')}</p>
      ) : (
        <>
          {preview.isPending ? (
            <p className="body">{t('sharingAcceptInvitePreviewLoading')}</p>
          ) : null}
          {preview.isError ? (
            <p className="body">{t('sharingAcceptInvitePreviewError')}</p>
          ) : null}
          {preview.isSuccess && previewData === null ? (
            <p className="body">{t('sharingAcceptInvitePreviewUnavailable')}</p>
          ) : null}
          {previewData !== null ? (
            <p className="body">
              {isSubject
                ? t('acceptInviteSubjectIntro', { profile: previewData.profile_display_name })
                : t('sharingAcceptInvitePreviewIntro', {
                    profileName: previewData.profile_display_name,
                    roleLabel,
                  })}
            </p>
          ) : null}

          {isSubject ? (
            <div className="acknowledgement">
              <p>{t('firstRunAgeAcknowledgementParentInviteLabel')}</p>
              <p className="hint">{t('firstRunAgeAcknowledgementParentInviteHint')}</p>
            </div>
          ) : null}

          <div className="field">
            <label htmlFor="accept-name">{t('sharingAcceptInviteNameLabel')}</label>
            <input
              id="accept-name"
              value={displayName}
              disabled={busy}
              placeholder={t('sharingAcceptInviteNameHint')}
              onChange={(event) => setDisplayName(event.target.value)}
            />
          </div>
          {failure !== null ? (
            <p className="error">{t(sharingFailureMessageId(failure))}</p>
          ) : null}
          <div className="actions">
            <button
              type="button"
              className="button secondary"
              disabled={busy}
              onClick={() => navigate('/')}
            >
              {t('sharingAcceptInviteDecline')}
            </button>
            <button
              type="button"
              className="button"
              disabled={busy}
              onClick={() => accept.mutate()}
            >
              {t('sharingAcceptInviteAccept')}
            </button>
          </div>
        </>
      )}
    </main>
  );
}

function failureKind(error: unknown): SharingFailureKind {
  return (error as { kind?: SharingFailureKind } | null)?.kind ?? 'other';
}

function ClaimTransferForm(props: { rawToken: string }) {
  const t = useT();
  const client = getSupabaseClient();
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const [childName, setChildName] = useState('');
  const [parentLabel, setParentLabel] = useState('');
  const [failure, setFailure] = useState<SharingFailureKind | null>(null);
  const [claimed, setClaimed] = useState<ClaimedTransfer | null>(null);

  const claim = useMutation({
    mutationFn: async () => {
      if (client === null) throw new Error('Supabase is not configured in this build');
      return acceptOwnershipTransfer(client, props.rawToken, {
        childDisplayName: childName.trim() === '' ? null : childName.trim(),
        parentDisplayName: parentLabel.trim() === '' ? null : parentLabel.trim(),
      });
    },
    onSuccess: (result) => {
      setClaimed(result);
      setFailure(null);
      void queryClient.invalidateQueries({ queryKey: PROFILES_QUERY_KEY });
    },
    onError: (error) => setFailure(failureKind(error)),
  });

  if (client === null) {
    return (
      <main className="page">
        <h1 className="headline">{t('sharingClaimProfileTitle')}</h1>
        <p className="body">{t('claimProfileBody')}</p>
        <p className="error">{t('sharingFailureNotSignedIn')}</p>
      </main>
    );
  }

  if (claimed !== null) {
    return (
      <main className="page">
        <h1 className="headline">{t('sharingClaimProfileTitle')}</h1>
        <p className="body">{claimed.profile_name}</p>
        <div className="actions">
          <button type="button" className="button" onClick={() => navigate('/')}>
            {t('sharingInviteGuardianDone')}
          </button>
        </div>
      </main>
    );
  }

  return (
    <main className="page">
      <h1 className="headline">{t('sharingClaimProfileTitle')}</h1>
      <p className="body">{t('claimProfileBody')}</p>
      {props.rawToken === '' ? (
        <p className="error">{t('transferFailureInvalidToken')}</p>
      ) : null}
      {props.rawToken !== '' ? (
        <>
          <div className="field">
            <label htmlFor="claim-child">{t('sharingClaimProfileChildNameLabel')}</label>
            <input
              id="claim-child"
              value={childName}
              disabled={claim.isPending}
              placeholder={t('sharingClaimProfileChildNameHint')}
              onChange={(event) => setChildName(event.target.value)}
            />
          </div>
          <div className="field">
            <label htmlFor="claim-parent">{t('sharingClaimProfileParentLabelLabel')}</label>
            <input
              id="claim-parent"
              value={parentLabel}
              disabled={claim.isPending}
              placeholder={t('sharingClaimProfileParentLabelHint')}
              onChange={(event) => setParentLabel(event.target.value)}
            />
          </div>
          {failure !== null ? (
            <p className="error">{t(transferFailureMessageId(failure))}</p>
          ) : null}
          <div className="actions">
            <button
              type="button"
              className="button secondary"
              disabled={claim.isPending}
              onClick={() => navigate('/')}
            >
              {t('sharingClaimProfileDecline')}
            </button>
            <button
              type="button"
              className="button"
              disabled={claim.isPending}
              onClick={() => claim.mutate()}
            >
              {t('claimProfileBecomeGuardianAction')}
            </button>
          </div>
        </>
      ) : null}
    </main>
  );
}
