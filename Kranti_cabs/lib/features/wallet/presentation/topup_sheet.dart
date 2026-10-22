import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/services/razorpay_service.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../auth/application/auth_providers.dart';
import '../application/wallet_providers.dart';

const _quickAmounts = [100.0, 200.0, 500.0, 1000.0];

class TopupSheet extends ConsumerStatefulWidget {
  const TopupSheet({super.key});

  @override
  ConsumerState<TopupSheet> createState() => _TopupSheetState();
}

class _TopupSheetState extends ConsumerState<TopupSheet> {
  final _amountController = TextEditingController();
  bool _processing = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _startTopup() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount < 10) {
      SnackbarUtils.error(context, 'Enter a valid amount (min ₹10)');
      return;
    }

    if (_processing) return;
    // Stays true while checkout is open: open() returns straight away, so
    // clearing it in a finally re-enabled the button under the checkout and a
    // second tap started a second top-up. Each outcome below clears it.
    setState(() => _processing = true);
    try {
      final order = await ref.read(walletRepositoryProvider).createTopupOrder(amount);
      final user = ref.read(authControllerProvider).user;

      ref.read(razorpayServiceProvider).open(
            request: RazorpayCheckoutRequest(
              keyId: order.keyId,
              orderId: order.orderId,
              amount: amount,
              name: 'Wallet top-up',
              description: 'Add money to wallet',
              contact: user?.phone,
              email: user?.email,
            ),
            onSuccess: (PaymentSuccessResponse response) async {
              try {
                await ref.read(walletRepositoryProvider).verifyTopupPayment({
                  'razorpay_payment_id': response.paymentId,
                  'razorpay_order_id': response.orderId,
                  'razorpay_signature': response.signature,
                });
                ref.invalidate(walletBalanceProvider);
                ref.invalidate(walletTransactionsProvider);
                if (mounted) {
                  setState(() => _processing = false);
                  Navigator.of(context).pop();
                  SnackbarUtils.success(context, 'Wallet topped up successfully');
                }
              } catch (e) {
                if (mounted) {
                  SnackbarUtils.error(context, 'Payment verification failed');
                  setState(() => _processing = false);
                }
              }
            },
            onError: (PaymentFailureResponse response) {
              if (!mounted) return;
              SnackbarUtils.error(context, response.message ?? 'Payment failed');
              setState(() => _processing = false);
            },
          );
    } catch (e) {
      if (mounted) {
        SnackbarUtils.error(
          context,
          e is ApiException ? e.message : 'Could not start payment',
        );
        setState(() => _processing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Add money', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        AppTextField(
          controller: _amountController,
          label: 'Amount',
          hint: 'Enter amount',
          prefixIcon: Icons.currency_rupee_rounded,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          children: _quickAmounts
              .map(
                (amount) => ActionChip(
                  label: Text('₹${amount.toInt()}'),
                  onPressed: () => _amountController.text = amount.toInt().toString(),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 24),
        PrimaryButton(label: 'Proceed to pay', isLoading: _processing, onPressed: _startTopup),
      ],
    );
  }
}
