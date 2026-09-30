import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';

// The app theme's two families, bundled locally like the Flutter app bundles
// its static instances (fonts resolve same-origin; `font-src 'self'` holds).
import '@fontsource/inter/400.css';
import '@fontsource/inter/500.css';
import '@fontsource/inter/600.css';
import '@fontsource/fraunces/600.css';
import './styles/global.css';

import { QueryClientProvider } from '@tanstack/react-query';

import { App } from './App';
import { createAppQueryClient } from './lib/queries';
import { AppIntlProvider } from './i18n/i18n';

const queryClient = createAppQueryClient();

const rootElement = document.getElementById('root');
if (rootElement === null) {
  throw new Error('#root is missing from index.html');
}

createRoot(rootElement).render(
  <StrictMode>
    <AppIntlProvider>
      <QueryClientProvider client={queryClient}>
        <App />
      </QueryClientProvider>
    </AppIntlProvider>
  </StrictMode>,
);
