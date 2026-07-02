import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth/local_auth.dart';

import '../settings/settings_controller.dart';

/// [PlatformException.code]s meaning the device has no biometric/PIN/pattern
/// set up at all — there's nothing to lock behind, so falling through
/// unlocked is correct. Any other error (cancelled, lockout, unknown) must
/// NOT unlock — that would make the lock trivially bypassable by dismissing
/// the prompt.
const _noAuthAvailableCodes = {
  auth_error.notAvailable,
  auth_error.notEnrolled,
  auth_error.passcodeNotSet,
  auth_error.otherOperatingSystem,
};

class LockGate extends ConsumerStatefulWidget {
  const LockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate>
    with WidgetsBindingObserver {
  final _auth = LocalAuthentication();
  bool _locked = true;
  bool _authenticating = false;

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
    if (state == AppLifecycleState.resumed && _isEnabled) {
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
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock Remote File Explorer',
        options: const AuthenticationOptions(biometricOnly: false),
      );
      if (ok && mounted) setState(() => _locked = false);
    } on PlatformException catch (e) {
      if (_noAuthAvailableCodes.contains(e.code) && mounted) {
        setState(() => _locked = false);
      }
      // Otherwise (cancelled, lockout, unknown) stay locked.
    } catch (_) {
      // Unexpected error — stay locked rather than silently bypassing.
    } finally {
      _authenticating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(
      settingsProvider.select(
        (s) => s.valueOrNull?.app.appLockEnabled ?? false,
      ),
    );

    if (!enabled || !_locked) return widget.child;

    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 64, color: scheme.primary),
            const SizedBox(height: 24),
            Text('Locked', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _tryUnlock,
              icon: const Icon(Icons.fingerprint),
              label: const Text('Unlock'),
            ),
          ],
        ),
      ),
    );
  }
}
