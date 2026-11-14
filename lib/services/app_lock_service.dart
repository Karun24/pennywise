import 'package:flutter/foundation.dart' show debugPrint;
import 'package:local_auth/local_auth.dart';

/// Result of an unlock attempt.
enum UnlockResult { success, failed, unavailable }

/// Verifies the user with the phone's own lock: fingerprint, face, or the
/// device PIN / pattern / password. PennyWise never sees or stores any of
/// these - Android/iOS handles the check.
abstract class AppLockAuthenticator {
  /// True if the phone has a screen lock or biometrics set up.
  Future<bool> isAvailable();

  Future<UnlockResult> authenticate(String reason);
}

class DeviceAppLockAuthenticator implements AppLockAuthenticator {
  DeviceAppLockAuthenticator();

  final LocalAuthentication _auth = LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (e) {
      debugPrint('PennyWise: app lock unavailable: $e');
      return false;
    }
  }

  @override
  Future<UnlockResult> authenticate(String reason) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        // Allow the phone PIN/pattern as a fallback to fingerprint/face.
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      return ok ? UnlockResult.success : UnlockResult.failed;
    } catch (e) {
      debugPrint('PennyWise: unlock error: $e');
      final available = await isAvailable();
      return available ? UnlockResult.failed : UnlockResult.unavailable;
    }
  }
}

/// Always succeeds. Used in tests.
class AlwaysUnlockAuthenticator implements AppLockAuthenticator {
  const AlwaysUnlockAuthenticator();

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<UnlockResult> authenticate(String reason) async =>
      UnlockResult.success;
}
