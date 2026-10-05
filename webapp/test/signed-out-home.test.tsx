import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { cleanup, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { afterEach, describe, expect, it } from 'vitest';

import { AppIntlProvider } from '../src/i18n/i18n';
import messages from '../src/i18n/messages.en.json';
import { SignedOutHome } from '../src/pages/SignedOutHome';

const webappRoot = join(import.meta.dirname, '..');

function renderWelcome() {
  return render(
    <AppIntlProvider>
      <MemoryRouter>
        <SignedOutHome />
      </MemoryRouter>
    </AppIntlProvider>,
  );
}

describe('SignedOutHome — what a signed-out visitor sees', () => {
  afterEach(cleanup);

  it('names the product and says what signing in is for', () => {
    renderWelcome();
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent(
      messages['webWelcomeTitle'],
    );
    expect(screen.getByText(messages['webHomeNeedsSignIn'])).toBeInTheDocument();
  });

  it('offers both ways in: sign in, or create an account', () => {
    renderWelcome();
    expect(
      screen.getByRole('link', { name: messages['accountSectionSignIn'] }),
    ).toHaveAttribute('href', '/sign-in');
    expect(
      screen.getByRole('link', { name: messages['accountSignInToggleCreateInstead'] }),
    ).toHaveAttribute('href', '/sign-up');
  });

  it('states what this browser keeps', () => {
    renderWelcome();
    expect(screen.getByText(messages['webWelcomeStorageNote'])).toBeInTheDocument();
  });

  // The note is a promise about storage. It is pinned to PRIVACY.md's
  // browser bullet by test/site/privacy_browser_error_reporting_test.dart,
  // which already runs whenever the policy or the catalogue changes.

  it('keeps the product name lowercase, sentence-initial included', () => {
    expect(messages['webWelcomeTitle'].startsWith('lunarlog')).toBe(true);
  });
});

describe('the brand images the page links', () => {
  const html = readFileSync(join(webappRoot, 'index.html'), 'utf8');

  // PNG signature: the file is a real image, not a placeholder or a
  // truncated copy.
  const pngSignature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

  it.each(['favicon.png', 'apple-touch-icon.png', 'brand-mark.png'])(
    '%s ships in public/ as a PNG',
    (name) => {
      const file = readFileSync(join(webappRoot, 'public', name));
      expect(file.subarray(0, 8).equals(pngSignature)).toBe(true);
    },
  );

  it('draws the header mark from the same origin', () => {
    const css = readFileSync(join(webappRoot, 'src', 'styles', 'global.css'), 'utf8');
    expect(css).toContain("url('/brand-mark.png')");
  });

  it('links the icons from the same origin (img-src is self only)', () => {
    expect(html).toContain('<link rel="icon" href="/favicon.png" type="image/png" />');
    expect(html).toContain('<link rel="apple-touch-icon" href="/apple-touch-icon.png" />');
  });
});
