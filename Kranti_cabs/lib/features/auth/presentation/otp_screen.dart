import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../shared/widgets/otp_field.dart';
import '../application/auth_providers.dart';

class OtpScreen extends ConsumerStatefulWidget {
  final String phone;
  const OtpScreen({super.key, required this.phone});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _otpController = TextEditingController();
  String _otp = '';
  bool _loading = false;
  int _secondsLeft = AppConstants.otpResendCooldown.inSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _secondsLeft = AppConstants.otpResendCooldown.inSeconds;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft == 0) {
        timer.cancel();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  Future<void> _resend() async {
    try {
      await ref.read(authControllerProvider.notifier).sendOtp(widget.phone);
      if (mounted) {
        SnackbarUtils.success(context, 'OTP resent successfully');
        _startTimer();
      }
    } catch (error) {
      if (mounted) SnackbarUtils.error(context, error.toString());
    }
  }

  Future<void> _verify() async {
    if (_otp.length != AppConstants.otpLength) return;
    setState(() => _loading = true);
    try {
      final result = await ref
          .read(authControllerProvider.notifier)
          .verifyOtp(phone: widget.phone, otp: _otp);
      if (!mounted) return;
      if (result.exists) {
        context.go('/home');
      } else {
        context.push('/auth/signup', extra: widget.phone);
      }
    } catch (error) {
      if (mounted) {
        SnackbarUtils.error(context, error.toString());
        _otpController.clear();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF11191D) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight > 32
                    ? constraints.maxHeight - 32
                    : constraints.maxHeight,
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),

                    // Title
                    Text(
                      'Verify OTP',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Subtitle
                    Text(
                      'Enter the 4-digit code sent to +91 ${widget.phone}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // 4-Digit OTP Fields
                    OtpField(
                      controller: _otpController,
                      length: AppConstants.otpLength,
                      onChanged: (value) => setState(() => _otp = value),
                      onCompleted: (value) {
                        _otp = value;
                        _verify();
                      },
                    ),
                    const SizedBox(height: 20),

                    // Resend Timer Row
                    Center(
                      child: _secondsLeft > 0
                          ? Text(
                              'Resend code in 0:${_secondsLeft.toString().padLeft(2, '0')}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: textSecondary,
                              ),
                            )
                          : TextButton(
                              onPressed: _resend,
                              child: const Text(
                                'Resend OTP',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primaryOrange,
                                ),
                              ),
                            ),
                    ),
                    const Spacer(),

                    // Primary Action Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: (_otp.length == AppConstants.otpLength && !_loading)
                            ? _verify
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryOrange,
                          disabledBackgroundColor: AppColors.primaryOrange.withValues(alpha: 0.4),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.2,
                                ),
                              )
                            : const Text(
                                'Verify & Continue',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
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
