import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecurityService {
  static const String _screenLockKey = 'security_screen_lock';
  static const String _biometricPromptKey = 'security_biometric_prompt';
  static const String _pinKey = 'security_pin';

  static final LocalAuthentication _localAuth = LocalAuthentication();

  static Future<bool> isScreenLockEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_screenLockKey) ?? false;
  }

  static Future<bool> isBiometricPromptEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_biometricPromptKey) ?? false;
  }

  static Future<void> setScreenLockEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_screenLockKey, enabled);
  }

  static Future<void> setBiometricPromptEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricPromptKey, enabled);
  }

  static Future<void> setPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pinKey, pin);
  }

  static Future<void> clearPin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pinKey);
  }

  static Future<bool> hasPin() async {
    final prefs = await SharedPreferences.getInstance();
    final pin = prefs.getString(_pinKey);
    return pin != null && pin.isNotEmpty;
  }

  static Future<bool> verifyPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pinKey) == pin;
  }

  static Future<bool> canUseBiometrics() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      return canCheck && isSupported;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticateWithBiometrics() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Authenticate to unlock WhatsApp Clone',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
