import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { cleanup, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';

import type { Prediction } from '../src/domain/schemas';
import { AppIntlProvider } from '../src/i18n/i18n';
import messages from '../src/i18n/messages.en.json';
import { ProfileHomeStatus } from '../src/pages/ProfileHomeStatus';

/**
 * The estimate card is the first thing on a profile's home, in every state.
 * Two things are pinned here. The profile's name is the page's one
 * top-level heading: the home had none, so a screen reader's "jump to the
 * main heading" went nowhere. And the line the card exists to show, the
 * cycle day or the reason there is none, is set in the display face, where
 * it used to be the same size and weight as everything around it.
 */

const active: Prediction = {
  kind: 'active',
  today: '2026-10-03',
  lastEpisodeStart: '2026-09-28',
  estimatedNextStart: '2026-10-14',
  originalEstimatedNextStart: '2026-10-14',
  averagedCycleLengths: [28],
  meanCycleLengthDays: 28,
  cycleDay: 6,
  duringEpisode: false,
  completedCycleCount: 6,
  validCycleCount: 6,
  meanPeriodLengthDays: 5,
  spreadDays: 1,
  validRatio: 1,
  tier: 'high',
  basis: 'statistical',
  unusuallyLongCycle: false,
  staleHistory: false,
  daysLate: null,
  daysUntilNextPeriod: 11,
  forecast: [],
  pms: null,
};

const states: [string, Prediction][] = [
  ['an estimate', active],
  [
    'too little history',
    {
      kind: 'notEnoughHistory',
      episodeCount: 1,
      completedCycleCount: 1,
      validCycleCount: 1,
      usableCycleCount: 1,
    },
  ],
  ['estimates paused', { kind: 'suppressed', method: null, lifecycleMode: 'pregnancy' }],
  ['estimates off', { kind: 'disabled' }],
];

function renderStatus(prediction: Prediction) {
  return render(
    <AppIntlProvider>
      <ProfileHomeStatus
        prediction={prediction}
        profileMode="standard"
        storedIrregularFraming={null}
        todayIso="2026-10-03"
        displayName="Maya"
      />
    </AppIntlProvider>,
  );
}

describe('ProfileHomeStatus', () => {
  afterEach(cleanup);

  it.each(states)('with %s, the profile name is the one top-level heading', (_label, state) => {
    renderStatus(state);
    const headings = screen.getAllByRole('heading', { level: 1 });
    expect(headings).toHaveLength(1);
    expect(headings[0]).toHaveTextContent('Maya');
    // The card is still named by it.
    expect(screen.getByRole('region', { name: 'Maya' })).toBeInTheDocument();
  });

  it('shows the cycle day on the emphasised line', () => {
    renderStatus(active);
    const line = screen.getByText('Cycle day 6');
    expect(line).toHaveClass('home-phase');
  });

  it('shows the period day there instead during a period', () => {
    renderStatus({ ...active, duringEpisode: true, cycleDay: 2 });
    expect(screen.getByText(/^Period, day \d+$/)).toHaveClass('home-phase');
  });

  it.each([
    ['estimates paused', states[2]?.[1], messages['predictionsSuppressedTitle']],
    ['estimates off', states[3]?.[1], messages['predictionsDisabledTitle']],
    ['too little history', states[1]?.[1], messages['webHomeNotEnoughTitle']],
  ])('with %s, the reason takes the emphasised line', (_label, state, title) => {
    renderStatus(state as Prediction);
    expect(screen.getByText(title ?? 'missing')).toHaveClass('home-state-title');
  });
});

describe('the estimate card type', () => {
  const css = readFileSync(
    join(import.meta.dirname, '..', 'src', 'styles', 'global.css'),
    'utf8',
  ).replaceAll('\r\n', '\n');

  function ruleBody(selector: string): string {
    const bodies: string[] = [];
    for (const match of css.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
      const found = (match[1] ?? '').replace(/\/\*[\s\S]*?\*\//g, '').trim();
      if (found === selector) bodies.push(match[2] ?? '');
    }
    expect(bodies, `one rule for ${selector}`).toHaveLength(1);
    return bodies[0] ?? '';
  }

  it.each([
    ['.home-phase', 'headline-medium'],
    ['.home-state-title', 'headline-small'],
  ])('%s is set in the display face at %s', (selector, step) => {
    const body = ruleBody(selector);
    expect(body).toContain('font-family: var(--ll-font-display);');
    expect(body).toContain(`font-size: var(--ll-type-${step}-font-size);`);
    expect(body).toContain(`line-height: var(--ll-type-${step}-line-height);`);
  });

  it('the name above it stays a quiet title, though it is the h1', () => {
    // The browser's own h1 size must not come through: the class sets it.
    expect(ruleBody('.card-title')).toContain(
      'font-size: var(--ll-type-title-medium-font-size);',
    );
  });
});
