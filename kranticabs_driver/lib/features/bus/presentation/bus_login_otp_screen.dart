import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../shared/widgets/otp_field.dart';
import '../application/bus_auth_providers.dart';
import '../data/models/bus_driver_models.dart';
import 'bus_ui.dart';

/// Verifies the bus-driver login OTP and routes to the operate home or the
/// pending screen based on approval.
class BusLoginOtpScreen extends ConsumerStatefulWidget {
  final String phone;
  final String? debugOtp;
  const BusLoginOtpScreen({super.key, required this.phone, this.debugOtp});

  @override
  ConsumerState<BusLoginOtpScreen> createState() => _BusLoginOtpScreenState();
}

class _BusLoginOtpScreenState extends ConsumerState<BusLoginOtpScreen> {
  final _otp = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _otp.dispose();
    super.dispose();
  }

  Future<void> _verify(String otp) async {
    if (_loading) return;
    if (otp.length < AppConstants.otpLength) return;
    setState(() => _loading = true);
    try {
      final profile = await ref.read(busAuthProvider.notifier).loginWithOtp(widget.phone, otp);
      if (!mounted) return;
      _routeFor(profile);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackbarUtils.error('Invalid or expired OTP. Please try again.');
    }
  }

  void _routeFor(BusDriverProfile profile) {
    context.go(profile.canOperate ? '/bus-home' : '/bus-pending');
  }

  Future<void> _resend() async {
    try {
      await ref.read(busAuthProvider.notifier).sendLoginOtp(widget.phone);
      SnackbarUtils.success('OTP sent again');
    } catch (_) {
      SnackbarUtils.error('Could not resend OTP');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BusScaffold(
      title: 'Verify OTP',
      bottomBar: BusBottomBar(
        actionLabel: 'Verify',
        isLoading: _loading,
        onPressed: () => _verify(_otp.text.trim()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
        children: [
          const Text('Enter the code',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Sent to +91 ${widget.phone}',
              style: const TextStyle(color: BusColors.textMuted, fontSize: 14)),
          if (widget.debugOtp != null && widget.debugOtp!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Test OTP: ${widget.debugOtp}',
                style: const TextStyle(color: BusColors.teal, fontSize: 13, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 28),
          OtpFieldWidget(
            controller: _otp,
            length: AppConstants.otpLength,
            onCompleted: _verify,
          ),
          const SizedBox(height: 20),
          Center(
            child: TextButton(
              onPressed: _resend,
              child: const Text('Resend OTP', style: TextStyle(color: BusColors.teal)),
            ),
          ),
        ],
      ),
    );
  }
}
