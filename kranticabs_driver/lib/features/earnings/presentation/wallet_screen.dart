import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/services/razorpay_service.dart';
import '../../auth/application/auth_providers.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/primary_button.dart';
import '../application/earnings_providers.dart';
import '../data/wallet_model.dart';

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  bool _busy = false;

  Future<void> _topUp(WalletData wallet) async {
    final controller = TextEditingController();
    final amount = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 20 + MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add money to wallet', style: Theme.of(sheetContext).textTheme.titleMedium),
            const SizedBox(height: 4),
            if (wallet.minimumTopUpAmount > 0)
              Text(
                'Minimum ₹${wallet.minimumTopUpAmount.toStringAsFixed(0)}',
                style: const TextStyle(color: AppColors.lightTextSecondary, fontSize: 12),
              ),
            const SizedBox(height: 16),
            AppTextField(
              controller: controller,
              label: 'Amount (₹)',
              hint: 'Enter amount',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Add Money',
              onPressed: () {
                final value = double.tryParse(controller.text.trim());
                Navigator.pop(sheetContext, value);
              },
            ),
          ],
        ),
      ),
    );

    if (amount == null || amount <= 0) return;

    if (wallet.minimumTopUpAmount > 0 && amount < wallet.minimumTopUpAmount) {
      SnackbarUtils.error(
        'Minimum top-up is Rs ${wallet.minimumTopUpAmount.toStringAsFixed(0)}',
      );
      return;
    }

    if (!mounted) return;
    setState(() => _busy = true);
    try {
      // Order first: the backend creates the Razorpay order and returns the
      // key, so the app never holds gateway credentials.
      final order = await ref.read(earningsRepositoryProvider).createTopupOrder(amount);
      final driver = ref.read(authProvider).driver;

      ref.read(razorpayServiceProvider).open(
            request: RazorpayCheckoutRequest(
              keyId: order.keyId,
              orderId: order.orderId,
              // Rupees — the service converts to paise. Passing the order's
              // `amount` (already paise) would charge 100x.
              amount: amount,
              name: 'Wallet top-up',
              description: 'Add money to driver wallet',
              contact: driver?.phone,
              email: driver?.email,
            ),
            onSuccess: (PaymentSuccessResponse response) async {
              try {
                // The wallet is credited only after the server verifies the
                // signature — never optimistically on the client.
                await ref.read(earningsRepositoryProvider).verifyTopupPayment({
                  'razorpay_payment_id': response.paymentId,
                  'razorpay_order_id': response.orderId,
                  'razorpay_signature': response.signature,
                });
                ref.invalidate(walletSnapshotProvider);
                if (mounted) SnackbarUtils.success('Wallet topped up');
              } on ApiException catch (e) {
                if (mounted) {
                  SnackbarUtils.error('Payment taken but not confirmed: ${e.message}');
                }
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
            onError: (PaymentFailureResponse response) {
              if (mounted) {
                SnackbarUtils.error(response.message ?? 'Payment failed or was cancelled');
                setState(() => _busy = false);
              }
            },
          );
    } on ApiException catch (e) {
      if (mounted) {
        SnackbarUtils.error(e.message);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final walletAsync = ref.watch(walletSnapshotProvider);

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Wallet',
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance_outlined),
            onPressed: () => context.push('/bank-account'),
          ),
        ],
      ),
      body: walletAsync.when(
        data: (snapshot) => RefreshIndicator(
          onRefresh: () => ref.refresh(walletSnapshotProvider.future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: AppColors.earningsGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Wallet balance', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 6),
                    Text(
                      // "-₹120" when the driver owes commission; tinted so a
                      // debt never reads as money in hand.
                      snapshot.wallet.balanceText,
                      style: TextStyle(
                        color: snapshot.wallet.balance < 0 ? const Color(0xFFFFCDD2) : Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (snapshot.wallet.isBlocked || snapshot.wallet.owed > 0) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _walletNotice(snapshot.wallet),
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: PrimaryButton(
                      label: 'Add Money',
                      onPressed: snapshot.wallet.isWalletEnabled ? () => _topUp(snapshot.wallet) : null,
                      loading: _busy,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PrimaryButton(
                      label: 'Withdraw',
                      color: AppColors.accent,
                      onPressed: snapshot.wallet.isTransferEnabled ? () => context.push('/withdraw') : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.push('/transactions'),
                child: const Text('View all transactions'),
              ),
              const SizedBox(height: 8),
              Text('Recent activity', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (snapshot.transactions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('No transactions yet', style: TextStyle(color: AppColors.lightTextSecondary)),
                  ),
                )
              else
                ...snapshot.transactions.take(8).map((tx) => TransactionTile(tx: tx)),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text('Could not load wallet', style: Theme.of(context).textTheme.bodyMedium),
        ),
      ),
    );
  }
}

/// The line under the balance: what to top up when rides are blocked, else
/// what is owed and how much more the driver may owe before they are.
String _walletNotice(WalletData wallet) {
  if (wallet.isBlocked) {
    final topUp = wallet.topUpToGetRides;
    return topUp > 0
        ? 'Top up ${formatSignedRupees(topUp)} to get rides again'
        : 'Top up to keep accepting rides';
  }
  final limit = wallet.creditLimit;
  return limit > 0
      ? 'You owe ${formatSignedRupees(wallet.owed)} commission from cash rides. '
          'Rides continue until you owe ${formatSignedRupees(limit)} - top up to clear it.'
      : 'You owe ${formatSignedRupees(wallet.owed)} commission from cash rides - top up to clear it.';
}

class TransactionTile extends StatelessWidget {
  final WalletTransactionModel tx;

  const TransactionTile({super.key, required this.tx});

  @override
  Widget build(BuildContext context) {
    final isCredit = tx.isCredit;
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
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (isCredit ? AppColors.success : AppColors.error).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCredit ? Icons.arrow_downward : Icons.arrow_upward,
              color: isCredit ? AppColors.success : AppColors.error,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.description.isEmpty ? tx.type : tx.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                if (tx.createdAt != null)
                  Text(
                    '${tx.createdAt!.day}/${tx.createdAt!.month}/${tx.createdAt!.year}',
                    style: const TextStyle(color: AppColors.lightTextSecondary, fontSize: 12),
                  ),
              ],
            ),
          ),
          Text(
            '${isCredit ? '+' : '-'}₹${tx.amount.abs().toStringAsFixed(0)}',
            style: TextStyle(
              color: isCredit ? AppColors.success : AppColors.error,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
