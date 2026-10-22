import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_exception.dart';
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
      final driver = await ref.read(authProvider.notifier).verifyOtp(widget.phone, otp);
      if (!mounted) return;
      if (!driver.isApproved) {
        context.go('/verification-pending');
      } else {
        context.go('/home');
      }
    } on ApiException catch (e) {
      SnackbarUtils.error(e.message);
      _controller.clear();
    } catch (_) {
      SnackbarUtils.error('auth.verify_failed'.tr());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    try {
      await ref.read(authProvider.notifier).sendOtp(widget.phone);
      _startTimer();
      if (mounted) SnackbarUtils.success('auth.otp_resent'.tr());
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
    const bgColor = Color(0xFF11191D);
    const textPrimary = Colors.white;
    const textSecondary = Color(0xFF94A3B8);
    final timerFormatted = '00:${_secondsLeft.toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
         // physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Hero Illustration (assets/otp.webp)
              Center(
                child: Image.asset(
                  'assets/otp.webp',
                  height: 180,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const SizedBox(height: 120),
                ),
              ),
              const SizedBox(height: 24),

              // Title
              Text(
                'auth.otp_title'.tr(),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),

              // Subtitle
              Text(
                'auth.otp_subtitle'.tr(namedArgs: {
                  'n': '${AppConstants.otpLength}',
                  'phone': widget.phone,
                }),
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),

              // 4-Digit OTP Boxes
              OtpFieldWidget(
                controller: _controller,
                length: AppConstants.otpLength,
                onCompleted: _verify,
              ),
              const SizedBox(height: 24),

              // Resend Code Row
              Center(
                child: _secondsLeft > 0
                    ? RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: textSecondary,
                          ),
                          children: [
                            TextSpan(text: 'auth.didnt_receive'.tr()),
                            TextSpan(
                              text: 'auth.resend_in'.tr(namedArgs: {'time': timerFormatted}),
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      )
                    : InkWell(
                        onTap: _resending ? null : _resend,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Text(
                            'auth.resend_code'.tr(),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 36),

              // Primary Action Button (Verify) in #12DEDC Primary Theme Color
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: !_loading ? () => _verify() : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.black,
                            strokeWidth: 2.4,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'auth.verify'.tr(),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.black,
                              size: 20,
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
