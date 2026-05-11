import 'package:local_auth/local_auth.dart';

class BiometricService {
  static final _auth = LocalAuthentication();

  static Future<bool> isAvailable() async {
    final canCheck = await _auth.canCheckBiometrics;
    final isSupported = await _auth.isDeviceSupported();
    return canCheck && isSupported;
  }

  static Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Authenticate to access ETL Manager',
        options: const AuthenticationOptions(
          biometricOnly: false, // PIN fallback bhi allow karo
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
