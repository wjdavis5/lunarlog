import { Link, useSearchParams } from 'react-router';
import { useEffect, useRef, useState, type FormEvent } from 'react';

import { useT } from '../i18n/t';
import type { MessageId } from '../i18n/message-ids';
import {
  AuthError,
  DeletionError,
  webAuth,
  type OAuthProvider,
  type WebIdentities,
} from '../lib/auth';
import {
  authCopyFor,
  deletionCopyFor,
  kMinPasswordLength,
  type AuthCopy,
} from '../lib/authCopy';
import {
  useAuthSession,
  useDeleteAccount,
  useIdentities,
  useLinkIdentity,
  useSignOut,
  useUnlinkIdentity,
  useUpdatePassword,
  startAppleDelete,
} from '../lib/authQueries';
import { downloadAccountExport } from '../lib/export';
import { getSupabaseClient } from '../lib/supabase';

/**
 * The account page (issue #1256): the app's account and "Your data" settings
 * that make sense in a browser, over the same /auth/* Worker routes the auth
 * screens use —
 *
 *   - the linked sign-in methods (link and unlink Google and Apple; the
 *     email identity renders with no remove affordance because it is the
 *     account's only recovery path, exactly like the app);
 *   - change password, sign out, and sign out everywhere (the Worker's
 *     password-update and sign-out routes, shared with the sign-in page's
 *     signed-in state);
 *   - delete account through the delete-account Edge Function. An
 *     Apple-linked account needs a fresh authorization code, and on the web
 *     that code only comes from a direct Sign in with Apple ceremony under
 *     the Services ID: the first deletion call fails closed with
 *     `apple_code_required` (nothing touched — the server's own contract),
 *     the page then navigates out to Apple, and the redirect back to
 *     /account?code=…&state=… completes the ceremony and the deletion with
 *     the fresh code;
 *   - the JSON export: `export_account_data()` shaped by the domain module
 *     into the app's export file format and downloaded from an in-memory
 *     Blob (lib/export.ts).
 */

/** The catalogue id of each provider's row label. */
function providerLabelId(provider: string): MessageId | null {
  switch (provider) {
    case 'email':
      return 'accountProviderLabelEmail';
    case 'google':
      return 'accountProviderLabelGoogle';
    case 'apple':
      return 'accountProviderLabelApple';
    default:
      return null;
  }
}

const LINKABLE_PROVIDERS: OAuthProvider[] = ['google', 'apple'];

