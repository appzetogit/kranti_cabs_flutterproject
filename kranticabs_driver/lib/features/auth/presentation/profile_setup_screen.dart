import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/primary_button.dart';
import '../application/signup_providers.dart';

import '../../../shared/widgets/registration_step_progress_bar.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  String _gender = 'male';
  bool _loading = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(signupProvider.notifier).savePersonal(
            fullName: _nameController.text.trim(),
            email: _emailController.text.trim(),
            gender: _gender,
          );
      if (!mounted) return;
      context.push('/location-permission');
    } on ApiException catch (e) {
      SnackbarUtils.error(e.message);
    } catch (_) {
      SnackbarUtils.error('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Create Account', showBack: true),
      bottomNavigationBar: const SafeArea(
        child: RegistrationProgressBar(currentStep: 1),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Text(
                    'Step 1 of 3',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text('Tell us about yourself', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 24),
                AppTextField(
                  controller: _nameController,
                  label: 'Full Name',
                  hint: 'John Doe',
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => Validators.required(v, field: 'Full name'),
                ),
                const SizedBox(height: 18),
                AppTextField(
                  controller: _emailController,
                  label: 'Email Address',
                  hint: 'you@gmail.com',
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => Validators.required(v, field: 'Email') ?? Validators.email(v),
                ),
                const SizedBox(height: 18),
                Text('Gender', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _genderChip('Male', 'male'),
                    const SizedBox(width: 10),
                    _genderChip('Female', 'female'),
                    const SizedBox(width: 10),
                    _genderChip('Other', 'other'),
                  ],
                ),
                const SizedBox(height: 32),
                PrimaryButton(label: 'Continue', onPressed: _submit, loading: _loading),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _genderChip(String label, String value) {
    final selected = _gender == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _gender = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? Theme.of(context).colorScheme.primary : null,
            border: Border.all(
              color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? const Color(0xFF11191D) : Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
