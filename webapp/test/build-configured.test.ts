import { afterEach, describe, expect, it } from 'vitest';
import type { Page } from '@playwright/test';
import { buildIsConfigured } from '../e2e/fixtures';

describe('buildIsConfigured (issue #1662)', () => {
  const origEnv = process.env.LUNARLOG_APP_CONFIGURED;

  afterEach(() => {
    if (origEnv !== undefined) {
      process.env.LUNARLOG_APP_CONFIGURED = origEnv;
    } else {
      delete process.env.LUNARLOG_APP_CONFIGURED;
    }
  });

  it('returns true without probing when LUNARLOG_APP_CONFIGURED is true', async () => {
    process.env.LUNARLOG_APP_CONFIGURED = 'true';
    const fakePage = null as unknown as Page;
    expect(await buildIsConfigured(fakePage)).toBe(true);
  });

  it('returns false without probing when LUNARLOG_APP_CONFIGURED is false', async () => {
    process.env.LUNARLOG_APP_CONFIGURED = 'false';
    const fakePage = null as unknown as Page;
    expect(await buildIsConfigured(fakePage)).toBe(false);
  });
});
