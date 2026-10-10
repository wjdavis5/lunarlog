import { beforeEach, describe, expect, it } from 'vitest';

import {
  dismissRecap,
  recapDismissed,
  resetRecapDismissForTests,
} from '../src/lib/recap-dismiss';

/**
 * The recap card's session-scoped dismissal (issue #1796; per profile and
 * cycle as of issue #1819).
 */

describe('recap dismissal (issues #1796, #1819)', () => {
  beforeEach(() => {
    resetRecapDismissForTests();
  });

  it('scopes a dismissal to its profile and cycle', () => {
    expect(recapDismissed('p1', '2026-09-03')).toBe(false);

    dismissRecap('p1', '2026-09-03');

    expect(recapDismissed('p1', '2026-09-03')).toBe(true);
    // Another profile's recap is untouched, even on the same cycle start.
    expect(recapDismissed('p2', '2026-09-03')).toBe(false);
    // A later cycle of the same profile shows its own recap.
    expect(recapDismissed('p1', '2026-10-01')).toBe(false);
  });

  it('clears every profile through the test seam', () => {
    dismissRecap('p1', '2026-09-03');
    dismissRecap('p2', '2026-09-03');
    resetRecapDismissForTests();
    expect(recapDismissed('p1', '2026-09-03')).toBe(false);
    expect(recapDismissed('p2', '2026-09-03')).toBe(false);
  });
});
