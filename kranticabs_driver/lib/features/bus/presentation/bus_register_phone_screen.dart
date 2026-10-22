import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../application/bus_onboarding_providers.dart';
import 'bus_ui.dart';

/// Step 1 of bus-driver registration — phone + OTP request.
class BusRegisterPhoneScreen extends ConsumerStatefulWidget {
  final String? initialPhone;
  const BusRegisterPhoneScreen({super.key, this.initialPhone});

  @override
  ConsumerState<BusRegisterPhoneScreen> createState() => _BusRegisterPhoneScreenState();
}

class _BusRegisterPhoneScreenState extends ConsumerState<BusRegisterPhoneScreen> {
  late final TextEditingController _phone =
      TextEditingController(text: widget.initialPhone ?? '');
  bool _loading = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final phone = _phone.text.trim();
    if (phone.length < AppConstants.phoneLength) {
      SnackbarUtils.error('Enter a valid mobile number');
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await ref.read(busOnboardingProvider.notifier).startOtp(phone);
      if (!mounted) return;
      if (result.loginMode) {
        // Phone already has a bus account — the backend sent a login OTP.
        SnackbarUtils.info('You already have an account — logging you in');
        context.pushReplacement('/bus-login-otp', extra: {'phone': phone, 'debugOtp': result.debugOtp});
        return;
      }
      context.push('/bus-register-otp', extra: {'phone': phone, 'debugOtp': result.debugOtp});
    } catch (e) {
      if (!mounted) return;
      SnackbarUtils.error('Could not send OTP. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BusScaffold(
      title: 'Bus Partner Registration',
      bottomBar: BusBottomBar(actionLabel: 'Send OTP', isLoading: _loading, onPressed: _submit),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        children: [
          const Icon(Icons.directions_bus_rounded, color: BusColors.teal, size: 48),
          const SizedBox(height: 16),
          const Text('Register your bus',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Join an existing bus or add your own. We verify your number first.',
              style: TextStyle(color: BusColors.textMuted, fontSize: 14)),
          const SizedBox(height: 28),
          BusCard(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                const Icon(Icons.call_outlined, color: BusColors.textMuted, size: 20),
                const SizedBox(width: 10),
                const Text('+91',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(AppConstants.phoneLength),
                    ],
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 16),
                      border: InputBorder.none,
                      hintText: 'Enter mobile number',
                      hintStyle: TextStyle(color: BusColors.textMuted, fontWeight: FontWeight.w400),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
