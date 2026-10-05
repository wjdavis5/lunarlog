import { useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { Link, useNavigate, useParams } from 'react-router';

import { useT, type TFunction } from '../i18n/t';
import {
  activeTransferQueryKey,
  guardiansQueryKey,
  pendingInvitesQueryKey,
  repullMembershipData,
  SYNCED_DATA_QUERY_KEY,
  useActiveTransfer,
  useCurrentUserId,
  useGuardians,
  usePendingInvites,
  useLiveProfiles,
} from '../lib/queries';
import { profileHomePath } from '../lib/profiles/profile-views';
import { subjectInviteAvailable } from '../lib/schemas';
import {
  cancelOwnershipTransfer,
  createGuardianInvitation,
  createOwnershipTransfer,
  invitePath,
  revokeGuardian,
  revokeGuardianInvitation,
  sharingFailureMessageId,
  transferFailureMessageId,
  updateGuardianRole,
  type GuardianRow,
  type InvitationOutcome,
  type PendingInviteRow,
  type SharingFailureKind,
} from '../lib/sharing';
import {
  allowedNewRoles,
  canCancelInvitation,
  canRevokeGuardian,
  guardianRoleLabelId,
  roleCanInviteCoParent,
  roleCanManageGuardians,
  roleCanTransferOwnership,
  type GuardianRole,
} from '../lib/roles';
import { getSupabaseClient } from '../lib/supabase';

/**
 * Manage-guardians on the web (issue #1255): the list / invite / role-change
 * / revoke / ownership-transfer surface, over the same SECURITY DEFINER RPCs
 * the app's `ManageGuardiansScreen` calls — the server re-authorises every
 * change, and the ladder in `roles.ts` only decides what the UI offers,
 * exactly as the app's client-side mirror does.
 *
 * Until #1250's sign-in lands there is no web session, so every RPC lands on
 * the typed not-signed-in failure and the page says so with the same copy
 * the app shows for issue #885 (`sharingFailureNotSignedIn`).
 */

type InvitePreset = 'co_parent' | 'caregiver' | 'viewer' | 'subject';

const PRESET_ROLES: Record<Exclude<InvitePreset, 'subject'>, GuardianRole> = {
  co_parent: 'co_parent',
  caregiver: 'caregiver',
  viewer: 'viewer',
};

function presetMessageId(preset: InvitePreset) {
  switch (preset) {
    case 'co_parent':
      return 'sharingInviteGuardianPresetCoParent' as const;
    case 'caregiver':
      return 'sharingInviteGuardianPresetCaregiver' as const;
    case 'viewer':
      return 'sharingInviteGuardianPresetViewer' as const;
    case 'subject':
      // The subject preset is caregiver access plus the subject marker; the
      // server enforces that pairing (issue #802).
      return 'inviteSubjectOption' as const;
  }
}

function formatDate(iso: string): string {
  return new Intl.DateTimeFormat('en', { dateStyle: 'medium' }).format(new Date(iso));
}

/** The expiry fragment of `sharingManageGuardiansPendingSubtitle` (issue #362). */
export function expiryLabel(expiresAt: string, now: Date, t: TFunction): string {
  const ms = new Date(expiresAt).getTime() - now.getTime();
  if (ms <= 0) return t('sharingManageGuardiansExpiryExpired');
  const minutes = Math.ceil(ms / 60_000);
  if (minutes <= 90) return t('sharingManageGuardiansExpiryMinutes', { minutes });
  return t('sharingManageGuardiansExpiryHours', { hours: Math.round(minutes / 60) });
}

function failureKindOf(error: unknown): SharingFailureKind {
  const kind = (error as { kind?: SharingFailureKind } | null)?.kind;
  return kind ?? 'other';
}

/** Unconfigured-build guard for mutation bodies; sections only render on a configured build. */
function requireClient(): NonNullable<ReturnType<typeof getSupabaseClient>> {
  const client = getSupabaseClient();
  if (client === null) {
    throw new Error('Supabase is not configured in this build');
  }
  return client;
}

export function ManageGuardiansPage() {
  const { profileId } = useParams();
  const t = useT();
  const client = getSupabaseClient();
  const profiles = useLiveProfiles();
  const profile = profiles.find((candidate) => candidate.id === profileId) ?? null;

  const guardians = useGuardians(profileId, profile !== null);
  const pending = usePendingInvites(profileId, profile !== null);
  const transfer = useActiveTransfer(profileId, profile !== null);
  const me = useCurrentUserId(client !== null).data ?? null;

  if (profileId === undefined || (profiles.length > 0 && profile === null)) {
    return (
      <main className="page">
        <section className="card">
          <p className="card-title">{t('sharingFailureNotFound')}</p>
        </section>
      </main>
    );
  }

  const myRole =
    guardians.data?.find((row) => row.user_id === me && row.status === 'accepted')?.role ??
    null;
  const canManage = myRole !== null && roleCanManageGuardians(myRole);
  // Leave/Remove visibility rides the revoke ladder (issue #1285): the
  // server refuses a sole accepted primary guardian's self-leave, so the
  // count that decides it is primary guardians only — counting every
  // accepted role offered Leave to a sole primary with one caregiver.
  const acceptedPrimaryGuardians =
    guardians.data?.filter(
      (row) => row.status === 'accepted' && row.role === 'primary_guardian',
    ).length ?? 0;

  return (
    <main className="page">
      <h1 className="display">
        {profile !== null
          ? t('sharingManageGuardiansScreenTitle', { profileName: profile.display_name })
          : ''}
      </h1>
      <p className="page-back">
        <Link className="nav-link" to={profileHomePath(profileId)}>
          {t('webDayBackToToday')}
        </Link>
      </p>

      <ul className="row-list">
        {(guardians.data ?? [])
          .filter((row) => row.status !== 'revoked')
          .map((row) => (
            <GuardianRowItem
              key={row.id}
              row={row}
              isMe={me !== null && row.user_id === me}
              myRole={myRole}
              currentUserId={me}
              acceptedPrimaryGuardians={acceptedPrimaryGuardians}
              profileId={profileId}
              profileName={profile?.display_name ?? ''}
            />
          ))}
      </ul>
      {guardians.data !== undefined && guardians.data.length === 0 ? (
        <section className="card">
          <p className="card-title">{t('sharingManageGuardiansNoGuardiansTitle')}</p>
          <p className="card-body">{t('sharingManageGuardiansNoGuardiansBody')}</p>
        </section>
      ) : null}
      {guardians.error instanceof Error ? (
        <p className="error">{t(sharingFailureMessageId(failureKindOf(guardians.error)))}</p>
      ) : null}

      {canManage ? (
        <PendingSection
          invites={pending.data}
          error={pending.error}
          myRole={myRole}
          currentUserId={me}
        />
      ) : null}

      {client !== null && profile !== null && roleCanTransferOwnership(myRole) ? (
        <TransferSection
          profileId={profileId}
          profileName={profile.display_name}
          live={transfer.data ?? null}
        />
      ) : null}

      {client !== null && profile !== null && canManage ? (
        <InviteSection
          profileId={profileId}
          profileName={profile.display_name}
          callerRole={myRole}
          subjectAvailable={subjectInviteAvailable(profile)}
        />
      ) : null}
    </main>
  );
}

function GuardianRowItem(props: {
  row: GuardianRow;
  isMe: boolean;
  myRole: GuardianRole | null;
  currentUserId: string | null;
  acceptedPrimaryGuardians: number;
  profileId: string;
  profileName: string;
}) {
  const t = useT();
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const [confirming, setConfirming] = useState<'remove' | 'leave' | null>(null);
  const [roleFailure, setRoleFailure] = useState(false);
  const [revokeFailure, setRevokeFailure] = useState(false);

  const roleChange = useMutation({
    mutationFn: async (newRole: GuardianRole) => {
      const client = requireClient();
      await updateGuardianRole(client, props.profileId, props.row.user_id, newRole);
    },
    onSuccess: () => {
      setRoleFailure(false);
      void queryClient.invalidateQueries({ queryKey: guardiansQueryKey(props.profileId) });
    },
    onError: () => setRoleFailure(true),
  });

  const revoke = useMutation({
    mutationFn: async () => {
      const client = requireClient();
      await revokeGuardian(client, props.profileId, props.row.user_id);
    },
    onSuccess: () => {
      if (props.isMe) {
        // Leaving: the profile leaves this account's view entirely — and
        // sync_pull simply stops returning it, with no tombstone (issue
        // #1282), so the full from-zero re-pull into a fresh snapshot is
        // what drops it; navigate once the re-pull and the shell
        // invalidation have landed.
        void repullMembershipData(queryClient).then(() => navigate('/'));
        return;
      }
      setConfirming(null);
      setRevokeFailure(false);
      void queryClient.invalidateQueries({ queryKey: guardiansQueryKey(props.profileId) });
    },
    onError: () => setRevokeFailure(true),
  });

  const roleLabel = t(guardianRoleLabelId(props.row.role));
  const roleLine = props.row.is_subject
    ? `${roleLabel} · ${t('manageGuardiansSubjectBadge')}`
    : roleLabel;
  const name = props.row.display_name ?? roleLabel;
  const options = props.isMe
    ? []
    : allowedNewRoles({ callerRole: props.myRole, target: props.row, currentUserId: null });
  const busy = roleChange.isPending || revoke.isPending;

  return (
    <li className="row">
      <div className="row-main">
        <p className="row-title">
          {name}
          {props.isMe ? ` ${t('sharingManageGuardiansYouSuffix')}` : ''}
        </p>
        <p className="row-sub">{roleLine}</p>
        {props.row.status === 'pending' ? (
          <span className="badge">{t('sharingManageGuardiansPendingBadge')}</span>
        ) : null}
        {roleFailure ? (
          <p className="error">{t('sharingManageGuardiansRoleUpdateFailed')}</p>
        ) : null}
        {revokeFailure ? (
          <p className="error">{t('sharingManageGuardiansRemoveFailed')}</p>
        ) : null}
      </div>
      <div className="actions">
        {confirming === null && options.length > 0 ? (
          <select
            aria-label={t('manageGuardiansChangeRoleTooltip')}
            disabled={busy}
            value=""
            onChange={(event) => {
              const next = event.target.value;
              if (next !== '') roleChange.mutate(next as GuardianRole);
            }}
          >
            <option value="">{t('manageGuardiansChangeRoleTooltip')}</option>
            {options.map((role) => (
              <option key={role} value={role}>
                {t(guardianRoleLabelId(role))}
              </option>
            ))}
          </select>
        ) : null}
        {confirming === null && rowCanBeRemoved(props) ? (
          <button
            type="button"
            className="button danger"
            disabled={busy}
            onClick={() => setConfirming('remove')}
          >
            {t('manageGuardiansRemoveCaregiverTooltip')}
          </button>
        ) : null}
        {confirming === null && rowCanBeLeft(props) ? (
          <button
            type="button"
            className="button danger"
            disabled={busy}
            onClick={() => setConfirming('leave')}
          >
            {t('manageGuardiansLeaveProfileTooltip')}
          </button>
        ) : null}
        {confirming === 'remove' ? (
          <>
            <p className="row-sub">
              {t('sharingManageGuardiansRemoveBody', { profileName: props.profileName })}
            </p>
            <button
              type="button"
              className="button danger"
              disabled={busy}
              onClick={() => revoke.mutate()}
            >
              {t('sharingManageGuardiansRemove')}
            </button>
            <button
              type="button"
              className="button secondary"
              disabled={busy}
              onClick={() => setConfirming(null)}
            >
              {t('sharingManageGuardiansCancel')}
            </button>
          </>
        ) : null}
        {confirming === 'leave' ? (
          <>
            <p className="row-sub">
              {t('manageGuardiansLeaveProfileDialogTitle', { profile: props.profileName })}
            </p>
            <button
              type="button"
              className="button danger"
              disabled={busy}
              onClick={() => revoke.mutate()}
            >
              {t('manageGuardiansLeaveProfileConfirm')}
            </button>
            <button
              type="button"
              className="button secondary"
              disabled={busy}
              onClick={() => setConfirming(null)}
            >
              {t('sharingManageGuardiansCancel')}
            </button>
          </>
        ) : null}
      </div>
    </li>
  );
}

/**
 * The revoke ladder for one guardian row (issue #1285) — `canRevokeGuardian`
 * decides both controls: removing someone else's row, and leaving on the
 * caller's own. A co-parent may remove caregivers and viewers only (the
 * server refuses the rest with `insufficient_privilege`), and Leave hides
 * from the sole accepted primary guardian (`object_not_in_prerequisite_state`).
 */
function revokeOptions(props: {
  row: GuardianRow;
  isMe: boolean;
  myRole: GuardianRole | null;
  currentUserId: string | null;
  acceptedPrimaryGuardians: number;
}) {
  return {
    callerRole: props.myRole,
    target: props.row,
    currentUserId: props.currentUserId,
    acceptedPrimaryGuardians: props.acceptedPrimaryGuardians,
  };
}

function rowCanBeRemoved(props: {
  row: GuardianRow;
  isMe: boolean;
  myRole: GuardianRole | null;
  currentUserId: string | null;
  acceptedPrimaryGuardians: number;
}): boolean {
  return !props.isMe && canRevokeGuardian(revokeOptions(props));
}

function rowCanBeLeft(props: {
  row: GuardianRow;
  isMe: boolean;
  myRole: GuardianRole | null;
  currentUserId: string | null;
  acceptedPrimaryGuardians: number;
}): boolean {
  return props.isMe && canRevokeGuardian(revokeOptions(props));
}

function PendingSection(props: {
  invites: PendingInviteRow[] | undefined;
  error: unknown;
  myRole: GuardianRole | null;
  currentUserId: string | null;
}) {
  const t = useT();
  return (
    <section className="card">
      <p className="card-title">{t('sharingManageGuardiansPendingTitle')}</p>
      {props.error instanceof Error ? (
        <p className="error">{t('sharingManageGuardiansPendingLoadError')}</p>
      ) : null}
      {props.invites !== undefined && props.invites.length === 0 ? (
        <p className="card-body">{t('sharingManageGuardiansNoPending')}</p>
      ) : null}
      <ul className="row-list">
        {(props.invites ?? []).map((invite) => (
          <PendingRowItem
            key={invite.id}
            invite={invite}
            myRole={props.myRole}
            currentUserId={props.currentUserId}
          />
        ))}
      </ul>
    </section>
  );
}

function PendingRowItem(props: {
  invite: PendingInviteRow;
  myRole: GuardianRole | null;
  currentUserId: string | null;
}) {
  const t = useT();
  const queryClient = useQueryClient();
  const [confirming, setConfirming] = useState(false);
  const [outcome, setOutcome] = useState<InvitationOutcome | null>(null);
  const [failed, setFailed] = useState(false);

  const cancel = useMutation({
    mutationFn: async () => {
      const client = requireClient();
      return revokeGuardianInvitation(client, props.invite.id);
    },
    onSuccess: (result) => {
      setOutcome(result);
      setConfirming(false);
      setFailed(false);
      void queryClient.invalidateQueries({
        queryKey: pendingInvitesQueryKey(props.invite.profile_id),
      });
    },
    onError: () => setFailed(true),
  });

  const roleLabel = t(guardianRoleLabelId(props.invite.role));
  const inviteLine = `${roleLabel} · ${expiryLabel(props.invite.expires_at, new Date(), t)}`;
  // Issue #1285: the cancel ladder — a co-parent may not cancel a co_parent
  // invitation they did not create (the server refuses it), so the control
  // hides rather than ending in a generic failure.
  const cancellable = canCancelInvitation({
    callerRole: props.myRole,
    inviteRole: props.invite.role,
    invitedBy: props.invite.invited_by,
    currentUserId: props.currentUserId,
  });
  const outcomeMessage = (value: InvitationOutcome) => {
    switch (value) {
      case 'revoked':
        return t('inviteCancellationRevoked');
      case 'already_revoked':
        return t('inviteCancellationAlreadyRevoked');
      case 'already_accepted':
        return t('inviteCancellationAlreadyAccepted');
      case 'expired':
        return t('inviteCancellationExpired');
    }
  };

  return (
    <li className="row">
      <div className="row-main">
        <p className="row-title">
          {props.invite.recipient_label ?? t('manageGuardiansWaitingForRedemption')}
        </p>
        <p className="row-sub">{inviteLine}</p>
        {props.invite.is_subject ? (
          <p className="row-sub">{t('manageGuardiansPendingSubjectLabel')}</p>
        ) : null}
        {outcome !== null ? <p className="row-sub">{outcomeMessage(outcome)}</p> : null}
        {failed ? (
          <p className="error">{t('sharingManageGuardiansCancelInviteFailed')}</p>
        ) : null}
      </div>
      <div className="actions">
        {!cancellable ? null : confirming ? (
          <>
            <button
              type="button"
              className="button danger"
              disabled={cancel.isPending}
              onClick={() => cancel.mutate()}
            >
              {t('sharingManageGuardiansCancelInvitation')}
            </button>
            <button
              type="button"
              className="button secondary"
              disabled={cancel.isPending}
              onClick={() => setConfirming(false)}
            >
              {t('sharingManageGuardiansKeepInvitation')}
            </button>
          </>
        ) : (
          <button
            type="button"
            className="button danger"
            disabled={cancel.isPending}
            onClick={() => setConfirming(true)}
            aria-label={t('manageGuardiansCancelInviteTooltip')}
          >
            {t('sharingManageGuardiansCancel')}
          </button>
        )}
      </div>
    </li>
  );
}

function InviteSection(props: {
  profileId: string;
  profileName: string;
  callerRole: GuardianRole | null;
  subjectAvailable: boolean;
}) {
  const t = useT();
  const queryClient = useQueryClient();
  // Issue #1285: the co_parent preset is a primary-guardian choice — the
  // server refuses a co-parent's co-parent invitation with 42501, so a
  // co-parent caller neither defaults to it nor sees it.
  const [preset, setPreset] = useState<InvitePreset>(
    roleCanInviteCoParent(props.callerRole) ? 'co_parent' : 'caregiver',
  );
  const [nickname, setNickname] = useState('');
  const [createdToken, setCreatedToken] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const [failed, setFailed] = useState(false);

  const create = useMutation({
    mutationFn: async () => {
      const client = requireClient();
      const subject = preset === 'subject';
      const role = subject ? 'caregiver' : PRESET_ROLES[preset];
      const label = nickname.trim() === '' ? null : nickname.trim();
      return createGuardianInvitation(client, {
        profileId: props.profileId,
        role,
        recipientLabel: label,
        subject,
      });
    },
    onSuccess: (result) => {
      setCreatedToken(result.rawToken);
      setCopied(false);
      setFailed(false);
      void queryClient.invalidateQueries({
        queryKey: pendingInvitesQueryKey(props.profileId),
      });
    },
    onError: () => setFailed(true),
  });

  const busy = create.isPending;
  const createdLink =
    createdToken !== null
      ? `${window.location.origin}${invitePath(createdToken, props.profileId)}`
      : '';

  return (
    <section className="card">
      {createdToken === null ? (
        <>
          <p className="card-title">
            {t('sharingInviteGuardianTitle', { profileName: props.profileName })}
          </p>
          <div className="field">
            <label htmlFor="invite-preset">{t('sharingInviteGuardianRoleLabel')}</label>
            <select
              id="invite-preset"
              value={preset}
              disabled={busy}
              onChange={(event) => setPreset(event.target.value as InvitePreset)}
            >
              {roleCanInviteCoParent(props.callerRole) ? (
                <option value="co_parent">{t(presetMessageId('co_parent'))}</option>
              ) : null}
              <option value="caregiver">{t(presetMessageId('caregiver'))}</option>
              <option value="viewer">{t(presetMessageId('viewer'))}</option>
              {props.subjectAvailable ? (
                <option value="subject">
                  {t('inviteSubjectOption', { name: props.profileName })}
                </option>
              ) : null}
            </select>
            {preset === 'subject' ? (
              <p className="row-sub">
                {t('inviteSubjectOptionDetail', { name: props.profileName })}
              </p>
            ) : null}
          </div>
          <div className="field">
            <label htmlFor="invite-nickname">{t('sharingInviteGuardianNicknameLabel')}</label>
            <input
              id="invite-nickname"
              value={nickname}
              disabled={busy}
              maxLength={80}
              placeholder={t('sharingInviteGuardianNicknameHint')}
              onChange={(event) => setNickname(event.target.value)}
            />
          </div>
          {failed ? <p className="error">{t('sharingInviteGuardianGenerateFailed')}</p> : null}
          <div className="actions">
            <button
              type="button"
              className="button"
              disabled={busy}
              onClick={() => create.mutate()}
            >
              {t('sharingInviteGuardianCreateLink')}
            </button>
          </div>
        </>
      ) : (
        <>
          <p className="card-title">{t('sharingInviteGuardianCreatedTitle')}</p>
          <p className="card-body">
            {preset === 'subject'
              ? t('inviteCreatedShareSubject', { name: props.profileName })
              : t('inviteCreatedShareGuardian', { profile: props.profileName })}
          </p>
          <p className="link-display">{createdLink}</p>
          <p className="card-body">{t('sharingInviteGuardianExpiry')}</p>
          <div className="actions">
            <button
              type="button"
              className="button"
              onClick={() => {
                void navigator.clipboard
                  ?.writeText(createdLink)
                  .then(() => setCopied(true))
                  .catch(() => setCopied(false));
              }}
            >
              {t('sharingInviteGuardianCopyLink')}
            </button>
            {copied ? <span>{t('sharingInviteGuardianCopied')}</span> : null}
            <button
              type="button"
              className="button secondary"
              onClick={() => {
                setCreatedToken(null);
                setCopied(false);
              }}
            >
              {t('sharingInviteGuardianDone')}
            </button>
          </div>
        </>
      )}
    </section>
  );
}

function TransferSection(props: {
  profileId: string;
  profileName: string;
  live: { id: string; expires_at: string } | null;
}) {
  const t = useT();
  const queryClient = useQueryClient();
  const [postRole, setPostRole] = useState<'co_parent' | 'viewer'>('co_parent');
  const [recipientLabel, setRecipientLabel] = useState('');
  const [created, setCreated] = useState<{ id: string; rawToken: string } | null>(null);
  const [copied, setCopied] = useState(false);
  const [failure, setFailure] = useState<SharingFailureKind | null>(null);
  const [cancelled, setCancelled] = useState(false);

  const refreshKeys = () => {
    void queryClient.invalidateQueries({ queryKey: activeTransferQueryKey(props.profileId) });
    void queryClient.invalidateQueries({ queryKey: guardiansQueryKey(props.profileId) });
    // Arming or cancelling a transfer changes no membership of this
    // account, so the synced dataset needs only the ordinary invalidation
    // (the profiles key this used to touch is read by no query — issue
    // #1282).
    void queryClient.invalidateQueries({ queryKey: SYNCED_DATA_QUERY_KEY });
  };

  const arm = useMutation({
    mutationFn: async () => {
      const client = requireClient();
      return createOwnershipTransfer(client, {
        profileId: props.profileId,
        parentPostTransferRole: postRole,
        recipientLabel: recipientLabel.trim() === '' ? null : recipientLabel.trim(),
      });
    },
    onSuccess: (result) => {
      setCreated({ id: result.transfer.id, rawToken: result.rawToken });
      setCopied(false);
      setFailure(null);
      setCancelled(false);
      refreshKeys();
    },
    onError: (error) => {
      setFailure(failureKindOf(error));
      // "Already armed" is not a dead end (review #2): the live transfer's
      // own card replaces the form as soon as the readback lands.
      refreshKeys();
    },
  });

  const cancelTransfer = useMutation({
    mutationFn: async (transferId: string) => {
      const client = requireClient();
      await cancelOwnershipTransfer(client, transferId);
    },
    onSuccess: () => {
      setCreated(null);
      setCancelled(true);
      setCopied(false);
      refreshKeys();
    },
    onError: () => setFailure('other'),
  });

  // An armed-but-not-yet-claimed transfer is cancellable from its creation
  // panel even before the readback lands; afterwards the readback row wins.
  const cancellableId = props.live?.id ?? created?.id ?? null;
  const createdLink =
    created !== null
      ? `${window.location.origin}${invitePath(created.rawToken, props.profileId)}&kind=claim`
      : '';
  // The pending card is for a live transfer this session never held the token
  // for (armed earlier or on another device — the server keeps only the hash).
  // When the readback lands on the transfer this session just armed, the link
  // panel stays up instead, with the Cancel action alongside: hiding it there
  // would strand the one-time token, which is unrecoverable (issue #1286).
  const foreignLive = props.live !== null && created?.id !== props.live.id ? props.live : null;

  return (
    <section className="card">
      <p className="card-title">
        {t('sharingTransferOwnershipScreenTitle', { profileName: props.profileName })}
      </p>

      {foreignLive !== null ? (
        <>
          <p className="card-title">{t('sharingTransferOwnershipPendingTitle')}</p>
          <p className="card-body">
            {t('sharingTransferOwnershipPendingBody', { profileName: props.profileName })}
          </p>
          <p className="card-body">
            {t('sharingTransferOwnershipExpires', { date: formatDate(foreignLive.expires_at) })}
          </p>
          <div className="actions">
            <button
              type="button"
              className="button danger"
              disabled={cancelTransfer.isPending}
              onClick={() => cancelTransfer.mutate(foreignLive.id)}
            >
              {t('sharingTransferOwnershipCancelPending')}
            </button>
          </div>
        </>
      ) : created !== null ? (
        <>
          <p className="card-title">{t('sharingTransferOwnershipReadyTitle')}</p>
          <p className="card-body">
            {t('sharingTransferOwnershipShareLink', { profileName: props.profileName })}
          </p>
          <p className="link-display">{createdLink}</p>
          <div className="actions">
            <button
              type="button"
              className="button"
              disabled={cancelTransfer.isPending}
              onClick={() => {
                void navigator.clipboard
                  ?.writeText(createdLink)
                  .then(() => setCopied(true))
                  .catch(() => setCopied(false));
              }}
            >
              {t('sharingTransferOwnershipCopyLink')}
            </button>
            {copied ? <span>{t('sharingTransferOwnershipLinkCopied')}</span> : null}
            {cancellableId !== null ? (
              <button
                type="button"
                className="button danger"
                disabled={cancelTransfer.isPending}
                onClick={() => cancelTransfer.mutate(cancellableId)}
              >
                {t('sharingTransferOwnershipCancelTransfer')}
              </button>
            ) : null}
          </div>
        </>
      ) : (
        <>
          <div className="field">
            <label htmlFor="transfer-role">{t('sharingTransferOwnershipRoleAfterTitle')}</label>
            <select
              id="transfer-role"
              value={postRole}
              disabled={arm.isPending}
              onChange={(event) => setPostRole(event.target.value as 'co_parent' | 'viewer')}
            >
              <option value="co_parent">{t('transferOwnershipRoleCoParent')}</option>
              <option value="viewer">{t('transferOwnershipRoleViewer')}</option>
            </select>
          </div>
          <div className="field">
            <label htmlFor="transfer-recipient">
              {t('sharingTransferOwnershipRecipientLabel')}
            </label>
            <input
              id="transfer-recipient"
              value={recipientLabel}
              disabled={arm.isPending}
              maxLength={80}
              placeholder={t('sharingTransferOwnershipRecipientHint')}
              onChange={(event) => setRecipientLabel(event.target.value)}
            />
          </div>
          {failure !== null ? (
            <p className="error">{t(transferFailureMessageId(failure))}</p>
          ) : null}
          {cancelled ? (
            <p className="card-body">{t('sharingTransferOwnershipCancelled')}</p>
          ) : null}
          <div className="actions">
            <button
              type="button"
              className="button"
              disabled={arm.isPending}
              onClick={() => arm.mutate()}
            >
              {t('sharingTransferOwnershipAction')}
            </button>
          </div>
        </>
      )}
    </section>
  );
}
