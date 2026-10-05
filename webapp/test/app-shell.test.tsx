import { QueryClientProvider } from '@tanstack/react-query';
import { cleanup, render, screen, within } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { AppIntlProvider } from '../src/i18n/i18n';
import messages from '../src/i18n/messages.en.json';
import { createAppQueryClient } from '../src/lib/queries';

/**
 * The app header. "Today" names the signed-in home; signed out, `/` is the
 * welcome page, so the header must not offer a "Today" link that leads
 * there. The product name is the way home in both states.
 *
 * The session hook is replaced at the module boundary and the home page is
 * a stub: these tests are about the shell, not about what it routes to.
 */

vi.mock('../src/lib/authQueries', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../src/lib/authQueries')>();
  return {
    ...actual,
    useAuthSession: vi.fn(),
    useResetWebDataOnIdentityChange: vi.fn(),
  };
});

vi.mock('../src/pages/TodayPage', () => ({
  TodayPage: () => <main data-testid="home-stub" />,
}));

import { App } from '../src/App';
import { useAuthSession } from '../src/lib/authQueries';

type Session = ReturnType<typeof useAuthSession>;

function renderApp(signedIn: boolean) {
  vi.mocked(useAuthSession).mockReturnValue({
    data: { signedIn, email: signedIn ? 'a@b.co' : null, userId: signedIn ? 'u1' : null },
  } as Session);
  window.history.replaceState(null, '', '/');
  return render(
    <AppIntlProvider>
      <QueryClientProvider client={createAppQueryClient()}>
        <App />
      </QueryClientProvider>
    </AppIntlProvider>,
  );
}

describe('the app header', () => {
  afterEach(cleanup);

  it('makes the product name the way home', () => {
    renderApp(false);
    const header = within(screen.getByRole('banner'));
    expect(
      header.getByRole('link', { name: messages['gateLockScreenAppTitle'] }),
    ).toHaveAttribute('href', '/');
  });

  it('offers no "Today" link while signed out, only the way in', () => {
    renderApp(false);
    const header = within(screen.getByRole('banner'));
    expect(header.queryByRole('link', { name: messages['calendarTodayTooltip'] })).toBeNull();
    expect(
      header.getByRole('link', { name: messages['accountSectionSignIn'] }),
    ).toHaveAttribute('href', '/sign-in');
  });

  it('offers "Today" and the account page once signed in', () => {
    renderApp(true);
    const header = within(screen.getByRole('banner'));
    expect(
      header.getByRole('link', { name: messages['calendarTodayTooltip'] }),
    ).toHaveAttribute('href', '/');
    expect(header.getByRole('link', { name: messages['accountSectionTitle'] })).toHaveAttribute(
      'href',
      '/account',
    );
  });
});
