import { defineConfig, devices } from '@playwright/test';

// Playwright runs against `vite preview`, which serves the build with the
// staging Worker's exact security headers (worker/headers.ts — see
// vite.config.ts's `preview.headers`), so the CSP/Trusted-Types assertions
// below are enforced by real Chromium, not assumed.
export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  timeout: 30_000,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? 'list' : 'list',
  use: {
    baseURL: 'http://127.0.0.1:4173',
    trace: 'retain-on-failure',
  },
  webServer: {
    // --host pins the loopback stack: vite otherwise binds whichever of
    // 127.0.0.1/::1 "localhost" resolves to first, and a [::1]-only server
    // is invisible to the IPv4 health check below.
    command: 'npm run preview -- --host 127.0.0.1 --port 4173 --strictPort',
    url: 'http://127.0.0.1:4173',
    reuseExistingServer: !process.env.CI,
    timeout: 60_000,
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
});
