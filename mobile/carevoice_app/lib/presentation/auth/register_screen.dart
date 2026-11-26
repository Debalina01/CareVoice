import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/firebase_service.dart';
import '../../core/localization.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../data/auth_repository.dart';
import '../widgets/pill_button.dart';
import '../widgets/soft_card.dart';
import '../widgets/soft_text_field.dart';
import '../dashboard/dashboard_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _authRepo = AuthRepository();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _initiateRegistrationWithOtp() async {
    final lang = AppLanguage.instance;
    final name = _fullNameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (name.isEmpty) {
      setState(() => _errorMessage = lang.isBengali ? 'অনুগ্রহ করে সম্পূর্ণ নাম লিখুন' : 'Please enter your full name');
      return;
    }

    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    if (!emailRegex.hasMatch(email)) {
      setState(() => _errorMessage = lang.isBengali
          ? 'একটি সঠিক এবং বৈধ ইমেল ঠিকানা লিখুন (যেমন: user@example.com)'
          : 'Please enter a valid email address format (e.g. user@example.com)');
      return;
    }

    if (password.length < 6) {
      setState(() => _errorMessage = lang.isBengali ? 'পাসওয়ার্ড কমপক্ষে ৬ অক্ষরের হতে হবে' : 'Password must be at least 6 characters');
      return;
    }

    if (password != confirmPassword) {
      setState(() => _errorMessage = lang.isBengali ? 'পাসওয়ার্ড দুটি মেলেনি' : 'Passwords do not match');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final isAvailable = await _authRepo.checkEmail(email);
      if (!isAvailable) {
        setState(() {
          _errorMessage = lang.isBengali
              ? 'এই ইমেল ঠিকানাটি ইতিমধ্যে নিবন্ধিত রয়েছে। অনুগ্রহ করে লগইন করুন অথবা অন্য একটি ইমেল দিন।'
              : 'This email address is already registered. Please log in or use a different email address.';
        });
        return;
      }

      final otpResult = await _authRepo.sendOtpDetailed(email: email, purpose: 'Registration');
      if (!mounted) return;

      if (!otpResult.success) {
        _showDeliveryFailedDialog(email, otpResult.message);
        return;
      }

      _showModernOtpDialog(email, otpResult);
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showDeliveryFailedDialog(String email, String failureReason) {
    final lang = AppLanguage.instance;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
        backgroundColor: AppColors.creamLight,
        title: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.missed, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                lang.isBengali ? 'ইমেল পাঠানো ব্যর্থ' : 'Email Delivery Failed',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.ink),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                lang.isBengali
                    ? '$email ঠিকানায় যাচাইকরণ ওটিপি পাঠানো সম্ভব হয়নি।'
                    : 'Could not deliver the verification OTP to $email.',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.ink),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.missed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  border: Border.all(color: AppColors.missed.withValues(alpha: 0.2)),
                ),
                child: Text(
                  failureReason,
                  style: const TextStyle(fontSize: 12, color: AppColors.missed, height: 1.35),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                lang.isBengali
                    ? 'আপনি চাইলে এখনই আপনার যাচাইকরণ কোড লিখতে পারেন অথবা পরে আবার চেষ্টা করতে পারেন।'
                    : 'Please check your internet connection, or tap below to enter your verification code.',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              lang.isBengali ? 'বাতিল' : 'Dismiss',
              style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.bold),
            ),
          ),
          PillButton(
            label: lang.isBengali ? 'কোড লিখুন' : 'Enter Code',
            variant: PillButtonVariant.primary,
            height: 38,
            onPressed: () {
              Navigator.of(ctx).pop();
              _showModernOtpDialog(
                email,
                OtpSendResult(
                  success: true,
                  message: failureReason,
                  isDeliveredViaSmtp: false,
                  deliveryMode: 'ManualEntry',
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showModernOtpDialog(String email, OtpSendResult initialResult) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => ModernOtpVerificationDialog(
        email: email,
        initialResult: initialResult,
        authRepo: _authRepo,
        onVerified: (enteredOtp) async {
          Navigator.of(dialogCtx).pop();
          setState(() => _isLoading = true);
          try {
            final user = await _authRepo.registerWithOtp(
              email: email,
              password: _passwordController.text,
              fullName: _fullNameController.text.trim(),
              phoneNumber: _phoneController.text.trim(),
              role: 'Family Member',
              otp: enteredOtp,
            );

            if (user != null && mounted) {
              try {
                await FirebaseService.instance.syncUserToFirestore(
                  email: user.email,
                  fullName: user.fullName,
                  userId: user.id,
                  role: user.role,
                  phoneNumber: user.phoneNumber,
                );
              } catch (_) {}

              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => DashboardScreen(user: user)),
                  (route) => false,
                );
              }
            }
          } catch (e) {
            setState(() {
              _errorMessage = e.toString().replaceAll('Exception: ', '');
            });
          } finally {
            if (mounted) setState(() => _isLoading = false);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLanguage.instance,
      builder: (context, _) {
        final lang = AppLanguage.instance;

        return Scaffold(
          backgroundColor: AppColors.cream,
          appBar: AppBar(
            backgroundColor: AppColors.cream,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.forest, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              lang.translate('register'),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.forest,
                fontSize: 18,
              ),
            ),
            actions: [
              InkWell(
                onTap: () => lang.toggleLanguage(),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: Container(
                  margin: const EdgeInsets.only(right: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.creamLight,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    boxShadow: AppTokens.clayShadowSm,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.language_rounded, size: 16, color: AppColors.forest),
                      const SizedBox(width: 6),
                      Text(
                        lang.isBengali ? 'English' : 'বাংলা',
                        style: TextStyle(
                          color: AppColors.forest,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: SoftCard(
                  backgroundColor: AppColors.creamLight,
                  radius: AppRadius.card,
                  padding: const EdgeInsets.all(28.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.mint,
                              borderRadius: BorderRadius.circular(AppRadius.control),
                              boxShadow: AppTokens.clayShadowSm,
                            ),
                            child: Icon(Icons.person_add_alt_1_rounded, color: AppColors.forest, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  lang.isBengali ? 'নতুন অ্যাকাউন্ট তৈরি করুন' : 'Create New Account',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.ink,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  lang.isBengali
                                      ? 'ওষুধের সময়সূচী ও পরিবারের স্বাস্থ্য পরিচর্যায় যুক্ত হন'
                                      : 'Connect family care and medicine reminders',
                                  style: TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),

                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.missed.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppRadius.control),
                            border: Border.all(color: AppColors.missed.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline_rounded, color: AppColors.missed, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(color: AppColors.missed, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.3),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],

                      SoftTextField(
                        controller: _fullNameController,
                        labelText: lang.translate('full_name'),
                        hintText: 'e.g. Anirban Mandal',
                        prefixIcon: Icons.badge_rounded,
                      ),
                      const SizedBox(height: 16),

                      SoftTextField(
                        controller: _emailController,
                        labelText: lang.translate('email_address'),
                        hintText: 'user@example.com',
                        helperText: lang.isBengali ? 'এই ইমেলে ভেরিফিকেশন ওটিপি পাঠানো হবে' : 'OTP verification will be sent to this email',
                        prefixIcon: Icons.email_rounded,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 16),

                      SoftTextField(
                        controller: _passwordController,
                        labelText: lang.translate('password'),
                        hintText: '••••••••',
                        prefixIcon: Icons.lock_rounded,
                        obscureText: _obscurePassword,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                            size: 20,
                            color: AppColors.muted,
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      const SizedBox(height: 16),

                      SoftTextField(
                        controller: _confirmPasswordController,
                        labelText: lang.isBengali ? 'পাসওয়ার্ড নিশ্চিত করুন *' : 'Confirm Password *',
                        hintText: '••••••••',
                        prefixIcon: Icons.lock_clock_rounded,
                        obscureText: _obscureConfirmPassword,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirmPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                            size: 20,
                            color: AppColors.muted,
                          ),
                          onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                        ),
                      ),
                      const SizedBox(height: 16),

                      SoftTextField(
                        controller: _phoneController,
                        labelText: lang.translate('phone_number'),
                        hintText: '+91 9876543210',
                        prefixIcon: Icons.phone_rounded,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 26),

                      PillButton(
                        label: (lang.isBengali ? 'ইমেল ওটিপি যাচাই ও নিবন্ধন' : 'Verify Email & Register').toUpperCase(),
                        icon: Icons.send_rounded,
                        variant: PillButtonVariant.primary,
                        height: 50,
                        isLoading: _isLoading,
                        onPressed: _initiateRegistrationWithOtp,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Modernized, Soft Pastel Clay OTP Verification Dialog
class ModernOtpVerificationDialog extends StatefulWidget {
  final String email;
  final OtpSendResult initialResult;
  final AuthRepository? authRepo;
  final Function(String enteredOtp) onVerified;

  const ModernOtpVerificationDialog({
    super.key,
    required this.email,
    required this.initialResult,
    this.authRepo,
    required this.onVerified,
  });

  @override
  State<ModernOtpVerificationDialog> createState() => _ModernOtpVerificationDialogState();
}

class _ModernOtpVerificationDialogState extends State<ModernOtpVerificationDialog> {
  final List<TextEditingController> _pinControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _pinFocusNodes = List.generate(6, (_) => FocusNode());

  late OtpSendResult _currentResult;
  int _resendCooldown = 30;
  Timer? _countdownTimer;
  bool _isResending = false;
  String? _dialogError;

  @override
  void initState() {
    super.initState();
    _currentResult = widget.initialResult;
    _startCountdown();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pinFocusNodes[0].canRequestFocus) {
        _pinFocusNodes[0].requestFocus();
      }
    });
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _resendCooldown = 30;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCooldown > 0) {
        if (mounted) setState(() => _resendCooldown--);
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    for (var c in _pinControllers) {
      c.dispose();
    }
    for (var f in _pinFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _fullPinCode {
    return _pinControllers.map((c) => c.text).join();
  }

  Future<void> _handleResendOtp() async {
    if (_resendCooldown > 0 || _isResending) return;

    setState(() {
      _isResending = true;
      _dialogError = null;
    });

    try {
      final repo = widget.authRepo ?? AuthRepository();
      final res = await repo.sendOtpDetailed(email: widget.email, purpose: 'Registration');
      if (mounted) {
        setState(() {
          _currentResult = res;
          if (res.success) {
            _startCountdown();
            _dialogError = null;
          } else {
            _dialogError = res.message;
          }
        });
        if (res.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.forest,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
              content: Text(
                AppLanguage.instance.isBengali ? 'নতুন ওটিপি পাঠানো হয়েছে' : 'New OTP dispatched to ${widget.email}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _dialogError = e.toString().replaceAll('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = AppLanguage.instance;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.modal)),
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.creamLight,
            borderRadius: BorderRadius.circular(AppRadius.modal),
            boxShadow: AppTokens.clayShadowLg,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: AppColors.mint,
                    shape: BoxShape.circle,
                    boxShadow: AppTokens.clayShadowSm,
                  ),
                  child: Icon(Icons.mark_email_read_rounded, color: AppColors.forest, size: 30),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                lang.isBengali ? 'ইমেল যাচাইকরণ (OTP)' : 'Email Verification (OTP)',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: AppColors.ink,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),

              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.powder.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.alternate_email_rounded, size: 14, color: AppColors.forest),
                      const SizedBox(width: 6),
                      Text(
                        widget.email,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.ink),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _currentResult.success
                      ? AppColors.taken.withValues(alpha: 0.12)
                      : AppColors.missed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  border: Border.all(
                    color: _currentResult.success
                        ? AppColors.taken.withValues(alpha: 0.25)
                        : AppColors.missed.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _currentResult.isDeliveredViaSmtp ? Icons.mark_email_read_rounded : Icons.info_outline_rounded,
                          color: _currentResult.isDeliveredViaSmtp ? AppColors.taken : AppColors.forest,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _currentResult.isDeliveredViaSmtp
                                ? (lang.isBengali
                                    ? 'আপনার ইমেলে একটি গোপন ৬-সংখ্যার যাচাইকরণ কোড পাঠানো হয়েছে। অনুগ্রহ করে ইনবক্স ও স্প্যাম ফোল্ডার পরীক্ষা করুন।'
                                    : 'A confidential 6-digit verification code has been dispatched to your email inbox. Please check your inbox and spam folder.')
                                : _currentResult.message,
                            style: TextStyle(
                              color: _currentResult.isDeliveredViaSmtp ? AppColors.forest : AppColors.ink,
                              fontSize: 12,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(6, (index) {
                  return SizedBox(
                    width: 44,
                    height: 52,
                    child: TextField(
                      controller: _pinControllers[index],
                      focusNode: _pinFocusNodes[index],
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      maxLength: 1,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppColors.ink,
                      ),
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        counterText: '',
                        filled: true,
                        fillColor: AppColors.cream,
                        contentPadding: EdgeInsets.zero,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.control),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.control),
                          borderSide: BorderSide(color: AppColors.sage.withValues(alpha: 0.5)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.control),
                          borderSide: BorderSide(color: AppColors.forest, width: 2),
                        ),
                      ),
                      onChanged: (value) {
                        if (value.isNotEmpty) {
                          if (index < 5) {
                            _pinFocusNodes[index + 1].requestFocus();
                          } else {
                            _pinFocusNodes[index].unfocus();
                          }
                        } else if (value.isEmpty && index > 0) {
                          _pinFocusNodes[index - 1].requestFocus();
                        }
                      },
                    ),
                  );
                }),
              ),
              const SizedBox(height: 14),

              if (_dialogError != null) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.missed.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Text(
                    _dialogError!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.missed, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 10),
              ],

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.timer_outlined, size: 14, color: AppColors.muted),
                      const SizedBox(width: 4),
                      Text(
                        _resendCooldown > 0
                            ? (lang.isBengali ? 'পুনরায় পাঠান: ${_resendCooldown}s' : 'Resend in: ${_resendCooldown}s')
                            : (lang.isBengali ? 'কোড পাননি?' : 'Didn\'t get code?'),
                        style: TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    onPressed: _resendCooldown > 0 || _isResending ? null : _handleResendOtp,
                    icon: _isResending
                        ? SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.forest))
                        : Icon(Icons.refresh_rounded, size: 14, color: AppColors.forest),
                    label: Text(
                      lang.isBengali ? 'কোড পুনরায় পাঠান' : 'Resend OTP',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.forest),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: PillButton(
                      label: lang.translate('cancel'),
                      variant: PillButtonVariant.subtle,
                      height: 44,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: PillButton(
                      label: lang.isBengali ? 'যাচাই ও নিবন্ধন' : 'Verify & Register',
                      variant: PillButtonVariant.primary,
                      height: 44,
                      onPressed: () {
                        final pin = _fullPinCode;
                        if (pin.length < 6) {
                          setState(() {
                            _dialogError = lang.isBengali ? 'অনুগ্রহ করে সম্পূর্ণ ৬-সংখ্যার কোড লিখুন' : 'Please enter the complete 6-digit code';
                          });
                          return;
                        }
                        widget.onVerified(pin);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
