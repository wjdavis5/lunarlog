import { Link, Navigate, Outlet, RouterProvider, createBrowserRouter } from 'react-router';

import { useT } from './i18n/t';
import { useAuthSession } from './lib/authQueries';
import { AuthCallbackPage } from './pages/AuthCallbackPage';
import { CodeEntryPage } from './pages/CodeEntryPage';
import { ForgotPasswordPage } from './pages/ForgotPasswordPage';
import { ResetPasswordPage } from './pages/ResetPasswordPage';
import { SignInPage } from './pages/SignInPage';
import { SignUpPage } from './pages/SignUpPage';
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

// One router per module load; any unknown path goes home. A not-found
// screen waits for catalogue copy of its own — the no-typed-copy lint bans
// typing one here.
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
      { path: 'auth/*', element: <Navigate replace to="/" /> },
      { path: '*', element: <Navigate replace to="/" /> },
    ],
  },
]);

export function App() {
  return <RouterProvider router={router} />;
}
