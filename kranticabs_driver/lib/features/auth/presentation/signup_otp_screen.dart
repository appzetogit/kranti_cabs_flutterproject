import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterdriver/core/theme/app_colors.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/otp_field.dart';
import '../../../shared/widgets/primary_button.dart';
import '../application/signup_providers.dart';

class SignupOtpScreen extends ConsumerStatefulWidget {
  const SignupOtpScreen({super.key});

  @override
  ConsumerState<SignupOtpScreen> createState() => _SignupOtpScreenState();
}

class _SignupOtpScreenState extends ConsumerState<SignupOtpScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  bool _resending = false;
  int _secondsLeft = AppConstants.otpResendCooldown.inSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = AppConstants.otpResendCooldown.inSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft -= 1);
      }
    });
  }

  Future<void> _verify([String? code]) async {
    final otp = code ?? _controller.text.trim();
    if (otp.length != AppConstants.otpLength) return;
    setState(() => _loading = true);
    try {
      await ref.read(signupProvider.notifier).verifyOtp(otp);
      if (!mounted) return;
      context.push('/signup-profile');
    } on ApiException catch (e) {
      SnackbarUtils.error(e.message);
      _controller.clear();
    } catch (_) {
      SnackbarUtils.error('Verification failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    try {
      final phone = ref.read(signupProvider).phone;
      await ref.read(signupProvider.notifier).sendOtp(phone);
      _startTimer();
      if (mounted) SnackbarUtils.success('OTP resent successfully');
    } on ApiException catch (e) {
      SnackbarUtils.error(e.message);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phone = ref.watch(signupProvider).phone;

    return Scaffold(
      backgroundColor: const Color(0xFF11191D),
      appBar: const CustomAppBar(title: '', showBack: true),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Verify your number', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                'Enter the ${AppConstants.otpLength}-digit code sent to +91 $phone',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 32),
              OtpFieldWidget(
                controller: _controller,
                length: AppConstants.otpLength,
                onCompleted: _verify,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Text(
                    _secondsLeft > 0 ? 'Resend OTP in $_secondsLeft s' : "Didn't receive the code?",
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (_secondsLeft == 0) ...[
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: _resending ? null : _resend,
                      child: Text(
                        'Resend',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 32),
              PrimaryButton(
                label: 'Verify',
                onPressed: () => _verify(),
                loading: _loading,
                color: AppColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
