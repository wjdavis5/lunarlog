/// <reference types="vitest/config" />
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

// The staging Worker's security headers (worker/headers.ts is the single
// source of truth). vite preview serves the same policy so `npm run e2e`
// exercises the real CSP — including `require-trusted-types-for 'script'`
// enforcement — in headless Chromium, not just the deployed origin.
import { SECURITY_HEADERS } from './worker/headers.ts';

export default defineConfig({
  plugins: [react()],
  build: {
    target: 'es2022',
  },
  preview: {
    headers: SECURITY_HEADERS,
  },
  test: {
    environment: 'jsdom',
    // The suite runs west of UTC (issue #1389). A civil date parsed as UTC
    // midnight and formatted in the local zone reads one day early for
    // everyone in the Americas, and a UTC runner cannot see it. Node on
    // Windows ignores TZ, so a Windows checkout runs in its own zone.
    env: { TZ: 'America/Los_Angeles' },
    setupFiles: ['./test/setup.ts'],
    include: ['test/**/*.test.{ts,tsx}'],
  },
});
