import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/empty_state.dart';
import '../application/earnings_providers.dart';
import 'wallet_screen.dart';

class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletAsync = ref.watch(walletSnapshotProvider);

    return Scaffold(
      appBar: const CustomAppBar(title: 'Transactions'),
      body: walletAsync.when(
        data: (snapshot) {
          if (snapshot.transactions.isEmpty) {
            return const EmptyState(icon: Icons.receipt_long_outlined, title: 'No transactions yet');
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(walletSnapshotProvider.future),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: snapshot.transactions.length,
              itemBuilder: (context, index) => TransactionTile(tx: snapshot.transactions[index]),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => const EmptyState(icon: Icons.error_outline, title: 'Could not load transactions'),
      ),
    );
  }
}
