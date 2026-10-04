import { Link, Navigate, Outlet, RouterProvider, createBrowserRouter } from 'react-router';

import { useT } from './i18n/t';
import { useAuthSession, useResetWebDataOnIdentityChange } from './lib/authQueries';
import { AccountPage } from './pages/AccountPage';
import { AuthCallbackPage } from './pages/AuthCallbackPage';
import { CodeEntryPage } from './pages/CodeEntryPage';
import { ForgotPasswordPage } from './pages/ForgotPasswordPage';
import { ResetPasswordPage } from './pages/ResetPasswordPage';
import { SignInPage } from './pages/SignInPage';
import { SignUpPage } from './pages/SignUpPage';
import { DayPage } from './pages/DayPage';
import { InvitePage } from './pages/InvitePage';
import { ManageGuardiansPage } from './pages/ManageGuardiansPage';
import { ProfileNotesPage } from './pages/ProfileNotesPage';
import { ProfilesPage } from './pages/ProfilesPage';
import { TodayPage } from './pages/TodayPage';

/**
 * The app shell: header + routed content. The auth screens (#1250) live
 * outside /auth/* so the Worker's API routes and the SPA's pages can never
 * shadow each other; /auth/callback itself is the SPA page the provider
 * and the emailed links land on, and the Worker only answers its POST
 * (the exchange), never the GET.
 */
function Shell() {
  const t = useT();
  // Issue #1281: when the page's session resolves to a different account,
  // the synced-data cache goes with the old one — before anything renders.
  useResetWebDataOnIdentityChange();
  const session = useAuthSession();
  return (
    <div className="app-shell">
      <header className="app-header">
        <span className="brand">{t('gateLockScreenAppTitle')}</span>
        <nav>
          <Link className="nav-link" to="/">
            {t('calendarTodayTooltip')}
          </Link>
          {/* Issue #1256: the account and "Your data" settings. */}
          {session.data?.signedIn === true ? (
            <Link className="nav-link" to="/account">
              {t('accountSectionTitle')}
            </Link>
          ) : null}
          <Link className="nav-link" to="/sign-in">
            {session.data?.signedIn === true
              ? t('accountSectionSignedIn')
              : t('accountSectionSignIn')}
          </Link>
        </nav>
      </header>
      <Outlet />
    </div>
  );
}

// One router per module load. `/invite` is the redemption entry the app's
// universal links and the site's invite page both point at (issue #1255),
// and `/auth/callback` is where #1250's OAuth/emailed-link ceremonies land;
// the Worker-reserved `/auth/*` beyond it goes home. Any other path goes
// home too — a not-found screen waits for catalogue copy of its own (the
// no-typed-copy lint bans typing one here).
const router = createBrowserRouter([
  {
    path: '/',
    element: <Shell />,
    children: [
      { index: true, element: <TodayPage /> },
      { path: 'sign-in', element: <SignInPage /> },
      { path: 'sign-up', element: <SignUpPage /> },
      { path: 'sign-in/code', element: <CodeEntryPage /> },
      { path: 'forgot-password', element: <ForgotPasswordPage /> },
      { path: 'reset-password', element: <ResetPasswordPage /> },
      // Issue #1256: the account and "Your data" settings — and the path
      // Apple's delete ceremony redirects back to (the Worker's
      // /auth/apple/delete/start names this page as its return URL).
      { path: 'account', element: <AccountPage /> },
      { path: 'auth/callback', element: <AuthCallbackPage /> },
      // Issue #1254: the day editor, one profile at a time; the day itself
      // is the `date` query parameter (defaults to the browser's today).
      { path: 'day/:profileId', element: <DayPage /> },
      // Issue #1253: the profiles management page (list / create / edit /
      // archive / delete) and the home's `?profile=` switcher.
      { path: 'profiles', element: <ProfilesPage /> },
      { path: 'invite', element: <InvitePage /> },
      { path: 'profile/:profileId/guardians', element: <ManageGuardiansPage /> },
      { path: 'profile/:profileId/notes', element: <ProfileNotesPage /> },
      { path: 'auth/*', element: <Navigate replace to="/" /> },
      { path: '*', element: <Navigate replace to="/" /> },
    ],
  },
]);

export function App() {
  return <RouterProvider router={router} />;
}
