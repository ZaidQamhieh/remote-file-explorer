import { Eye, EyeOff, Lock, LogIn, UserPlus, UserRound } from 'lucide-react-native';
import { useState } from 'react';
import { View } from 'react-native';

import { Button, InlineError, Pressable, Text, TextField } from '../../design/components';
import { useScheme } from '../../design/theme';
import { Spacing } from '../../design/tokens';
import { t } from '../../i18n';
import { pairingDeps } from '../../services';
import { AddressField, CodeBoxRow } from './fields';
import { humanizeError, loginWithAccount, probeTarget, registerAccount } from './pairingService';

/** Login (existing account) and Register (new account + one-time pairing code) share one form. */
export function AccountForm({ mode, prefillAddress, onPaired }: { mode: 'login' | 'register'; prefillAddress?: string; onPaired: (label: string) => void }) {
  const c = useScheme();
  const [address, setAddress] = useState(prefillAddress ?? '');
  const [code, setCode] = useState('');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [obscure, setObscure] = useState(true);
  const [touched, setTouched] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const reg = mode === 'register';

  const req = (v: string) => (touched && !v.trim() ? t('requiredLabel') : null);
  const pwError = touched ? (!password ? t('requiredLabel') : reg && password.length < 8 ? t('passwordTooShort') : null) : null;
  const confirmError = touched && reg && confirm !== password ? t('passwordMismatch') : null;

  async function submit() {
    setTouched(true);
    const invalid =
      !address.trim() || !username.trim() || !password || (reg && (!code.trim() || password.length < 8 || confirm !== password));
    if (invalid) return;
    setBusy(true);
    setError(null);
    try {
      const target = await probeTarget(pairingDeps, address);
      const host = reg
        ? await registerAccount(pairingDeps, target, { pairingCode: code, username, password })
        : await loginWithAccount(pairingDeps, target, { username, password });
      onPaired(host.label);
    } catch (e) {
      const msg = humanizeError(e);
      setError(reg ? t('registerFailed', { error: msg }) : t('loginFailed', { error: msg }));
    } finally {
      setBusy(false);
    }
  }

  const eye = (
    <Pressable onPress={() => setObscure((o) => !o)} accessibilityLabel={obscure ? 'Show password' : 'Hide password'}>
      {obscure ? <Eye size={18} color={c.onSurfaceVariant} /> : <EyeOff size={18} color={c.onSurfaceVariant} />}
    </Pressable>
  );
  return (
    <View style={{ gap: Spacing.md }}>
      <AddressField value={address} onChange={setAddress} error={req(address)} />
      {reg && (
        <View style={{ gap: 6 }}>
          <Text variant="labelMedium" muted>{t('pairingCodeLabel')}</Text>
          <CodeBoxRow value={code} onChange={setCode} />
          {touched && !code.trim() ? <Text variant="bodySmall" color={c.error}>{t('requiredLabel')}</Text> : null}
        </View>
      )}
      <TextField label={t('usernameLabel')} value={username} onChangeText={setUsername} autoCapitalize="none" autoCorrect={false} error={req(username)} leading={<UserRound size={18} color={c.onSurfaceVariant} />} />
      <TextField label={t('passwordLabel')} value={password} onChangeText={setPassword} secureTextEntry={obscure} autoCapitalize="none" autoCorrect={false} error={pwError} leading={<Lock size={18} color={c.onSurfaceVariant} />} trailing={eye} />
      {reg && <TextField label={t('confirmPasswordLabel')} value={confirm} onChangeText={setConfirm} secureTextEntry={obscure} autoCapitalize="none" autoCorrect={false} error={confirmError} leading={<Lock size={18} color={c.onSurfaceVariant} />} />}
      <Text variant="bodySmall" muted>{reg ? t('registerHint') : t('loginHint')}</Text>
      {error && <InlineError message={error} />}
      <Button label={reg ? t('registerButton') : t('loginButton')} busy={busy} onPress={submit} icon={reg ? <UserPlus size={18} color="#fff" /> : <LogIn size={18} color="#fff" />} />
    </View>
  );
}
