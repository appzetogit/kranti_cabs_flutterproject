import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/primary_button.dart';
import '../application/signup_providers.dart';

class SignupPhoneScreen extends ConsumerStatefulWidget {
  /// Pre-fills the number when the driver arrived from the login screen after
  /// typing a number that has no account yet, so they do not type it twice.
  final String? initialPhone;

  const SignupPhoneScreen({super.key, this.initialPhone});

  @override
  ConsumerState<SignupPhoneScreen> createState() => _SignupPhoneScreenState();
}

class _SignupPhoneScreenState extends ConsumerState<SignupPhoneScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _phoneController =
      TextEditingController(text: widget.initialPhone ?? '');
  bool _loading = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final phone = _phoneController.text.trim();
      final loginMode = await ref.read(signupProvider.notifier).sendOtp(phone);
      if (!mounted) return;
      if (loginMode) {
        SnackbarUtils.info('An account already exists for this number. Please login instead.');
        context.push('/login');
      } else {
        context.push('/signup-otp');
      }
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
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Create Account', showBack: true),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Join as a driver', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  'Enter your mobile number to get started',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 32),
                AppTextField(
                  controller: _phoneController,
                  label: 'Mobile Number',
                  hint: '9876543210',
                  keyboardType: TextInputType.phone,
                  validator: Validators.phone,
                  maxLength: AppConstants.phoneLength,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  prefixIcon: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: Center(
                      widthFactor: 1,
                      child: Text('+91', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.lightTextPrimary)),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                PrimaryButton(label: 'Send OTP', onPressed: _submit, loading: _loading),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
