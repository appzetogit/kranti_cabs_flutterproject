import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import 'incentive_model.dart';
import 'wallet_model.dart';

/// `{ keyId, orderId, amount, currency }` from the backend. `amount` is in
/// paise; the checkout sheet is handed the rupee figure the driver typed.
class WalletTopupOrder {
  final String keyId;
  final String orderId;
  final String currency;

  const WalletTopupOrder({
    required this.keyId,
    required this.orderId,
    this.currency = 'INR',
  });

  factory WalletTopupOrder.fromJson(Map<String, dynamic> json) {
    return WalletTopupOrder(
      keyId: (json['keyId'] ?? json['key_id'] ?? json['key'] ?? '').toString(),
      orderId: (json['orderId'] ?? json['order_id'] ?? json['id'] ?? '').toString(),
      currency: (json['currency'] ?? 'INR').toString(),
    );
  }
}

class EarningsRepository {
  final ApiClient _api;

  EarningsRepository(this._api);

  Future<WalletSnapshot> getWallet() async {
    final data = await _api.get(ApiConstants.wallet);
    return WalletSnapshot.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// Opens a Razorpay order for a wallet top-up.
  ///
  /// Replaces the old `POST /drivers/wallet/top-up` call, which credited the
  /// wallet with no payment at all — a driver could grant themselves unlimited
  /// balance, and balance gates ride acceptance.
  Future<WalletTopupOrder> createTopupOrder(double amount) async {
    final data = await _api.post(
      ApiConstants.walletTopUpRazorpayOrder,
      data: {'amount': amount},
    );
    return WalletTopupOrder.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// Hands Razorpay's signed result back for server-side verification. The
  /// wallet is only credited once the signature checks out.
  Future<void> verifyTopupPayment(Map<String, dynamic> payload) {
    return _api.post(ApiConstants.walletTopUpRazorpayVerify, data: payload);
  }

  Future<void> requestWithdrawal(double amount, String paymentMethod) {
    return _api.post(ApiConstants.walletWithdrawals, data: {
      'amount': amount,
      'payment_method': paymentMethod,
    });
  }

  Future<IncentiveSnapshot> getIncentives() async {
    final data = await _api.get(ApiConstants.incentives);
    return IncentiveSnapshot.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<void> claimIncentive({required String rewardType, required String rewardKey}) {
    return _api.post(ApiConstants.incentivesClaim, data: {
      'rewardType': rewardType,
      'rewardKey': rewardKey,
    });
  }
}
