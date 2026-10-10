/**
 * First-run orientation (issue #1795): a signed-in account with no profiles
 * sees a short welcome once per browser session. The flag is deliberately a
 * module variable and not storage: the nothing-stored rule bans
 * sessionStorage and friends, so a reload starts a new session and shows the
 * card again.
 */

let seenThisSession = false;

export function firstRunSeen(): boolean {
  return seenThisSession;
}

export function markFirstRunSeen(): void {
  seenThisSession = true;
}

/** Test seam: module state persists across cases within one test file. */
export function resetFirstRunForTests(): void {
  seenThisSession = false;
}
