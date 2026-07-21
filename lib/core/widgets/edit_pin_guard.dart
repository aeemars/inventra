import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/controllers/auth_controller.dart';
import '../constants/app_colors.dart';
import '../constants/app_typography.dart';
import '../extensions/theme_ext.dart';

/// Provider tracking whether the Edit PIN has been unlocked in the current session
final editPinUnlockedProvider = StateProvider<bool>((ref) => false);

class EditPinGuard extends ConsumerStatefulWidget {
  final Widget child;

  const EditPinGuard({
    super.key,
    required this.child,
  });

  @override
  ConsumerState<EditPinGuard> createState() => _EditPinGuardState();
}

class _EditPinGuardState extends ConsumerState<EditPinGuard> {
  // PIN entry states
  String _pin = '';
  String _errorMessage = '';

  // Setup PIN states
  bool _isSettingUp = false;
  String _firstPin = '';
  String _confirmPin = '';
  bool _confirming = false;
  String? _generatedRecoveryCode;
  bool _showRecoveryCodeScreen = false;

  // Recovery reset states
  bool _isRecovering = false;
  final _recoveryController = TextEditingController();
  String _recoveryError = '';

  @override
  void dispose() {
    _recoveryController.dispose();
    super.dispose();
  }

  String _generateRecoveryCode() {
    final rand = Random();
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    String nextPart(int len) =>
        List.generate(len, (index) => chars[rand.nextInt(chars.length)]).join();
    return 'INV-${nextPart(4)}-${nextPart(4)}';
  }

  void _onKeyPress(String val, bool forSetup) {
    setState(() {
      _errorMessage = '';
      if (forSetup) {
        if (_confirming) {
          if (_confirmPin.length < 4) {
            _confirmPin += val;
            if (_confirmPin.length == 4) {
              _verifyAndSaveSetupPin();
            }
          }
        } else {
          if (_firstPin.length < 4) {
            _firstPin += val;
            if (_firstPin.length == 4) {
              _confirming = true;
            }
          }
        }
      } else {
        if (_pin.length < 4) {
          _pin += val;
          if (_pin.length == 4) {
            _verifyEnteredPin();
          }
        }
      }
    });
  }

  void _onBackspace(bool forSetup) {
    setState(() {
      _errorMessage = '';
      if (forSetup) {
        if (_confirming) {
          if (_confirmPin.isNotEmpty) {
            _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
          } else {
            _confirming = false;
          }
        } else {
          if (_firstPin.isNotEmpty) {
            _firstPin = _firstPin.substring(0, _firstPin.length - 1);
          }
        }
      } else {
        if (_pin.isNotEmpty) {
          _pin = _pin.substring(0, _pin.length - 1);
        }
      }
    });
  }

  void _onClear(bool forSetup) {
    setState(() {
      _errorMessage = '';
      if (forSetup) {
        _firstPin = '';
        _confirmPin = '';
        _confirming = false;
      } else {
        _pin = '';
      }
    });
  }

  void _verifyEnteredPin() {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    if (user.editPin == _pin) {
      ref.read(editPinUnlockedProvider.notifier).state = true;
    } else {
      setState(() {
        _pin = '';
        _errorMessage = 'Incorrect PIN. Please try again.';
      });
    }
  }

  Future<void> _verifyAndSaveSetupPin() async {
    if (_firstPin != _confirmPin) {
      setState(() {
        _confirmPin = '';
        _errorMessage = 'PINs do not match. Restarting setup...';
        _firstPin = '';
        _confirming = false;
      });
      return;
    }

    final code = _generateRecoveryCode();
    final success = await ref
        .read(authControllerProvider.notifier)
        .setEditPin(_firstPin, code);

    if (success && mounted) {
      ref.invalidate(authStateProvider);
      setState(() {
        _generatedRecoveryCode = code;
        _showRecoveryCodeScreen = true;
      });
    } else if (mounted) {
      setState(() {
        _errorMessage = 'Failed to save PIN. Try again.';
        _firstPin = '';
        _confirmPin = '';
        _confirming = false;
      });
    }
  }

