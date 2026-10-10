/**
 * The recap card's session-scoped dismissal (issue #1796; per profile and
 * cycle as of issue #1819). The phone stores the seen cycle start per
 * profile in device-local settings; the web keeps nothing at rest, so the
 * same idea lives as module state for the session, keyed by profile and by
 * the cycle start so another profile's recap - or a later cycle of this
 * one - still shows its own.
 */

const dismissedByProfile = new Map<string, string>();

export function recapDismissed(profileId: string, cycleStart: string): boolean {
  return dismissedByProfile.get(profileId) === cycleStart;
}

export function dismissRecap(profileId: string, cycleStart: string): void {
  dismissedByProfile.set(profileId, cycleStart);
}

/** Test seam: module state persists across cases within one test file. */
export function resetRecapDismissForTests(): void {
  dismissedByProfile.clear();
}
