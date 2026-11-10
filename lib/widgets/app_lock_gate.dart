import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_lock_service.dart';
import '../state/finance_store.dart';
import '../theme/theme_ext.dart';

/// Covers the app with a lock screen when App lock is on: at start-up and
/// whenever the app comes back after being in the background for a while.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  /// How long the app may stay in the background before it locks again.
  static const relockAfter = Duration(seconds: 30);

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate>
    with WidgetsBindingObserver {
  bool _locked = false;
  bool _authenticating = false;
  bool _initialised = false;
  String? _message;
  DateTime? _backgroundSince;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialised) {
      _initialised = true;
      if (context.read<FinanceStore>().settings.appLock) {
        _locked = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The fingerprint dialog itself briefly pauses the app; ignore that.
    if (_authenticating) return;
    final enabled = context.read<FinanceStore>().settings.appLock;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgroundSince ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final since = _backgroundSince;
      _backgroundSince = null;
      if (enabled &&
          !_locked &&
          since != null &&
          DateTime.now().difference(since) >= AppLockGate.relockAfter) {
        setState(() {
          _locked = true;
          _message = null;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
      }
    }
  }

  Future<void> _unlock() async {
    if (_authenticating || !mounted) return;
    final auth = context.read<AppLockAuthenticator>();
    setState(() {
      _authenticating = true;
      _message = null;
    });
    final result = await auth.authenticate('Unlock PennyWise');
    if (!mounted) return;
    setState(() {
      _authenticating = false;
      _backgroundSince = null;
      switch (result) {
        case UnlockResult.success:
          _locked = false;
        case UnlockResult.failed:
          _message = 'Not unlocked. Tap Unlock to try again.';
        case UnlockResult.unavailable:
          // The phone's screen lock was removed; don't lock the user out.
          _locked = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled =
        context.select<FinanceStore, bool>((s) => s.settings.appLock);
    final showLock = enabled && _locked;
    return Stack(
      children: [
        // Keep the app alive underneath, but hidden from view and touch.
        Offstage(offstage: showLock, child: widget.child),
        if (showLock) _LockScreen(
          busy: _authenticating,
          message: _message,
          onUnlock: _unlock,
        ),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({
    required this.busy,
    required this.message,
    required this.onUnlock,
  });

  final bool busy;
  final String? message;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: context.penny.heroGradient,
            ),
          ),
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                      child: const Icon(Icons.lock_rounded,
                          size: 44, color: Colors.white),
                    ),
                    const SizedBox(height: 20),
                    Text('PennyWise is locked',
                        textAlign: TextAlign.center,
                        style: context.text.titleLarge
                            ?.copyWith(color: Colors.white)),
                    const SizedBox(height: 8),
                    Text(
                      'Use your fingerprint, face or phone PIN to open it.',
                      textAlign: TextAlign.center,
                      style: context.text.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.8)),
                    ),
                    if (message != null) ...[
                      const SizedBox(height: 12),
                      Text(message!,
                          textAlign: TextAlign.center,
                          style: context.text.bodySmall
                              ?.copyWith(color: const Color(0xFFFFD1DA))),
                    ],
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF2B1B7E),
                        minimumSize: const Size(200, 52),
                      ),
                      onPressed: busy ? null : onUnlock,
                      icon: const Icon(Icons.fingerprint_rounded),
                      label: const Text('Unlock'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
