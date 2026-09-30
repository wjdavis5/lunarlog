import { Link, Navigate, Outlet, RouterProvider, createBrowserRouter } from 'react-router';

import { useT } from './i18n/t';
import { AuthCallbackPage } from './pages/AuthCallbackPage';
import { DayPage } from './pages/DayPage';
import { InvitePage } from './pages/InvitePage';
import { ManageGuardiansPage } from './pages/ManageGuardiansPage';
import { ProfileNotesPage } from './pages/ProfileNotesPage';
import { TodayPage } from './pages/TodayPage';

/**
 * The app shell: header + routed content. `auth/*` is the route the staging
 * Worker reserves for the auth-callback flow (#1250); today it renders a
 * placeholder so a deep link lands in the app, never a 404.
 */
function Shell() {
  const t = useT();
  return (
    <div className="app-shell">
      <header className="app-header">
        <span className="brand">{t('gateLockScreenAppTitle')}</span>
        <nav>
          <Link className="nav-link" to="/">
            {t('calendarTodayTooltip')}
          </Link>
        </nav>
      </header>
      <Outlet />
    </div>
  );
}

// One router per module load. `/invite` is the redemption entry the app's
// universal links and the site's invite page both point at (issue #1255);
// `/auth/*` stays the Worker-reserved entry for #1250's ceremony. Any other
// path goes home.
const router = createBrowserRouter([
  {
    path: '/',
    element: <Shell />,
    children: [
      { index: true, element: <TodayPage /> },
      // Issue #1254: the day editor, one profile at a time; the day itself
      // is the `date` query parameter (defaults to the browser's today).
      { path: 'day/:profileId', element: <DayPage /> },
      { path: 'invite', element: <InvitePage /> },
      { path: 'profile/:profileId/guardians', element: <ManageGuardiansPage /> },
      { path: 'profile/:profileId/notes', element: <ProfileNotesPage /> },
      { path: 'auth/*', element: <AuthCallbackPage /> },
      { path: '*', element: <Navigate replace to="/" /> },
    ],
  },
]);

export function App() {
  return <RouterProvider router={router} />;
}
