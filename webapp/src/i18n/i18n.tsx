import type { ReactNode } from 'react';
import { IntlProvider } from 'react-intl';

import messages from './messages.en.json';

/**
 * The catalogue is generated from `lib/l10n/app_en.arb` by
 * scripts/generate.mjs at build time; the app is English-only today, exactly
 * like the Flutter app's single arb. `useT` (./t) is the only way a
 * component reads it.
 */
export function AppIntlProvider({ children }: { children: ReactNode }) {
  return (
    <IntlProvider defaultLocale="en" locale="en" messages={messages}>
      {children}
    </IntlProvider>
  );
}
