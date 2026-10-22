class WalletData {
  final double balance;
  final double cashLimit;
  final double minimumBalanceForOrders;
  final double availableForOrders;
  final bool isWalletEnabled;
  final bool isTransferEnabled;
  final double minimumTopUpAmount;
  final double minimumTransferAmount;
  final bool isBlocked;

  const WalletData({
    required this.balance,
    required this.cashLimit,
    required this.minimumBalanceForOrders,
    required this.availableForOrders,
    required this.isWalletEnabled,
    required this.isTransferEnabled,
    required this.minimumTopUpAmount,
    required this.minimumTransferAmount,
    required this.isBlocked,
  });

  factory WalletData.fromJson(Map<String, dynamic> json) => WalletData(
        balance: (json['balance'] as num?)?.toDouble() ?? 0,
        cashLimit: (json['cashLimit'] as num?)?.toDouble() ?? 0,
        minimumBalanceForOrders: (json['minimumBalanceForOrders'] as num?)?.toDouble() ?? 0,
        availableForOrders: (json['availableForOrders'] as num?)?.toDouble() ?? 0,
        isWalletEnabled: json['isWalletEnabled'] != false,
        isTransferEnabled: json['isTransferEnabled'] != false,
        minimumTopUpAmount: (json['minimumTopUpAmount'] as num?)?.toDouble() ?? 0,
        minimumTransferAmount: (json['minimumTransferAmount'] as num?)?.toDouble() ?? 0,
        isBlocked: json['isBlocked'] == true,
      );

  static const empty = WalletData(
    balance: 0,
    cashLimit: 0,
    minimumBalanceForOrders: 0,
    availableForOrders: 0,
    isWalletEnabled: true,
    isTransferEnabled: true,
    minimumTopUpAmount: 0,
    minimumTransferAmount: 0,
    isBlocked: false,
  );
}

class WalletTransactionModel {
  final String id;
  final String type;
  final double amount;
  final double balanceAfter;
  final String description;
  final DateTime? createdAt;

  const WalletTransactionModel({
    required this.id,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    required this.description,
    this.createdAt,
  });

  factory WalletTransactionModel.fromJson(Map<String, dynamic> json) => WalletTransactionModel(
        id: (json['_id'] ?? json['id'] ?? '').toString(),
        type: (json['type'] ?? '').toString(),
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        balanceAfter: (json['balanceAfter'] as num?)?.toDouble() ?? 0,
        description: (json['description'] ?? '').toString(),
        createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'].toString()) : null,
      );

  bool get isCredit => amount >= 0;
}

class WithdrawalRequestModel {
  final String id;
  final double amount;
  final String paymentMethod;
  final String status;
  final DateTime? createdAt;

  const WithdrawalRequestModel({
    required this.id,
    required this.amount,
    required this.paymentMethod,
    required this.status,
    this.createdAt,
  });

  factory WithdrawalRequestModel.fromJson(Map<String, dynamic> json) => WithdrawalRequestModel(
        id: (json['_id'] ?? json['id'] ?? '').toString(),
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        paymentMethod: (json['payment_method'] ?? json['paymentMethod'] ?? '').toString(),
        status: (json['status'] ?? 'pending').toString(),
        createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'].toString()) : null,
      );
}

class WalletSnapshot {
  final WalletData wallet;
  final List<WalletTransactionModel> transactions;
  final List<WithdrawalRequestModel> withdrawalRequests;

  const WalletSnapshot({
    required this.wallet,
    required this.transactions,
    required this.withdrawalRequests,
  });

  factory WalletSnapshot.fromJson(Map<String, dynamic> json) => WalletSnapshot(
        wallet: WalletData.fromJson(Map<String, dynamic>.from(json['wallet'] as Map? ?? {})),
        transactions: (json['transactions'] as List? ?? const [])
            .map((e) => WalletTransactionModel.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        withdrawalRequests: (json['withdrawalRequests'] as List? ?? const [])
            .map((e) => WithdrawalRequestModel.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  static const empty = WalletSnapshot(wallet: WalletData.empty, transactions: [], withdrawalRequests: []);
}
