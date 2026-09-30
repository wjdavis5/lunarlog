import { Link, Navigate, Outlet, RouterProvider, createBrowserRouter } from 'react-router';

import { useT } from './i18n/t';
import { AuthCallbackPage } from './pages/AuthCallbackPage';
import { DayPage } from './pages/DayPage';
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

// One router per module load; the scaffold has exactly one real route, so
// any other path goes home. A not-found screen waits for catalogue copy of
// its own — the no-typed-copy lint bans typing one here.
const router = createBrowserRouter([
  {
    path: '/',
    element: <Shell />,
    children: [
      { index: true, element: <TodayPage /> },
      // Issue #1254: the day editor, one profile at a time; the day itself
      // is the `date` query parameter (defaults to the browser's today).
      { path: 'day/:profileId', element: <DayPage /> },
      { path: 'auth/*', element: <AuthCallbackPage /> },
      { path: '*', element: <Navigate replace to="/" /> },
    ],
  },
]);

export function App() {
  return <RouterProvider router={router} />;
}