export function AccountPage() {
  const t = useT();
  const session = useAuthSession();
  const signedIn = session.data?.signedIn === true;
  const identities = useIdentities(signedIn);
  const link = useLinkIdentity();
  const unlink = useUnlinkIdentity();
  const signOut = useSignOut();
  const update = useUpdatePassword();
  const deleteAccount = useDeleteAccount();

  // The remove confirmations inline into their row (the Manage-guardians
  // page's pattern): one at a time, named by provider.
  const [confirmingRemove, setConfirmingRemove] = useState<OAuthProvider | null>(null);
  // The delete dialog's own inline confirmation.
  const [confirmingDelete, setConfirmingDelete] = useState(false);
  // Set once the server answered `apple_code_required`: the deletion never
  // began, and the Continue button starts the Apple ceremony.
  const [awaitingAppleCeremony, setAwaitingAppleCeremony] = useState(false);

  // The export is a moment of user-visible work (the RPC plus the download);
  // its failure is the catalogue's export-failure copy.
  const [exporting, setExporting] = useState(false);
  const [exportFailed, setExportFailed] = useState(false);

  // Mapped copy for every failure the page can show (computed in the body,
  // where the mutations' errors are narrowed once).
  const linkCopy = link.error instanceof AuthError ? authCopyFor(link.error) : null;
  const unlinkCopy = unlink.error instanceof AuthError ? authCopyFor(unlink.error) : null;
  const updateCopy = update.error instanceof AuthError ? authCopyFor(update.error) : null;
  const signOutCopy =
    signOut.error !== null && signOut.error instanceof AuthError
      ? authCopyFor(signOut.error)
      : null;
  const deletionError =
    deleteAccount.error instanceof DeletionError ? deleteAccount.error : null;
  const deletionCopy =
    deletionError !== null && !awaitingAppleCeremony ? deletionCopyFor(deletionError) : null;

  // The Apple ceremony's landing: Apple redirects back here with
  // ?code=&state=. The session restores from the refresh cookie on the way
  // (the redirect killed the page), so the completion waits for it.
  const [searchParameters, setSearchParameters] = useSearchParams();
  const appleCode = searchParameters.get('code');
  const appleState = searchParameters.get('state');
  const ceremonyStartedRef = useRef(false);
  const [ceremonyError, setCeremonyError] = useState<AuthCopy | null>(null);

  useEffect(() => {
    if (appleCode === null || appleState === null) return;
    if (ceremonyStartedRef.current) return; // StrictMode/loop guard: one completion per landing.
    if (!signedIn) return; // The session is still restoring from the cookie.
    ceremonyStartedRef.current = true;
    webAuth
      .completeAppleDelete(appleCode, appleState)
      .then(() => {
        // The state check consumed, the code is fresh: delete with it. The
        // mutation's own success handler drops the dead session.
        deleteAccount.mutate({ appleCode, appleCodeClient: 'web' });
      })
      .catch((error: unknown) => {
        setCeremonyError(
          error instanceof AuthError ? authCopyFor(error) : { id: 'commonSomethingWentWrong' },
        );
      })
      .finally(() => {
        // The code and state leave the URL either way — they are one-time
        // material, not something a refresh should re-offer.
        setSearchParameters({}, { replace: true });
      });
  }, [appleCode, appleState, signedIn, deleteAccount, setSearchParameters]);

  const startDeletion = () => {
    setConfirmingDelete(false);
    // Ask the server first (the app's #664 shape): an Apple-linked account
    // fails closed with apple_code_required before anything is touched, and
    // that failure is this page's cue to run the ceremony.
    deleteAccount.mutate(
      { appleCode: null, appleCodeClient: 'web' },
      {
        onError: (error) => {
          setAwaitingAppleCeremony(
            error instanceof DeletionError && error.code === 'apple_code_required',
          );
        },
      },
    );
  };

  const runExport = () => {
    const client = getSupabaseClient();
    if (client === null) {
      setExportFailed(true);
      return;
    }
    setExporting(true);
    setExportFailed(false);
    downloadAccountExport(client)
      .catch(() => setExportFailed(true))
      .finally(() => setExporting(false));
  };

  return (
    <main className="page">
      <h1 className="display">{t('accountSectionTitle')}</h1>
      {signedIn ? (
        <>
          <p className="body">
            {t('accountSectionSignedInAs', { email: session.data?.email ?? '' })}
          </p>
          <SignInMethodsCard
            identities={identities.data ?? null}
            linkPending={link.isPending}
            unlinkPending={unlink.isPending}
            confirmingRemove={confirmingRemove}
            onConfirmRemove={setConfirmingRemove}
            onCancelRemove={() => setConfirmingRemove(null)}
            onUnlink={(provider) =>
              unlink.mutate(provider, { onSettled: () => setConfirmingRemove(null) })
            }
            onLink={(provider) => {
              link.mutate(provider, {
                onSuccess: (url) => window.location.assign(url),
              });
            }}
          />
          {identities.isError ? (
            <p className="auth-error">{t('commonSomethingWentWrong')}</p>
          ) : null}
          {linkCopy !== null ? (
            <p className="auth-error">{t(linkCopy.id, linkCopy.values)}</p>
          ) : null}
          {unlinkCopy !== null ? (
            <p className="auth-error">{t(unlinkCopy.id, unlinkCopy.values)}</p>
          ) : null}
          <ChangePasswordCard
            updatePending={update.isPending}
            onSave={(password, onSaved) => update.mutate(password, { onSuccess: onSaved })}
          />
          {updateCopy !== null ? (
            <p className="auth-error">{t(updateCopy.id, updateCopy.values)}</p>
          ) : null}
          <section className="card">
            <h2 className="card-title">{t('accountSectionSignOut')}</h2>
            <div className="card-body">
              <div className="auth-actions">
                <button
                  type="button"
                  className="button secondary"
                  disabled={signOut.isPending}
                  onClick={() => signOut.mutate('local')}
                >
                  {t('accountSectionSignOut')}
                </button>
                <button
                  type="button"
                  className="button secondary"
                  disabled={signOut.isPending}
                  onClick={() => signOut.mutate('global')}
                >
                  {t('accountSectionSignOutEverywhere')}
                </button>
              </div>
              {signOutCopy !== null ? (
                <p className="auth-error">{t(signOutCopy.id, signOutCopy.values)}</p>
              ) : null}
            </div>
          </section>
          <ExportCard exporting={exporting} failed={exportFailed} onExport={runExport} />
          <DeleteAccountCard
            confirming={confirmingDelete}
            onConfirm={() => setConfirmingDelete(true)}
            onCancel={() => setConfirmingDelete(false)}
            onDelete={startDeletion}
            deleting={deleteAccount.isPending}
            awaitingAppleCeremony={awaitingAppleCeremony}
            onAppleCeremony={() => startAppleDelete()}
          />
          {deletionCopy !== null ? (
            <p className="auth-error">{t(deletionCopy.id, deletionCopy.values)}</p>
          ) : null}
          {ceremonyError !== null ? (
            <p className="auth-error">{t(ceremonyError.id, ceremonyError.values)}</p>
          ) : null}
        </>
      ) : (
        <div className="auth-info">
          <p className="body">{t('accountSectionSignIn')}</p>
          <div className="auth-links">
            <Link to="/sign-in">{t('accountSignInTitle')}</Link>
          </div>
        </div>
      )}
    </main>
  );
}

