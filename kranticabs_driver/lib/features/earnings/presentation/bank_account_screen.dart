import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/data/driver_model.dart';

class BankAccountScreen extends ConsumerStatefulWidget {
  const BankAccountScreen({super.key});

  @override
  ConsumerState<BankAccountScreen> createState() => _BankAccountScreenState();
}

class _BankAccountScreenState extends ConsumerState<BankAccountScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _accountController;
  late final TextEditingController _ifscController;
  late final TextEditingController _branchController;
  late final TextEditingController _upiController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final bank = ref.read(authProvider).driver?.bankDetails ?? BankDetails.empty;
    _nameController = TextEditingController(text: bank.accountHolderName);
    _accountController = TextEditingController(text: bank.accountNumber);
    _ifscController = TextEditingController(text: bank.ifsc);
    _branchController = TextEditingController(text: bank.branchName);
    _upiController = TextEditingController(text: bank.upiId);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _accountController.dispose();
    _ifscController.dispose();
    _branchController.dispose();
    _upiController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(authRepositoryProvider).updateBankDetails(BankDetails(
            accountHolderName: _nameController.text.trim(),
            accountNumber: _accountController.text.trim(),
            ifsc: _ifscController.text.trim(),
            branchName: _branchController.text.trim(),
            upiId: _upiController.text.trim(),
          ));
      await ref.read(authProvider.notifier).refresh();
      if (mounted) SnackbarUtils.success('Bank details saved');
    } on ApiException catch (e) {
      if (mounted) SnackbarUtils.error(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bank = ref.watch(authProvider).driver?.bankDetails ?? BankDetails.empty;

    return Scaffold(
      appBar: const CustomAppBar(title: 'Bank Account'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (bank.hasDetails)
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: (bank.isVerified ? AppColors.success : AppColors.warning).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    bank.isVerified ? Icons.verified_outlined : Icons.hourglass_top_outlined,
                    color: bank.isVerified ? AppColors.success : AppColors.warning,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    bank.isVerified ? 'Bank details verified' : 'Verification pending',
                    style: TextStyle(
                      color: bank.isVerified ? AppColors.success : AppColors.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          AppTextField(controller: _nameController, label: 'Account holder name', hint: 'Full name on account'),
          const SizedBox(height: 16),
          AppTextField(
            controller: _accountController,
            label: 'Account number',
            hint: 'Bank account number',
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          AppTextField(controller: _ifscController, label: 'IFSC code', hint: 'e.g. HDFC0001234'),
          const SizedBox(height: 16),
          AppTextField(controller: _branchController, label: 'Branch name', hint: 'Bank branch'),
          const SizedBox(height: 16),
          AppTextField(controller: _upiController, label: 'UPI ID (optional)', hint: 'name@upi'),
          const SizedBox(height: 24),
          PrimaryButton(label: 'Save Bank Details', onPressed: _save, loading: _saving),
        ],
      ),
    );
  }
}
