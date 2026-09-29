import { createContext, useContext, useMemo, type ReactNode } from 'react';
import { useColorScheme } from 'react-native';

import { amoledScheme, darkScheme, lightScheme, type Scheme } from './tokens';

export type ThemeMode = 'system' | 'light' | 'dark' | 'amoled';

type Ctx = { scheme: Scheme; mode: ThemeMode };
const ThemeContext = createContext<Ctx>({ scheme: lightScheme, mode: 'system' });

export function resolveScheme(mode: ThemeMode, systemDark: boolean): Scheme {
  if (mode === 'amoled') return amoledScheme;
  if (mode === 'dark') return darkScheme;
  if (mode === 'light') return lightScheme;
  return systemDark ? darkScheme : lightScheme;
}

export function ThemeProvider({ mode = 'system', children }: { mode?: ThemeMode; children: ReactNode }) {
  const systemDark = useColorScheme() === 'dark';
  const value = useMemo(() => ({ scheme: resolveScheme(mode, systemDark), mode }), [mode, systemDark]);
  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export const useScheme = (): Scheme => useContext(ThemeContext).scheme;
