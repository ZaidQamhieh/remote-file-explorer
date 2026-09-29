// Ported from app/lib/core/theme/{tokens,app_theme}.dart. Light values are the
// exact ColorScheme.fromSeed(seed #4C8DFF, secondary #9B87F5) output of the
// shipped Flutter app; dark is its hand-picked zinc scheme. Every value was
// dumped from the Flutter ThemeData, none inferred.

export const Brand = {
  seed: '#4C8DFF',
  seedDim: '#2C5FCC',
  accent: '#9B87F5',
  accentDim: '#7C6AE0',
  online: '#34D399',
  offline: '#9AA0A6',
  amber: '#F3A73F',
  red: '#F1596B',
  primaryGradient: ['#4C8DFF', '#2C5FCC'] as const,
  accentGradient: ['#9B87F5', '#7C6AE0'] as const,
} as const;

export const Spacing = { xs: 4, sm: 8, md2: 12, md: 16, md3: 20, lg: 24, xl: 32 } as const;

/** Mockup radius scale 8/14/20/28 plus stadium. */
export const Radii = { chip: 8, sm: 14, card: 20, lg: 28, sheet: 28, stadium: 999 } as const;

export const Motion = { short: 150, medium: 250, long: 350 } as const;

export type Scheme = {
  dark: boolean;
  primary: string;
  onPrimary: string;
  primaryContainer: string;
  onPrimaryContainer: string;
  secondary: string;
  onSecondary: string;
  secondaryContainer: string;
  onSecondaryContainer: string;
  tertiary: string;
  tertiaryContainer: string;
  onTertiaryContainer: string;
  error: string;
  onError: string;
  errorContainer: string;
  onErrorContainer: string;
  inverseSurface: string;
  onInverseSurface: string;
  surface: string;
  onSurface: string;
  onSurfaceVariant: string;
  outline: string;
  outlineVariant: string;
  surfaceContainerLowest: string;
  surfaceContainerLow: string;
  surfaceContainer: string;
  surfaceContainerHigh: string;
  surfaceContainerHighest: string;
};

export const lightScheme: Scheme = {
  dark: false,
  primary: '#445E91',
  onPrimary: '#FFFFFF',
  primaryContainer: '#D8E2FF',
  onPrimaryContainer: '#2C4678',
  secondary: '#9B87F5',
  onSecondary: '#FFFFFF',
  secondaryContainer: '#DBE2F9',
  onSecondaryContainer: '#3F4759',
  tertiary: '#715573',
  tertiaryContainer: '#FCD7FB',
  onTertiaryContainer: '#583E5B',
  error: '#BA1A1A',
  onError: '#FFFFFF',
  errorContainer: '#FFDAD6',
  onErrorContainer: '#93000A',
  inverseSurface: '#2F3036',
  onInverseSurface: '#F0F0F7',
  surface: '#F9F9FF',
  onSurface: '#1A1B20',
  onSurfaceVariant: '#44474F',
  outline: '#75777F',
  outlineVariant: '#C5C6D0',
  surfaceContainerLowest: '#FFFFFF',
  surfaceContainerLow: '#F3F3FA',
  surfaceContainer: '#EEEDF4',
  surfaceContainerHigh: '#E8E7EF',
  surfaceContainerHighest: '#E2E2E9',
};

export const darkScheme: Scheme = {
  dark: true,
  primary: Brand.seed,
  onPrimary: '#0B1220',
  primaryContainer: Brand.seed,
  onPrimaryContainer: '#0B1220',
  secondary: Brand.online,
  onSecondary: '#06281E',
  secondaryContainer: Brand.online,
  onSecondaryContainer: '#06281E',
  tertiary: Brand.online,
  tertiaryContainer: Brand.online,
  onTertiaryContainer: '#06281E',
  error: Brand.red,
  onError: '#2E0A0A',
  errorContainer: Brand.red,
  onErrorContainer: '#2E0A0A',
  inverseSurface: '#F4F4F5',
  onInverseSurface: '#09090B',
  surface: '#09090B',
  onSurface: '#F4F4F5',
  onSurfaceVariant: '#71717A',
  outline: '#52525B',
  outlineVariant: '#27272A',
  surfaceContainerLowest: '#000000',
  surfaceContainerLow: '#0F0F11',
  surfaceContainer: '#18181B',
  surfaceContainerHigh: '#212125',
  surfaceContainerHighest: '#27272A',
};

/** AMOLED variant of the dark scheme (Flutter AppTheme.toAmoled). */
export const amoledScheme: Scheme = {
  ...darkScheme,
  surface: '#000000',
  surfaceContainerLowest: '#000000',
  surfaceContainerLow: '#000000',
  surfaceContainer: '#000000',
  surfaceContainerHigh: '#18181B',
  surfaceContainerHighest: '#27272A',
};

export const FontFamily = {
  regular: 'Inter-Regular',
  medium: 'Inter-Medium',
  semibold: 'Inter-SemiBold',
  mono: 'JetBrainsMono-Regular',
  monoMedium: 'JetBrainsMono-Medium',
} as const;

/** Material 3 type roles as used by the Flutter theme (Inter, weights 400/500/600). */
export const TypeScale = {
  headlineSmall: { fontSize: 24, lineHeight: 32, fontFamily: FontFamily.regular },
  titleLarge: { fontSize: 22, lineHeight: 28, fontFamily: FontFamily.semibold },
  titleMedium: { fontSize: 16, lineHeight: 24, letterSpacing: 0.15, fontFamily: FontFamily.medium },
  titleSmall: { fontSize: 14, lineHeight: 20, letterSpacing: 0.1, fontFamily: FontFamily.medium },
  bodyLarge: { fontSize: 16, lineHeight: 24, letterSpacing: 0.5, fontFamily: FontFamily.regular },
  bodyMedium: { fontSize: 14, lineHeight: 20, letterSpacing: 0.25, fontFamily: FontFamily.regular },
  bodySmall: { fontSize: 12, lineHeight: 16, letterSpacing: 0.4, fontFamily: FontFamily.regular },
  labelLarge: { fontSize: 14, lineHeight: 20, letterSpacing: 0.1, fontFamily: FontFamily.medium },
  labelMedium: { fontSize: 12, lineHeight: 16, letterSpacing: 0.5, fontFamily: FontFamily.medium },
  /** Mockup `.section-label`: 10.5/700 uppercase, .09em tracking. */
  sectionLabel: { fontSize: 10.5, lineHeight: 14, letterSpacing: 0.945, fontFamily: FontFamily.semibold },
  /** ScreenHeader title: 19/700, -0.19 tracking. */
  screenTitle: { fontSize: 19, lineHeight: 24, letterSpacing: -0.19, fontFamily: FontFamily.semibold },
  screenSubtitle: { fontSize: 11.5, lineHeight: 15, fontFamily: FontFamily.regular },
} as const;

export type TypeRole = keyof typeof TypeScale;
