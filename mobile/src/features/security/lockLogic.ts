/** After leaving the app for less than this, coming back does not ask again (the system auth sheet itself backgrounds the app). */
export const RELOCK_GRACE_MS = 2000;

/** Whether resuming after [backgroundedAt] must show the lock again. Unknown background time locks. */
export function shouldRelockOnResume(enabled: boolean, backgroundedAt: number | null, now: number, graceMs = RELOCK_GRACE_MS): boolean {
  if (!enabled) return false;
  if (backgroundedAt === null) return true;
  return now - backgroundedAt >= graceMs;
}

export type AuthOutcome = 'success' | 'failed' | 'unavailable';

/**
 * Device auth outcome to lock action. `unavailable` (no screen lock enrolled, or no hardware) opens the app: a lock
 * that can never be satisfied would brick it, so it fails open exactly as the Flutter LockGate does.
 */
export const unlocksApp = (o: AuthOutcome): boolean => o !== 'failed';

/** Why the switch cannot be turned on right now, or null when it can. */
export function lockEnableBlocker(hasHardware: boolean, enrolledLevel: number): 'noHardware' | 'noScreenLock' | null {
  if (!hasHardware) return 'noHardware';
  return enrolledLevel > 0 ? null : 'noScreenLock';
}
