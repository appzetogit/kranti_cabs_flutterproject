import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../core/utils/validators.dart';
import '../application/auth_providers.dart';

class PhoneEntryScreen extends ConsumerStatefulWidget {
  const PhoneEntryScreen({super.key});

  @override
  ConsumerState<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends ConsumerState<PhoneEntryScreen> {
  final _phoneController = TextEditingController();
  final _phoneFocusNode = FocusNode();
  bool _loading = false;
  bool _isFocused = false;
  String? _phoneError;

  @override
  void initState() {
    super.initState();
    _phoneFocusNode.addListener(() {
      if (mounted) {
        setState(() => _isFocused = _phoneFocusNode.hasFocus);
      }
    });
    _phoneController.addListener(() {
      if (mounted) {
        if (_phoneError != null && _phoneController.text.length == 10) {
          setState(() => _phoneError = null);
        } else {
          setState(() {});
        }
      }
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final phone = _phoneController.text.trim();
    final error = Validators.phone(phone);
    if (error != null) {
      setState(() => _phoneError = error);
      return;
    }
    setState(() {
      _phoneError = null;
      _loading = true;
    });
    try {
      await ref.read(authControllerProvider.notifier).sendOtp(phone);
      if (!mounted) return;
      context.push('/auth/otp', extra: phone);
    } catch (error) {
      if (mounted) SnackbarUtils.error(context, error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _phoneFocusNode.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const bgColor = Color(0xFF11191D);
    const cardBgColor = Color(0xFF222222);
    const borderColor = Color(0xFF2E2E2E);
    const goldColor = Color(0xFFF5B400);
    const textSecondary = Color(0xFF94A3B8);
    const errorColor = Color(0xFFEF4444);

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          // Ambient warm top glow
          Positioned(
            top: -70,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 340,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      goldColor.withValues(alpha: 0.16),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 32,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 12),

                          // Brand Logo Container
                          Container(
                            width: 68,
                            height: 68,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: cardBgColor,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: borderColor),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black45,
                                  blurRadius: 14,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Image.asset(
                              'assets/logo.webp',
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Header Typography
                          const Text(
                            'Welcome to',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: textSecondary,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 4),

                          Row(
                            children: [
                              const Text(
                                'KRANTI CABS ',
                                style: TextStyle(
                                  fontSize: 27,
                                  fontWeight: FontWeight.w900,
                                  color: goldColor,
                                  letterSpacing: 0.4,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: goldColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: goldColor.withValues(alpha: 0.4),
                                    width: 1,
                                  ),
                                ),
                                child: const Text(
                                  'USER',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    color: goldColor,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          const Text(
                            'Enter your mobile number to get started with fast & safe rides.',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w400,
                              color: textSecondary,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Feature Highlights Strip
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: cardBgColor,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: borderColor),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _FeaturePill(
                                  icon: Icons.bolt_rounded,
                                  label: 'Quick Ride',
                                  accentColor: goldColor,
                                ),
                                Container(
                                  width: 1,
                                  height: 18,
                                  color: borderColor,
                                ),
                                _FeaturePill(
                                  icon: Icons.verified_user_rounded,
                                  label: 'Verified Drivers',
                                  accentColor: const Color(0xFF10B981),
                                ),
                                Container(
                                  width: 1,
                                  height: 18,
                                  color: borderColor,
                                ),
                                _FeaturePill(
                                  icon: Icons.price_check_rounded,
                                  label: 'Honest Fare',
                                  accentColor: goldColor,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),

                          // Label above input
                          const Padding(
                            padding: EdgeInsets.only(left: 2, bottom: 8),
                            child: Text(
                              'Mobile Number',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFE2E8F0),
                              ),
                            ),
                          ),

                          // Input Card (Fixed height, no distortion on error)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            height: 56,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: cardBgColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _phoneError != null
                                    ? errorColor
                                    : _isFocused
                                        ? goldColor
                                        : borderColor,
                                width: _isFocused || _phoneError != null ? 1.6 : 1.2,
                              ),
                              boxShadow: [
                                if (_isFocused && _phoneError == null)
                                  BoxShadow(
                                    color: goldColor.withValues(alpha: 0.22),
                                    blurRadius: 12,
                                    offset: const Offset(0, 2),
                                  )
                                else if (_phoneError != null)
                                  BoxShadow(
                                    color: errorColor.withValues(alpha: 0.18),
                                    blurRadius: 10,
                                    offset: const Offset(0, 2),
                                  ),
                              ],
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Country Code Pill with India Flag
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      '🇮🇳',
                                      style: TextStyle(fontSize: 18),
                                    ),
                                    const SizedBox(width: 6),
                                    const Text(
                                      '+91',
                                      style: TextStyle(
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 12),

                                // Vertical Divider
                                Container(
                                  width: 1.2,
                                  height: 24,
                                  color: const Color(0xFF383838),
                                ),
                                const SizedBox(width: 12),

                                // Phone Input Field
                                Expanded(
                                  child: TextFormField(
                                    controller: _phoneController,
                                    focusNode: _phoneFocusNode,
                                    keyboardType: TextInputType.phone,
                                    cursorColor: goldColor,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(10),
                                    ],
                                    style: const TextStyle(
                                      fontSize: 16.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      letterSpacing: 1.2,
                                    ),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      hintText: 'Enter 10-digit number',
                                      hintStyle: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w400,
                                        color: Color(0xFF64748B),
                                        letterSpacing: 0.2,
                                      ),
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      errorBorder: InputBorder.none,
                                      focusedErrorBorder: InputBorder.none,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                    onFieldSubmitted: (_) => _submit(),
                                  ),
                                ),

                                // Clear Button if text typed
                                if (_phoneController.text.isNotEmpty)
                                  GestureDetector(
                                    onTap: () {
                                      _phoneController.clear();
                                      setState(() => _phoneError = null);
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 6),
                                      child: Icon(
                                        Icons.cancel_rounded,
                                        color: textSecondary.withValues(alpha: 0.8),
                                        size: 19,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          // Error Message OUTSIDE the card
                          if (_phoneError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8, left: 4),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.error_outline_rounded,
                                    size: 14,
                                    color: errorColor,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _phoneError!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: errorColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 22),

                          // Continue Button
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _loading ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: goldColor,
                                foregroundColor: const Color(0xFF0A0A0A),
                                elevation: 0,
                                shadowColor: goldColor.withValues(alpha: 0.35),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: _loading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        color: Color(0xFF0A0A0A),
                                        strokeWidth: 2.4,
                                      ),
                                    )
                                  : const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'Continue',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF0A0A0A),
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Icon(
                                          Icons.arrow_forward_rounded,
                                          color: Color(0xFF0A0A0A),
                                          size: 19,
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Don't have an account / Register link
                          Center(
                            child: GestureDetector(
                              onTap: _submit,
                              child: RichText(
                                text: const TextSpan(
                                  children: [
                                    TextSpan(
                                      text: "Don't have an account? ",
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w500,
                                        color: textSecondary,
                                      ),
                                    ),
                                    TextSpan(
                                      text: 'Register',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w800,
                                        color: goldColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          const Spacer(),
                          const SizedBox(height: 24),

                          // Trust Badge & Terms Notice at bottom
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.lock_outline_rounded,
                                      size: 13,
                                      color: textSecondary.withValues(alpha: 0.8),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      '100% Secure • Instant OTP Verification',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w500,
                                        color: textSecondary.withValues(alpha: 0.8),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'By continuing, you agree to our Terms of Service & Privacy Policy',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w400,
                                    color: textSecondary.withValues(alpha: 0.6),
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accentColor;

  const _FeaturePill({
    required this.icon,
    required this.label,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: accentColor),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFFCBD5E1),
          ),
        ),
      ],
    );
  }
}
