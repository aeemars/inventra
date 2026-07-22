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
  bool _isVerifying = false;

  // Setup PIN states
  bool _isSettingUp = false;
  String _firstPin = '';
  String _confirmPin = '';
  bool _confirming = false;

  // Emailed reset states
  bool _isResetting = false;
  bool _showResetCodeScreen = false;
  String? _maskedEmail;
  final _codeController = TextEditingController();
  final _newPinController = TextEditingController();
  String _resetError = '';

  @override
  void dispose() {
    _codeController.dispose();
    _newPinController.dispose();
    super.dispose();
  }

  void _onKeyPress(String val, bool forSetup) {
    if (_isVerifying) return;
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
    if (_isVerifying) return;
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
    if (_isVerifying) return;
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

  Future<void> _verifyEnteredPin() async {
    final enteredPin = _pin;
    setState(() => _isVerifying = true);
    try {
      final valid = await ref.read(authRepositoryProvider).verifyEditPin(enteredPin);
      if (valid && mounted) {
        ref.read(editPinUnlockedProvider.notifier).state = true;
      } else if (mounted) {
        setState(() {
          _pin = '';
          _errorMessage = 'Incorrect PIN. Please try again.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pin = '';
          _errorMessage = 'Verification error: ${e.toString()}';
        });
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
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

    setState(() => _isVerifying = true);
    try {
      await ref.read(authRepositoryProvider).setEditPin(newPin: _firstPin);
      if (mounted) {
        ref.read(editPinUnlockedProvider.notifier).state = true;
        setState(() {
          _isSettingUp = false;
          _confirming = false;
          _firstPin = '';
          _confirmPin = '';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to save PIN. Try again.';
          _firstPin = '';
          _confirmPin = '';
          _confirming = false;
        });
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _requestReset() async {
    setState(() {
      _isVerifying = true;
      _resetError = '';
    });
    try {
      final masked = await ref.read(authRepositoryProvider).requestEditPinReset();
      if (mounted) {
        setState(() {
          _maskedEmail = masked;
          _showResetCodeScreen = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _resetError = 'Could not send reset email: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _confirmReset() async {
    final code = _codeController.text.trim();
    final newPin = _newPinController.text.trim();

    if (code.length != 6) {
      setState(() => _resetError = 'Reset code must be 6 digits');
      return;
    }
    if (!RegExp(r'^\d{4}$').hasMatch(newPin)) {
      setState(() => _resetError = 'New PIN must be exactly 4 digits');
      return;
    }

    setState(() {
      _isVerifying = true;
      _resetError = '';
    });
    try {
      await ref.read(authRepositoryProvider).confirmEditPinReset(code: code, newPin: newPin);
      if (mounted) {
        ref.read(editPinUnlockedProvider.notifier).state = true;
        setState(() {
          _isResetting = false;
          _showResetCodeScreen = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _resetError = 'Reset failed: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUnlocked = ref.watch(editPinUnlockedProvider);
    if (isUnlocked) return widget.child;

    final user = ref.watch(currentUserProvider);
    final hasPin = user?.hasEditPin ?? false;

    if (_showResetCodeScreen) {
      return _buildResetCodeScreen();
    }

    if (_isResetting) {
      return _buildRequestResetView();
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
        onPressed: _isVerifying ? null : () => _onKeyPress(val, forSetup),
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
        onPressed: _isVerifying ? null : onTap,
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
              if (_isVerifying)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (_errorMessage.isNotEmpty)
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

  // 2. Unlock Entry Screen
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
              if (_isVerifying)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (_errorMessage.isNotEmpty)
                Text(
                  _errorMessage,
                  style: const TextStyle(color: AppColors.error, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isResetting = true;
                    _resetError = '';
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

  // 3. Request Reset View (Step 1 of forgot PIN)
  Widget _buildRequestResetView() {
    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            setState(() {
              _isResetting = false;
              _resetError = '';
            });
          },
        ),
        title: const Text('Reset Edit PIN'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              const Icon(Icons.mark_email_read_outlined, size: 56, color: AppColors.primary),
              const SizedBox(height: 16),
              Text(
                'Email PIN Reset Code',
                style: AppTypography.h2.copyWith(color: context.appTextPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                'We will send a 6-digit reset code to your registered email address to verify your identity.',
                style: TextStyle(color: context.appTextSecondary, height: 1.4),
              ),
              const SizedBox(height: 24),
              if (_resetError.isNotEmpty)
                Text(
                  _resetError,
                  style: const TextStyle(color: AppColors.error, fontSize: 13),
                ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isVerifying ? null : _requestReset,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isVerifying
                      ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                      : const Text('Send Reset Code'),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // 4. Reset Code Confirm View (Step 2 of forgot PIN)
  Widget _buildResetCodeScreen() {
    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            setState(() {
              _showResetCodeScreen = false;
              _isResetting = false;
              _resetError = '';
              _codeController.clear();
              _newPinController.clear();
            });
          },
        ),
        title: const Text('Confirm PIN Reset'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                Text(
                  'Enter Reset Code',
                  style: AppTypography.h2.copyWith(color: context.appTextPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  'A 6-digit code was sent to ${_maskedEmail ?? "your email"}. Enter the code and your new 4-digit PIN below.',
                  style: TextStyle(color: context.appTextSecondary, height: 1.4),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: '6-Digit Reset Code',
                    hintText: '123456',
                    prefixIcon: const Icon(Icons.pin_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _newPinController,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 4,
                  decoration: InputDecoration(
                    labelText: 'New 4-Digit PIN',
                    hintText: '••••',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_resetError.isNotEmpty)
                  Text(
                    _resetError,
                    style: const TextStyle(color: AppColors.error, fontSize: 13),
                  ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isVerifying ? null : _confirmReset,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isVerifying
                        ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                        : const Text('Confirm & Reset PIN'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
