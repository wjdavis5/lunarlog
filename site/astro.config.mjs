import { defineConfig } from 'astro/config';

// https://astro.build/config
//
// The marketing site (issue #1099). `output: 'static'` builds plain files to
// `site/dist`, which the apex Worker's static-assets layer serves.
//
// No integrations and no `client:*` directives anywhere: the site ships zero
// client-side JavaScript by default (acceptance criterion 4 — loading any page
// must make no request to an origin other than lunarlog.app).
export default defineConfig({
  site: 'https://lunarlog.app',
  output: 'static',
  build: {
    // The CSP in `site/public/_headers` is `style-src 'self'` with no
    // `'unsafe-inline'`, so Astro must never inline a stylesheet into the
    // HTML. The default ('auto') inlines anything under 4 kB; 'never' always
    // emits an external `<link rel="stylesheet">`.
    inlineStylesheets: 'never',
  },
});
