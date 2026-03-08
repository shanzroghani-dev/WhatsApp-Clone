import 'package:flutter/material.dart';
import 'package:whatsapp_clone/core/design_tokens.dart';
import 'package:whatsapp_clone/core/security_service.dart';

class SecurityUnlockScreen extends StatefulWidget {
  const SecurityUnlockScreen({super.key});

  @override
  State<SecurityUnlockScreen> createState() => _SecurityUnlockScreenState();
}

class _SecurityUnlockScreenState extends State<SecurityUnlockScreen> {
  final TextEditingController _pinController = TextEditingController();
  bool _biometricAvailable = false;
  bool _checkingBiometric = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initBiometric();
  }

  Future<void> _initBiometric() async {
    final enabled = await SecurityService.isBiometricPromptEnabled();
    final available = enabled && await SecurityService.canUseBiometrics();
    if (!mounted) return;
    setState(() {
      _biometricAvailable = available;
      _checkingBiometric = false;
    });
  }

  Future<void> _unlockWithPin() async {
    final pin = _pinController.text.trim();
    if (pin.length < 4) {
      setState(() => _error = 'Enter a valid PIN');
      return;
    }

    final verified = await SecurityService.verifyPin(pin);
    if (!mounted) return;
    if (verified) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = 'Incorrect PIN');
    }
  }

  Future<void> _unlockWithBiometric() async {
    final ok = await SecurityService.authenticateWithBiometrics();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Unlock App'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline_rounded, size: 56),
              const SizedBox(height: AppSpacing.lg),
              const Text(
                'Enter your PIN to continue',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _pinController,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: 'App PIN',
                  errorText: _error,
                  counterText: '',
                ),
                onSubmitted: (_) => _unlockWithPin(),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _unlockWithPin,
                  child: const Text('Unlock'),
                ),
              ),
              if (!_checkingBiometric && _biometricAvailable) ...[
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _unlockWithBiometric,
                    icon: const Icon(Icons.fingerprint_rounded),
                    label: const Text('Use biometrics'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