  void _verifyRecoveryCode() {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final entered = _recoveryController.text.trim().toUpperCase();
    final actual = user.editPinRecoveryCode?.trim().toUpperCase();

    if (actual != null && entered == actual) {
      setState(() {
        _isRecovering = false;
        _isSettingUp = true;
        _firstPin = '';
        _confirmPin = '';
        _confirming = false;
        _pin = '';
        _errorMessage = '';
        _recoveryController.clear();
        _recoveryError = '';
      });
    } else {
      setState(() {
        _recoveryError = 'Invalid recovery code. Please check spelling.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUnlocked = ref.watch(editPinUnlockedProvider);
    if (isUnlocked) return widget.child;

    final user = ref.watch(currentUserProvider);
    final hasPin = user?.editPin != null && user!.editPin!.isNotEmpty;

    if (_showRecoveryCodeScreen) {
      return _buildRecoveryDisplay();
    }

    if (_isRecovering) {
      return _buildRecoveryInputView();
    }

    if (_isSettingUp || !hasPin) {
      return _buildSetupView();
    }

    return _buildUnlockView();
  }

  // Helper NumPad Widget
  Widget _buildNumPad(bool forSetup) {
    return Column(
      children: [
        for (var row in [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: row.map((val) => _buildNumButton(val, forSetup)).toList(),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildSpecialButton('C', () => _onClear(forSetup)),
            _buildNumButton('0', forSetup),
            _buildSpecialButton(
              '⌫',
              () => _onBackspace(forSetup),
              icon: Icons.backspace_outlined,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNumButton(String val, bool forSetup) {
    return SizedBox(
      width: 72,
      height: 72,
      child: ElevatedButton(
        onPressed: () => _onKeyPress(val, forSetup),
        style: ElevatedButton.styleFrom(
          shape: const CircleBorder(),
          backgroundColor: context.appSurfaceRaised,
          foregroundColor: context.appTextPrimary,
          elevation: 1,
        ),
        child: Text(
          val,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildSpecialButton(String label, VoidCallback onTap, {IconData? icon}) {
    return SizedBox(
      width: 72,
      height: 72,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          shape: const CircleBorder(),
          side: BorderSide(color: context.appCardBorder),
          foregroundColor: context.appTextSecondary,
        ),
        child: icon != null
            ? Icon(icon, size: 20)
            : Text(
                label,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }

  // 1. Setup View
  Widget _buildSetupView() {
    final title = _confirming ? 'Confirm PIN' : 'Create Edit PIN';
    final currentInput = _confirming ? _confirmPin : _firstPin;

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            setState(() {
              _isSettingUp = false;
              _confirming = false;
              _firstPin = '';
              _confirmPin = '';
              _errorMessage = '';
            });
            context.go('/dashboard');
          },
        ),
        title: const Text('Setup PIN Protection'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline_rounded,
                  size: 56, color: AppColors.primary),
              const SizedBox(height: 16),
              Text(
                title,
                style: AppTypography.h2.copyWith(color: context.appTextPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                _confirming
                    ? 'Confirm your 4-digit PIN'
                    : 'Set a 4-digit PIN to restrict editing rights',
                style: TextStyle(color: context.appTextSecondary),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  final hasChar = index < currentInput.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hasChar ? AppColors.primary : context.appDivider,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 16),
              if (_errorMessage.isNotEmpty)
                Text(
                  _errorMessage,
                  style: const TextStyle(color: AppColors.error, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              const Spacer(),
              _buildNumPad(true),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // 2. Recovery Code Setup Display
  Widget _buildRecoveryDisplay() {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.security_rounded,
                color: AppColors.success,
                size: 72,
              ),
              const SizedBox(height: 24),
              Text(
                'PIN Configured Successfully!',
                style: AppTypography.h2.copyWith(color: context.appTextPrimary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Below is your recovery code. Keep this code safe. '
                'It is the only way to reset your PIN if you forget it.',
                textAlign: TextAlign.center,
                style: TextStyle(height: 1.4),
              ),
              const SizedBox(height: 32),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                decoration: BoxDecoration(
                  color: context.appSurfaceRaised,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.success.withValues(alpha: 0.3), width: 1.5),
                ),
                child: SelectableText(
                  _generatedRecoveryCode ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: AppColors.success,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.info_outline_rounded, size: 16, color: Colors.orange),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Store this securely. It will not be shown again.',
                      style: TextStyle(fontSize: 12, color: context.appTextSecondary),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _showRecoveryCodeScreen = false;
                      _isSettingUp = false;
                    });
                    ref.read(editPinUnlockedProvider.notifier).state = true;
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Got it, proceed'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 3. Unlock Entry Screen
  Widget _buildUnlockView() {
    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/dashboard'),
        ),
        title: const Text('Restricted Access'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_rounded, size: 56, color: AppColors.primary),
              const SizedBox(height: 16),
              Text(
                'Enter Edit PIN',
                style: AppTypography.h2.copyWith(color: context.appTextPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                'Please enter your 4-digit PIN to modify details',
                style: TextStyle(color: context.appTextSecondary),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  final hasChar = index < _pin.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hasChar ? AppColors.primary : context.appDivider,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 16),
              if (_errorMessage.isNotEmpty)
                Text(
                  _errorMessage,
                  style: const TextStyle(color: AppColors.error, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isRecovering = true;
                    _recoveryError = '';
                    _recoveryController.clear();
                  });
                },
                child: const Text(
                  'Forgot PIN?',
                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
                ),
              ),
              const Spacer(),
              _buildNumPad(false),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // 4. Recovery Input Code View
  Widget _buildRecoveryInputView() {
    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            setState(() {
              _isRecovering = false;
              _recoveryError = '';
            });
          },
        ),
        title: const Text('Reset PIN'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Text(
                'Reset Edit PIN',
                style: AppTypography.h1.copyWith(color: context.appTextPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter the 8-character recovery code generated during PIN setup to reset your PIN.',
                style: TextStyle(color: context.appTextSecondary, height: 1.4),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _recoveryController,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Recovery Code',
                  hintText: 'INV-XXXX-XXXX',
                  prefixIcon: const Icon(Icons.vpn_key_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  errorText: _recoveryError.isNotEmpty ? _recoveryError : null,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _verifyRecoveryCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Verify and Reset'),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
