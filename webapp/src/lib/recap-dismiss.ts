/**
 * The recap card's session-scoped dismissal (issue #1796). The phone stores
 * the seen cycle start per profile in device-local settings; the web keeps
 * nothing at rest, so the same idea lives as a module variable for the
 * session, keyed by the cycle start so a later cycle still shows its own
 * recap.
 */

let dismissedCycleStart: string | null = null;

export function recapDismissed(cycleStart: string): boolean {
  return dismissedCycleStart === cycleStart;
}

export function dismissRecap(cycleStart: string): void {
  dismissedCycleStart = cycleStart;
}

/** Test seam: module state persists across cases within one test file. */
export function resetRecapDismissForTests(): void {
  dismissedCycleStart = null;
}
