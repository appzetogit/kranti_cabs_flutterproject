import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/custom_bottom_sheet.dart';
import '../../../shared/widgets/empty_state.dart';
import '../application/wallet_providers.dart';
import 'topup_sheet.dart';

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(walletBalanceProvider);
    final transactionsAsync = ref.watch(walletTransactionsProvider);

    return Scaffold(
      appBar: const CustomAppBar(title: 'Wallet', showBack: true),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(walletBalanceProvider);
          ref.invalidate(walletTransactionsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: AppColors.primaryGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Wallet balance', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 8),
                  balanceAsync.when(
                    data: (balance) => Text(
                      Formatters.currency(balance),
                      style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800),
                    ),
                    loading: () => const SizedBox(
                      height: 32,
                      width: 32,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    ),
                    error: (_, _) => const Text('—', style: TextStyle(color: Colors.white, fontSize: 32)),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primary,
                      ),
                      onPressed: () => CustomBottomSheet.show(context, child: const TopupSheet()),
                      child: const Text('Add money'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Recent transactions', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            transactionsAsync.when(
              data: (transactions) => transactions.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: 'No transactions yet',
                        message: 'Your wallet activity will show up here.',
                      ),
                    )
                  : Column(
                      children: transactions
                          .map(
                            (tx) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor:
                                    (tx.isCredit ? AppColors.success : AppColors.error).withValues(alpha: 0.1),
                                child: Icon(
                                  tx.isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                                  color: tx.isCredit ? AppColors.success : AppColors.error,
                                ),
                              ),
                              title: Text(tx.description),
                              subtitle: Text(Formatters.dateTime(tx.createdAt)),
                              trailing: Text(
                                '${tx.isCredit ? '+' : '-'}${Formatters.currency(tx.amount)}',
                                style: TextStyle(
                                  color: tx.isCredit ? AppColors.success : AppColors.error,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, _) => const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Could not load transactions',
                  message: 'Please check your connection and try again.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
