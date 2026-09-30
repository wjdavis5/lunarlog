import { useT } from '../i18n/t';

/**
 * Placeholder for the auth-callback flow (#1250). The Worker reserves
 * `/auth/*` and the SPA serves this route, so a recovery or magic link
 * lands in the app instead of a 404 — the same `lunarlog://auth-callback`
 * contract the native clients honour, over https. #1250 replaces this
 * placeholder with the real ceremony.
 */
export function AuthCallbackPage() {
  const t = useT();
  return (
    <main className="page">
      <h1 className="headline">{t('accountSignInTitle')}</h1>
      <p className="body">{t('accountSignInMagicLinkInfo')}</p>
    </main>
  );
}
