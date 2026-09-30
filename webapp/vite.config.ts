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
    setupFiles: ['./test/setup.ts'],
    include: ['test/**/*.test.{ts,tsx}'],
  },
});