/** The linked sign-in methods: one row per known provider, the email row
 * permanently without a remove affordance. */
function SignInMethodsCard(props: {
  identities: WebIdentities | null;
  linkPending: boolean;
  unlinkPending: boolean;
  confirmingRemove: OAuthProvider | null;
  onConfirmRemove: (provider: OAuthProvider) => void;
  onCancelRemove: () => void;
  onUnlink: (provider: OAuthProvider) => void;
  onLink: (provider: OAuthProvider) => void;
}) {
  const t = useT();
  const providers = props.identities?.providers ?? [];
  // Every known provider gets a row; linked ones carry their remove
  // affordance, unlinked ones the add button.
  const known: Array<'email' | OAuthProvider> = ['email', ...LINKABLE_PROVIDERS];
  const labels = providers
    .map(providerLabelId)
    .filter((id): id is MessageId => id !== null)
    .map((id) => t(id));
  return (
    <section className="card">
      <h2 className="card-title">
        {t('accountSectionSignInMethods', { methods: labels.join(', ') })}
      </h2>
      <div className="card-body">
        <ul className="row-list">
          {known.map((provider) => {
            const labelId = providerLabelId(provider);
            if (labelId === null) return null;
            const label = t(labelId);
            const linkable = provider !== 'email';
            const linked = provider === 'email' || providers.includes(provider);
            return (
              <li className="row" key={provider}>
                <div className="row-main">
                  <span className="row-title">{label}</span>
                  <span className="row-sub">{t('accountSectionLinkSubtitle')}</span>
                </div>
                {linked && linkable ? (
                  props.confirmingRemove === provider ? (
                    <>
                      <button
                        type="button"
                        className="button danger"
                        disabled={props.unlinkPending}
                        onClick={() => props.onUnlink(provider)}
                      >
                        {t('accountSectionRemove')}
                      </button>
                      <button
                        type="button"
                        className="button secondary"
                        disabled={props.unlinkPending}
                        onClick={props.onCancelRemove}
                      >
                        {t('accountSectionCancel')}
                      </button>
                    </>
                  ) : (
                    <button
                      type="button"
                      className="button secondary"
                      disabled={props.linkPending || props.unlinkPending}
                      onClick={() => props.onConfirmRemove(provider)}
                    >
                      {t('accountSectionRemoveProvider', { provider: label })}
                    </button>
                  )
                ) : null}
                {!linked && linkable ? (
                  <button
                    type="button"
                    className="button secondary"
                    disabled={props.linkPending || props.unlinkPending}
                    onClick={() => props.onLink(provider)}
                  >
                    {provider === 'apple'
                      ? t('accountSectionAddApple')
                      : t('accountSectionAddGoogle')}
                  </button>
                ) : null}
              </li>
            );
          })}
        </ul>
        {props.confirmingRemove !== null ? (
          <p className="row-sub">
            {t('accountSectionRemoveTitle', {
              provider: t(
                providerLabelId(props.confirmingRemove) ?? 'accountProviderLabelEmail',
              ),
            })}{' '}
            {t('accountSectionRemoveBody', {
              provider: t(
                providerLabelId(props.confirmingRemove) ?? 'accountProviderLabelEmail',
              ),
            })}
          </p>
        ) : null}
      </div>
    </section>
  );
}

/** The change-password form: the recovery screen's field set, aimed at the
 * signed-in account instead of a recovery session. */
