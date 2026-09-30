import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

import {
  arbPath,
  buildMessageCatalogue,
  buildMessageIdsModule,
  messagesOutPath,
  messageIdsOutPath,
  serializeMessageCatalogue,
} from '../scripts/generate.mjs';

const committedCatalogue = JSON.parse(readFileSync(messagesOutPath, 'utf8')) as Record<
  string,
  string
>;
const committedIdsModule = readFileSync(messageIdsOutPath, 'utf8');
const arb = JSON.parse(readFileSync(arbPath, 'utf8')) as Record<string, unknown>;

describe('the generated message catalogue (issue #1249)', () => {
  it('is fresh against lib/l10n/app_en.arb', () => {
    expect(committedCatalogue).toEqual(buildMessageCatalogue(arb));
    expect(committedIdsModule).toBe(buildMessageIdsModule(buildMessageCatalogue(arb)));
  });

  it('is substantial and metadata-free', () => {
    const ids = Object.keys(committedCatalogue);
    expect(ids.length).toBeGreaterThan(1000);
    for (const id of ids) {
      expect(id.startsWith('@')).toBe(false);
    }
  });

  it('keeps the ids in arb order (stable diffs)', () => {
    const arbOrder = Object.keys(arb).filter((k) => !k.startsWith('@'));
    expect(Object.keys(committedCatalogue)).toEqual(arbOrder);
  });

  it('carries the strings the shell renders', () => {
    expect(committedCatalogue['gateLockScreenAppTitle']).toBe('lunarlog');
    expect(committedCatalogue['calendarMonthYearLabel']).toBe('{month} {year}');
    expect(committedCatalogue['accountSignInMagicLinkInfo']).toContain('sign-in link or code');
  });

  it('generates the typed MessageId union', () => {
    expect(committedIdsModule).toContain('export const MESSAGE_IDS = [');
    expect(committedIdsModule).toContain('"calendarMonthYearLabel",');
    expect(committedIdsModule).toContain(
      'export type MessageId = (typeof MESSAGE_IDS)[number];',
    );
  });

  it('serialises deterministically (2-space indent, trailing newline)', () => {
    const serialised = serializeMessageCatalogue({ a: 'x' });
    expect(serialised).toBe('{\n  "a": "x"\n}\n');
  });
});
