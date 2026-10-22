import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../data/models/wallet_transaction_model.dart';
import '../data/wallet_repository.dart';

final walletRepositoryProvider = Provider<WalletRepository>((ref) {
  return WalletRepository(ref.watch(apiClientProvider));
});

final walletBalanceProvider = FutureProvider.autoDispose<double>((ref) {
  return ref.watch(walletRepositoryProvider).getBalance();
});

final walletTransactionsProvider = FutureProvider.autoDispose<List<WalletTransactionModel>>((ref) {
  return ref.watch(walletRepositoryProvider).getTransactions();
});
