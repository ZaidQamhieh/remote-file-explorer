import { createContext, useContext, useMemo, type ReactNode } from 'react';
import { useColorScheme } from 'react-native';

import { schemeFromSeed } from './accent';
import { amoledScheme, darkScheme, lightScheme, type Scheme } from './tokens';

export type ThemeMode = 'system' | 'light' | 'dark' | 'amoled';

type Ctx = { scheme: Scheme; mode: ThemeMode };
const ThemeContext = createContext<Ctx>({ scheme: lightScheme, mode: 'system' });

const AMOLED_SURFACES = {
  surface: amoledScheme.surface,
  surfaceContainerLowest: amoledScheme.surfaceContainerLowest,
  surfaceContainerLow: amoledScheme.surfaceContainerLow,
  surfaceContainer: amoledScheme.surfaceContainer,
} as const;

/** [seed] is an ARGB accent; null keeps the hand-picked default schemes. */
export function resolveScheme(mode: ThemeMode, systemDark: boolean, seed: number | null = null): Scheme {
  if (seed !== null) {
    const dark = mode === 'amoled' || mode === 'dark' || (mode === 'system' && systemDark);
    const derived = schemeFromSeed(seed, dark);
    return mode === 'amoled' ? { ...derived, ...AMOLED_SURFACES } : derived;
  }
  if (mode === 'amoled') return amoledScheme;
  if (mode === 'dark') return darkScheme;
  if (mode === 'light') return lightScheme;
  return systemDark ? darkScheme : lightScheme;
}

export function ThemeProvider({ mode = 'system', seed = null, children }: { mode?: ThemeMode; seed?: number | null; children: ReactNode }) {
  const systemDark = useColorScheme() === 'dark';
  const value = useMemo(() => ({ scheme: resolveScheme(mode, systemDark, seed), mode }), [mode, systemDark, seed]);
  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export const useScheme = (): Scheme => useContext(ThemeContext).scheme;
