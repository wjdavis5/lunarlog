import { Link, Navigate, Outlet, RouterProvider, createBrowserRouter } from 'react-router';

import { useT } from './i18n/t';
import { useAuthSession } from './lib/authQueries';
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
  const session = useAuthSession();
  return (
    <div className="app-shell">
      <header className="app-header">
        <span className="brand">{t('gateLockScreenAppTitle')}</span>
        <nav>
          <Link className="nav-link" to="/">
            {t('calendarTodayTooltip')}
          </Link>
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
      { path: 'auth/callback', element: <AuthCallbackPage /> },
      // Issue #1254: the day editor, one profile at a time; the day itself
      // is the `date` query parameter (defaults to the browser's today).
      { path: 'day/:profileId', element: <DayPage /> },
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
