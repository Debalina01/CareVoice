import 'package:flutter/material.dart';
import '../../core/localization.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../data/api_client.dart';
import '../../data/auth_repository.dart';
import '../widgets/pill_button.dart';
import '../widgets/soft_card.dart';
import '../widgets/soft_text_field.dart';
import 'register_screen.dart';
import '../dashboard/dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authRepo = AuthRepository();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _errorMessage = AppLanguage.instance.isBengali ? 'অনুগ্রহ করে আপনার ইমেল ঠিকানা লিখুন' : 'Please enter your email address');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = await _authRepo.login(
        email: email,
        password: _passwordController.text,
      );

      if (user != null && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => DashboardScreen(user: user)),
        );
      }
    } on EmailNotVerifiedException catch (_) {
      if (!mounted) return;
      try {
        final otpResult = await _authRepo.sendOtpDetailed(email: email, purpose: 'LoginVerification');
        if (!mounted) return;
        _showOtpVerificationDialog(email, otpResult);
      } catch (err) {
        setState(() => _errorMessage = err.toString().replaceAll('Exception: ', ''));
      }
    } catch (e) {
      setState(() {
        _errorMessage = ApiClient.friendlyError(
          e,
          fallback: AppLanguage.instance.isBengali
              ? 'লগইন করা যায়নি। অনুগ্রহ করে ইন্টারনেট সংযোগ ও তথ্য পরীক্ষা করে আবার চেষ্টা করুন।'
              : 'Could not sign in right now. Please check your details and internet connection.',
        );
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showOtpVerificationDialog(String email, OtpSendResult initialResult) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ModernOtpVerificationDialog(
        email: email,
        initialResult: initialResult,
        onVerified: (pin) async {
          Navigator.of(ctx).pop();
          setState(() {
            _isLoading = true;
            _errorMessage = null;
          });
          try {
            final verified = await _authRepo.verifyOtp(email: email, otp: pin);
            if (verified && mounted) {
              final user = await _authRepo.login(
                email: email,
                password: _passwordController.text,
              );
              if (user != null && mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => DashboardScreen(user: user)),
                );
              }
            } else {
              setState(() {
                _errorMessage = AppLanguage.instance.isBengali
                    ? 'ওটিপি (OTP) ভুল বা মেয়াদ শেষ হয়ে গেছে'
                    : 'Invalid or expired OTP code';
              });
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
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.sage.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.favorite_rounded, size: 14, color: AppColors.forest),
                                const SizedBox(width: 6),
                                Text(
                                  'CareVoice',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.forest,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: () => lang.toggleLanguage(),
                                borderRadius: BorderRadius.circular(AppRadius.pill),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
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
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      SoftCard(
                        backgroundColor: AppColors.creamLight,
                        radius: AppRadius.card,
                        padding: const EdgeInsets.all(28.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Container(
                                width: 68,
                                height: 68,
                                decoration: BoxDecoration(
                                  color: AppColors.mint,
                                  shape: BoxShape.circle,
                                  boxShadow: AppTokens.clayShadowSm,
                                ),
                                child: Icon(
                                  Icons.medication_liquid_rounded,
                                  size: 36,
                                  color: AppColors.forest,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              lang.translate('app_title'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                color: AppColors.forest,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              lang.translate('app_subtitle'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.muted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 20),

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
                                        style: TextStyle(
                                          color: AppColors.missed,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

                            SoftTextField(
                              controller: _emailController,
                              labelText: lang.translate('email_address'),
                              hintText: 'e.g. name@example.com',
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
                            const SizedBox(height: 24),

                            PillButton(
                              label: lang.translate('log_in').toUpperCase(),
                              icon: Icons.login_rounded,
                              variant: PillButtonVariant.primary,
                              isLoading: _isLoading,
                              height: 50,
                              onPressed: _handleLogin,
                            ),
                            const SizedBox(height: 16),

                            Center(
                              child: TextButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const RegisterScreen()),
                                  );
                                },
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.forest,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                ),
                                child: Text(
                                  lang.isBengali
                                      ? 'অ্যাকাউন্ট নেই? নতুন অ্যাকাউন্ট নিবন্ধন করুন'
                                      : "Don't have an account? Register here",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: AppColors.forest,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
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
