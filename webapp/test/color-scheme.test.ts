import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { parse } from 'postcss';
import { describe, expect, it } from 'vitest';

import { webappRoot } from '../scripts/generate.mjs';

// The theme follows the system, and the browser has to be told so. Until it
// was, the parts of a control the browser draws itself kept their light
// form on the dark theme: checkboxes were white boxes with a blue tick, and
// the calendar button in a date field was dark on a dark field.
describe('native controls follow the theme', () => {
  const css = parse(readFileSync(join(webappRoot, 'src', 'styles', 'global.css'), 'utf8'));

  const rootDeclaration = (prop: string): string | undefined => {
    let value: string | undefined;
    css.walkRules(':root', (rule) => {
      // Top level only: a :root inside a media query is one scheme's tokens.
      if (rule.parent?.type !== 'root') return;
      rule.walkDecls(prop, (decl) => {
        value = decl.value;
      });
    });
    return value;
  };

  it('the stylesheet declares both colour schemes on the root', () => {
    expect(rootDeclaration('color-scheme')).toBe('light dark');
  });

  it('ticked boxes take the theme colour, from a token', () => {
    expect(rootDeclaration('accent-color')).toBe('var(--ll-primary)');
  });

  it('the page says so before the stylesheet loads', () => {
    const html = readFileSync(join(webappRoot, 'index.html'), 'utf8');
    expect(html).toContain('<meta name="color-scheme" content="light dark" />');
  });
});
