import { Fingerprint, Monitor } from 'lucide-react-native';
import { useRef, useState } from 'react';
import { TextInput, View } from 'react-native';

import { normalizeFingerprint } from '../../core/api/pin';
import { Text, TextField } from '../../design/components';
import { useScheme } from '../../design/theme';
import { FontFamily, Radii } from '../../design/tokens';
import { t } from '../../i18n';
import { CODE_LENGTH, sanitizeCode } from './codeInput';

export function AddressField({ value, onChange, error }: { value: string; onChange: (v: string) => void; error?: string | null }) {
  const c = useScheme();
  return (
    <TextField
      label={t('agentAddressLabel')}
      placeholder={t('agentAddressHint')}
      value={value}
      onChangeText={onChange}
      autoCapitalize="none"
      autoCorrect={false}
      keyboardType="url"
      error={error}
      leading={<Monitor size={18} color={c.onSurfaceVariant} />}
    />
  );
}

export function FingerprintField({ value, onChange, error }: { value: string; onChange: (v: string) => void; error?: string | null }) {
  const c = useScheme();
  return (
    <TextField
      label={t('fingerprintLabel')}
      placeholder={t('fingerprintHint')}
      helper={t('fingerprintVerificationHelp')}
      value={value}
      onChangeText={onChange}
      autoCapitalize="characters"
      autoCorrect={false}
      mono
      error={error}
      leading={<Fingerprint size={18} color={c.onSurfaceVariant} />}
    />
  );
}

export const fingerprintError = (v: string) => (normalizeFingerprint(v) === null ? t('fingerprintInvalid') : null);

/**
 * 8 display boxes over ONE real text input (the standard OTP pattern): fast typing, paste and IME
 * composition are handled by the native input rather than 8 racing controlled fields.
 */
export function CodeBoxRow({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  const c = useScheme();
  const ref = useRef<TextInput>(null);
  const [focused, setFocused] = useState(false);
  const chars = value.padEnd(CODE_LENGTH, ' ').slice(0, CODE_LENGTH).split('');
  const cursor = Math.min(value.length, CODE_LENGTH - 1);
  return (
    <View style={{ height: 48 }}>
      <View style={{ flexDirection: 'row', justifyContent: 'center', gap: 7 }} pointerEvents="none" accessibilityElementsHidden importantForAccessibility="no-hide-descendants">
        {chars.map((ch, i) => (
          <View
            key={i}
            style={{
              width: 34,
              height: 48,
              alignItems: 'center',
              justifyContent: 'center',
              backgroundColor: c.surfaceContainerHighest,
              borderRadius: Radii.chip,
              borderWidth: focused && i === cursor ? 2 : 1,
              borderColor: focused && i === cursor ? c.primary : c.outlineVariant,
            }}
          >
            <Text style={{ fontFamily: FontFamily.monoMedium, fontSize: 18 }}>{ch.trim()}</Text>
          </View>
        ))}
      </View>
      <TextInput
        ref={ref}
        accessibilityLabel={`Pairing code, ${CODE_LENGTH} characters`}
        value={value}
        onChangeText={(v) => onChange(sanitizeCode(v))}
        onFocus={() => setFocused(true)}
        onBlur={() => setFocused(false)}
        autoCapitalize="characters"
        autoCorrect={false}
        autoComplete="off"
        maxLength={CODE_LENGTH * 2}
        caretHidden
        style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, opacity: 0.02, color: 'transparent' }}
      />
    </View>
  );
}
