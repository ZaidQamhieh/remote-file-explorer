import { NativeModule, requireNativeModule } from 'expo';

import type { RfeResponse } from './RfeTransport.types';

declare class RfeTransportModule extends NativeModule<{}> {
  /** Flutter shared_preferences (`flutter.` stripped); each value is JSON-encoded. */
  legacyPrefsReadAll(): Promise<Record<string, string>>;
  secureRead(key: string): Promise<string | null>;
  secureWrite(key: string, value: string): Promise<void>;
  secureDelete(key: string): Promise<void>;
  secureContains(key: string): Promise<boolean>;
  probeFingerprint(url: string, timeoutMs?: number): Promise<string>;
  request(
    url: string,
    method: string,
    headers: Record<string, string>,
    bodyText: string | null,
    pin: string | null,
    timeoutMs?: number,
  ): Promise<RfeResponse>;
  downloadToFile(
    url: string,
    headers: Record<string, string>,
    pin: string | null,
    destPath: string,
    offset?: number,
    timeoutMs?: number,
  ): Promise<number>;
}

export default requireNativeModule<RfeTransportModule>('RfeTransport');
