import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/primary_button.dart';
import '../application/earnings_providers.dart';
import '../data/wallet_model.dart';

class WithdrawScreen extends ConsumerStatefulWidget {
  const WithdrawScreen({super.key});

  @override
  ConsumerState<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends ConsumerState<WithdrawScreen> {
  final _amountController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _submit(WalletData wallet) async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      SnackbarUtils.error('Enter a valid amount');
      return;
    }
    if (amount > wallet.balance) {
      SnackbarUtils.error('Amount cannot exceed wallet balance');
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(earningsRepositoryProvider).requestWithdrawal(amount, 'bank_transfer');
      ref.invalidate(walletSnapshotProvider);
      _amountController.clear();
      if (mounted) SnackbarUtils.success('Withdrawal request sent to admin');
    } on ApiException catch (e) {
      if (mounted) SnackbarUtils.error(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final walletAsync = ref.watch(walletSnapshotProvider);

    return Scaffold(
      appBar: const CustomAppBar(title: 'Withdraw / Settlement'),
      body: walletAsync.when(
        data: (snapshot) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Available balance', style: TextStyle(color: AppColors.lightTextSecondary)),
                  Text(
                    snapshot.wallet.balanceText,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.primaryDark),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            AppTextField(
              controller: _amountController,
              label: 'Withdrawal amount (₹)',
              hint: snapshot.wallet.minimumTransferAmount > 0
                  ? 'Minimum ₹${snapshot.wallet.minimumTransferAmount.toStringAsFixed(0)}'
                  : 'Enter amount',
              keyboardType: TextInputType.number,
              enabled: snapshot.wallet.isTransferEnabled,
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Request Withdrawal',
              onPressed: snapshot.wallet.isTransferEnabled ? () => _submit(snapshot.wallet) : null,
              loading: _busy,
            ),
            if (!snapshot.wallet.isTransferEnabled) ...[
              const SizedBox(height: 8),
              const Text(
                'Withdrawals are currently disabled by admin.',
                style: TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ],
            const SizedBox(height: 28),
            Text('Withdrawal history', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (snapshot.withdrawalRequests.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: EmptyState(icon: Icons.history, title: 'No withdrawal requests yet'),
              )
            else
              ...snapshot.withdrawalRequests.map((request) => _WithdrawalTile(request: request)),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => const EmptyState(icon: Icons.error_outline, title: 'Could not load wallet'),
      ),
    );
  }
}

class _WithdrawalTile extends StatelessWidget {
  final WithdrawalRequestModel request;

  const _WithdrawalTile({required this.request});

  Color _statusColor() {
    switch (request.status.toLowerCase()) {
      case 'approved':
      case 'completed':
        return AppColors.success;
      case 'rejected':
        return AppColors.error;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.lightBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('₹${request.amount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                if (request.createdAt != null)
                  Text(
                    '${request.createdAt!.day}/${request.createdAt!.month}/${request.createdAt!.year}',
                    style: const TextStyle(color: AppColors.lightTextSecondary, fontSize: 12),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _statusColor().withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              request.status,
              style: TextStyle(color: _statusColor(), fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
