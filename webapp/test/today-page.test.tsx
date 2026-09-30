import { QueryClientProvider } from '@tanstack/react-query';
import { cleanup, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { afterEach, describe, expect, it } from 'vitest';

import { createAppQueryClient } from '../src/lib/queries';
import { AppIntlProvider } from '../src/i18n/i18n';
import messages from '../src/i18n/messages.en.json';
import { AuthCallbackPage } from '../src/pages/AuthCallbackPage';
import { TodayPage } from '../src/pages/TodayPage';

function renderWithProviders(ui: React.ReactElement, initialPath = '/') {
  const queryClient = createAppQueryClient();
  return render(
    <AppIntlProvider>
      <QueryClientProvider client={queryClient}>
        <MemoryRouter initialEntries={[initialPath]}>{ui}</MemoryRouter>
      </QueryClientProvider>
    </AppIntlProvider>,
  );
}

describe('TodayPage (issue #1249)', () => {
  // Vitest runs without globals, so Testing Library's automatic cleanup
  // never registers — without this, the second render sees two shells.
  afterEach(cleanup);

  it('renders the month header and empty state from the catalogue', () => {
    renderWithProviders(<TodayPage />);
    const month = new Intl.DateTimeFormat('en', { month: 'long' }).format(new Date());
    const year = String(new Date().getFullYear());
    const expectedHeader = messages['calendarMonthYearLabel']
      ?.replace('{month}', month)
      .replace('{year}', year);
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent(expectedHeader ?? '');
    expect(
      screen.getByText(messages['calendarNoEntriesTitle'] ?? 'missing'),
    ).toBeInTheDocument();
    expect(
      screen.getByText(messages['calendarNoEntriesBody'] ?? 'missing'),
    ).toBeInTheDocument();
  });

  it('sets the document title from the catalogue', () => {
    renderWithProviders(<TodayPage />);
    expect(document.title).toBe(messages['gateLockScreenAppTitle']);
  });
});

describe('AuthCallbackPage (issue #1249, real ceremony #1250)', () => {
  it('renders the sign-in placeholder copy from the catalogue', () => {
    renderWithProviders(<AuthCallbackPage />, '/auth/callback?code=smoke');
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent(
      messages['accountSignInTitle'] ?? 'missing',
    );
  });
});
