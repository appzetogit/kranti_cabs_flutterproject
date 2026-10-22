import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../auth/application/auth_providers.dart';
import '../application/profile_providers.dart';

class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _reasonController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reasonController.text.trim().isEmpty) {
      SnackbarUtils.error('Please tell us why you want to delete your account');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This will permanently delete your driver account and all associated data. This action cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (!mounted) return;
    setState(() => _submitting = true);
    try {
      await ref.read(profileRepositoryProvider).requestAccountDeletion(_reasonController.text.trim());
      await ref.read(authProvider.notifier).logout();
      if (mounted) {
        SnackbarUtils.success('Account deletion requested');
        context.go('/welcome');
      }
    } on ApiException catch (e) {
      if (mounted) SnackbarUtils.error(e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Delete Account'),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Deleting your account is permanent. Your ride history, earnings and documents will be removed.',
                    style: TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppTextField(
            controller: _reasonController,
            label: 'Reason for leaving',
            hint: 'Tell us why you want to delete your account',
            maxLines: 4,
          ),
          const SizedBox(height: 28),
          PrimaryButton(
            label: 'Delete My Account',
            onPressed: _submit,
            loading: _submitting,
            color: AppColors.error,
          ),
        ],
      ),
    );
  }
}
