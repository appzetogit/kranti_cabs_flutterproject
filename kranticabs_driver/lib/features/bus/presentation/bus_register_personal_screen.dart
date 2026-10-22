import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/snackbar_utils.dart';
import '../application/bus_onboarding_providers.dart';
import 'bus_ui.dart';

/// Step 3 of registration — the driver's personal details.
class BusRegisterPersonalScreen extends ConsumerStatefulWidget {
  const BusRegisterPersonalScreen({super.key});

  @override
  ConsumerState<BusRegisterPersonalScreen> createState() => _BusRegisterPersonalScreenState();
}

class _BusRegisterPersonalScreenState extends ConsumerState<BusRegisterPersonalScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  String _gender = 'Male';
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  bool _isEmail(String s) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    if (name.isEmpty) {
      SnackbarUtils.error('Enter your full name');
      return;
    }
    if (!_isEmail(email)) {
      SnackbarUtils.error('Enter a valid email');
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(busOnboardingProvider.notifier).savePersonal(
            fullName: name,
            email: email,
            gender: _gender,
          );
      if (!mounted) return;
      context.push('/bus-register-bus');
    } catch (_) {
      if (!mounted) return;
      SnackbarUtils.error('Could not save details. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BusScaffold(
      title: 'Your Details',
      bottomBar: BusBottomBar(actionLabel: 'Continue', isLoading: _loading, onPressed: _submit),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        children: [
          BusField(controller: _name, label: 'Full Name', hint: 'Your name', icon: Icons.person_rounded),
          const SizedBox(height: 16),
          BusField(
            controller: _email,
            label: 'Email',
            hint: 'you@example.com',
            icon: Icons.email_rounded,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          const Text('Gender',
              style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: ['Male', 'Female', 'Other'].map((g) {
              final active = _gender == g;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _gender = g),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active ? BusColors.tealDark : BusColors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: active ? BusColors.teal : BusColors.border),
                      ),
                      child: Text(g,
                          style: TextStyle(
                              color: active ? BusColors.teal : BusColors.textMuted,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
