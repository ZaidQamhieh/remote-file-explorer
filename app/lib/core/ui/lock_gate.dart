import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../settings/settings_controller.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

abstract class AppAuthenticator {
  Future<bool> authenticate(String reason);
}

class LocalAppAuthenticator implements AppAuthenticator {
  LocalAppAuthenticator([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> authenticate(String reason) => _auth.authenticate(
    localizedReason: reason,
    options: const AuthenticationOptions(
      biometricOnly: false,
      stickyAuth: true,
    ),
  );
}

final appAuthenticatorProvider = Provider<AppAuthenticator>(
  (_) => LocalAppAuthenticator(),
);

/// How long after a successful unlock a resume event is treated as the
/// delayed echo of that same auth flow rather than a genuine re-open.
const _postUnlockGrace = Duration(seconds: 2);

/// True when an [AppLifecycleState.resumed] event should re-lock the app.
///
/// Showing the system biometric prompt itself pauses/resumes the app on some
/// devices (see local_auth's `stickyAuth` docs) — re-locking on that resume
/// would stomp the unlock that's about to land from the in-flight
/// `authenticate()` call, making a successful scan look like it did nothing.
///
/// That guard alone isn't enough: the native resumed event (fired when the
/// prompt UI closes) can arrive *after* `authenticate()` already resolved and
/// reset `authenticating` to false — so a successful scan unlocks the app for
/// an instant, then this same resume immediately re-locks it, looking like
/// biometrics "doesn't let you in". `justUnlocked` covers that race with a
/// short grace window; it does not weaken re-lock-on-backgrounding since a
/// real re-open more than [_postUnlockGrace] later still re-locks normally.
bool shouldRelockOnResume({
  required bool appLockEnabled,
  required bool authenticating,
  required bool justUnlocked,
}) => appLockEnabled && !authenticating && !justUnlocked;

class LockGate extends ConsumerStatefulWidget {
  const LockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate>
    with WidgetsBindingObserver {
  bool _locked = true;
  bool _authenticating = false;
  DateTime? _lastUnlockAt;
  String? _authError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // settingsProvider loads asynchronously from SharedPreferences — reading
    // it synchronously here (before it resolves) always sees the not-yet-
    // loaded default (app lock "off") and would unlock immediately regardless
    // of the real persisted value. Wait for it to actually load first.
    ref.read(settingsProvider.future).then((_) {
      if (mounted) _tryUnlock();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden) &&
        _isEnabled) {
      if (mounted) setState(() => _locked = true);
      return;
    }
    if (state == AppLifecycleState.resumed &&
        shouldRelockOnResume(
          appLockEnabled: _isEnabled,
          authenticating: _authenticating,
          justUnlocked:
              _lastUnlockAt != null &&
              DateTime.now().difference(_lastUnlockAt!) < _postUnlockGrace,
        )) {
      setState(() => _locked = true);
      _tryUnlock();
    }
  }

  bool get _isEnabled =>
      ref.read(settingsProvider).valueOrNull?.app.appLockEnabled ?? false;

  Future<void> _tryUnlock() async {
    if (!_isEnabled) {
      setState(() => _locked = false);
      return;
    }
    if (_authenticating) return;
    _authenticating = true;
    if (mounted) setState(() => _authError = null);
    try {
      final ok = await ref
          .read(appAuthenticatorProvider)
          .authenticate('Unlock Remote File Explorer');
      if (!ok && mounted) {
        setState(() => _authError = 'Authentication was not completed.');
      }
      if (ok && mounted) {
        _lastUnlockAt = DateTime.now();
        setState(() => _locked = false);
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(
          () =>
              _authError = 'Device authentication is unavailable (${e.code}).',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _authError = 'Unable to authenticate on this device.');
      }
    } finally {
      _authenticating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    return settings.when(
      loading: () => _lockedView(context, loading: true),
      error:
          (_, __) => _lockedView(
            context,
            message: 'Security settings could not be loaded.',
          ),
      data: (value) {
        if (!value.app.appLockEnabled || !_locked) return widget.child;
        return _lockedView(context, message: _authError, canUnlock: true);
      },
    );
  }

  Widget _lockedView(
    BuildContext context, {
    bool loading = false,
    bool canUnlock = false,
    String? message,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.lock, size: 64, color: scheme.primary),
            const SizedBox(height: 24),
            Text('Locked', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            if (loading)
              const CircularProgressIndicator()
            else ...[
              if (message != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(message, textAlign: TextAlign.center),
                ),
                const SizedBox(height: 16),
              ],
              if (canUnlock)
                FilledButton.icon(
                  onPressed: _tryUnlock,
                  icon: const Icon(LucideIcons.fingerprint),
                  label: const Text('Unlock'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
