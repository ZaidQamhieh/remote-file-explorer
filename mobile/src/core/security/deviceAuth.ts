import * as LocalAuthentication from 'expo-local-authentication';

import type { AuthOutcome } from '../../features/security/lockLogic';

/** Hardware present and the enrolled security level (0 none, 1 PIN/pattern, higher biometric). */
export async function deviceAuthState(): Promise<{ hasHardware: boolean; level: number }> {
  try {
    const [hasHardware, level] = await Promise.all([LocalAuthentication.hasHardwareAsync(), LocalAuthentication.getEnrolledLevelAsync()]);
    return { hasHardware, level };
  } catch {
    return { hasHardware: false, level: 0 };
  }
}

/** Biometric prompt with the device PIN/pattern as fallback. Missing hardware or enrollment reports `unavailable`. */
export async function authenticate(reason: string): Promise<AuthOutcome> {
  const { hasHardware, level } = await deviceAuthState();
  if (!hasHardware || level === 0) return 'unavailable';
  try {
    const r = await LocalAuthentication.authenticateAsync({ promptMessage: reason, disableDeviceFallback: false });
    return r.success ? 'success' : 'failed';
  } catch {
    return 'unavailable';
  }
}
