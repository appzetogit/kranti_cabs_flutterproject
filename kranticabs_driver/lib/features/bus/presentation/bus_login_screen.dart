import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../application/bus_auth_providers.dart';
import 'bus_ui.dart';

/// Bus-driver login — phone entry. Sends a `bus_driver` OTP; an unknown number
/// is routed to registration.
class BusLoginScreen extends ConsumerStatefulWidget {
  final String? initialPhone;
  const BusLoginScreen({super.key, this.initialPhone});

  @override
  ConsumerState<BusLoginScreen> createState() => _BusLoginScreenState();
}

class _BusLoginScreenState extends ConsumerState<BusLoginScreen> {
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
      final debugOtp = await ref.read(busAuthProvider.notifier).sendLoginOtp(phone);
      if (!mounted) return;
      context.push('/bus-login-otp', extra: {'phone': phone, 'debugOtp': debugOtp});
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 404) {
        context.push('/bus-register', extra: phone);
        return;
      }
      SnackbarUtils.error(e.message);
    } catch (_) {
      SnackbarUtils.error('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BusScaffold(
      title: 'Bus Partner Login',
      bottomBar: BusBottomBar(actionLabel: 'Send OTP', isLoading: _loading, onPressed: _submit),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        children: [
          const Icon(Icons.directions_bus_rounded, color: BusColors.teal, size: 48),
          const SizedBox(height: 16),
          const Text('Welcome, Bus Partner',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Log in with your registered mobile number to manage your bus.',
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
          const SizedBox(height: 20),
          Center(
            child: GestureDetector(
              onTap: () => context.push('/bus-register', extra: _phone.text.trim()),
              child: RichText(
                text: const TextSpan(children: [
                  TextSpan(
                    text: "Don't have a bus account?  ",
                    style: TextStyle(color: Colors.white, fontSize: 13.5),
                  ),
                  TextSpan(
                    text: 'Register',
                    style: TextStyle(color: BusColors.teal, fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