function ChangePasswordCard(props: {
  updatePending: boolean;
  onSave: (password: string, onSaved: () => void) => void;
}) {
  const t = useT();
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [formError, setFormError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  const submit = (event: FormEvent) => {
    event.preventDefault();
    if (password.length < kMinPasswordLength) {
      setFormError(t('accountPasswordRecoveryLengthError', { length: kMinPasswordLength }));
      return;
    }
    if (password !== confirm) {
      setFormError(t('accountPasswordRecoveryMismatchError'));
      return;
    }
    setFormError(null);
    props.onSave(password, () => setSaved(true));
  };

  return (
    <section className="card">
      <h2 className="card-title">{t('accountPasswordRecoveryTitle')}</h2>
      <div className="card-body">
        <form
          className="auth-form"
          onSubmit={submit}
          noValidate
          onChange={() => setSaved(false)}
        >
          <div className="auth-field">
            <label htmlFor="account-new-password">{t('accountPasswordRecoveryNewLabel')}</label>
            <input
              id="account-new-password"
              type="password"
              autoComplete="new-password"
              aria-describedby="account-new-password-hint"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
            />
            <p className="auth-hint" id="account-new-password-hint">
              {t('accountPasswordRecoveryLengthHelper', { length: kMinPasswordLength })}
            </p>
          </div>
          <div className="auth-field">
            <label htmlFor="account-confirm-password">
              {t('accountPasswordRecoveryConfirmLabel')}
            </label>
            <input
              id="account-confirm-password"
              type="password"
              autoComplete="new-password"
              value={confirm}
              onChange={(event) => setConfirm(event.target.value)}
            />
          </div>
          <div className="auth-actions">
            <button
              type="submit"
              className="button secondary"
              disabled={password === '' || confirm === '' || props.updatePending}
            >
              {t('accountPasswordRecoverySave')}
            </button>
          </div>
          {formError !== null ? <p className="auth-error">{formError}</p> : null}
          {saved && formError === null ? <p className="body">{t('webDaySaved')}</p> : null}
        </form>
      </div>
    </section>
  );
}

/** The JSON export: one tile, the signed-in subtitle (the web client has no
 * local store to export — the account's server data is the whole export). */
function ExportCard(props: { exporting: boolean; failed: boolean; onExport: () => void }) {
  const t = useT();
  return (
    <section className="card">
      <h2 className="card-title">{t('yourDataExportTitle')}</h2>
      <div className="card-body">
        <p className="row-sub">{t('yourDataExportSubtitleSignedIn')}</p>
        <div className="auth-actions">
          <button
            type="button"
            className="button secondary"
            disabled={props.exporting}
            onClick={props.onExport}
          >
            {t('settingsExportRangeConfirm')}
          </button>
        </div>
        {props.failed ? <p className="auth-error">{t('accountExportFailure')}</p> : null}
      </div>
    </section>
  );
}

/** The delete-account tile and its inline confirmation, plus the
 * apple_code_required turn: nothing was deleted, run the Apple ceremony. */
function DeleteAccountCard(props: {
  confirming: boolean;
  onConfirm: () => void;
  onCancel: () => void;
  onDelete: () => void;
  deleting: boolean;
  awaitingAppleCeremony: boolean;
  onAppleCeremony: () => void;
}) {
  const t = useT();
  return (
    <section className="card">
      <h2 className="card-title">{t('accountSectionDelete')}</h2>
      <div className="card-body">
        {props.awaitingAppleCeremony ? (
          <>
            <p className="row-sub">{t('accountDeletionAppleCodeRequired')}</p>
            <div className="auth-actions">
              <button type="button" className="button danger" onClick={props.onAppleCeremony}>
                {t('webAuthContinueAction')}
              </button>
            </div>
          </>
        ) : props.confirming ? (
          <>
            <p className="row-sub">{t('accountDeleteDialogBody')}</p>
            <p className="row-sub">{t('accountDeleteDialogAck')}</p>
            <div className="auth-actions">
              <button
                type="button"
                className="button danger"
                disabled={props.deleting}
                onClick={props.onDelete}
              >
                {t('accountDeleteDialogConfirm')}
              </button>
              <button
                type="button"
                className="button secondary"
                disabled={props.deleting}
                onClick={props.onCancel}
              >
                {t('accountDeleteDialogCancel')}
              </button>
            </div>
          </>
        ) : (
          <div className="auth-actions">
            <button type="button" className="button danger" onClick={props.onConfirm}>
              {t('accountSectionDelete')}
            </button>
          </div>
        )}
      </div>
    </section>
  );
}
