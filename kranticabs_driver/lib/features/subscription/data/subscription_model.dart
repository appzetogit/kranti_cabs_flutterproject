/// One plan a driver can buy — usually just one for their vehicle class,
/// several when the admin has switched the city to `driver_choice`.
///
/// Amount and description come straight from the backend; the admin can
/// change the price at any time, so nothing here is hardcoded.
class SubscriptionPlan {
  final String id;
  final String name;
  final double amount;
  final List<String> vehicleClasses;
  final String description;
  final String howItWorks;

  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.amount,
    required this.vehicleClasses,
    required this.description,
    required this.howItWorks,
  });

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlan(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      amount: _toDouble(json['amount']),
      vehicleClasses: _toStringList(json['vehicleClasses']),
      description: (json['description'] ?? '').toString(),
      howItWorks: (json['howItWorks'] ?? '').toString(),
    );
  }
}

/// The driver's currently purchased pass, whether still active or expired.
class ActiveSubscription {
  final String id;
  final String planName;
  final double amount;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final String paymentMethod;
  final List<String> vehicleClasses;

  const ActiveSubscription({
    required this.id,
    required this.planName,
    required this.amount,
    this.startsAt,
    this.expiresAt,
    required this.paymentMethod,
    required this.vehicleClasses,
  });

  factory ActiveSubscription.fromJson(Map<String, dynamic> json) {
    return ActiveSubscription(
      id: (json['id'] ?? '').toString(),
      planName: (json['planName'] ?? '').toString(),
      amount: _toDouble(json['amount']),
      startsAt: _toDate(json['startsAt']),
      expiresAt: _toDate(json['expiresAt']),
      paymentMethod: (json['paymentMethod'] ?? '').toString(),
      vehicleClasses: _toStringList(json['vehicleClasses']),
    );
  }
}

class SubscriptionCycle {
  final DateTime? startsAt;
  final DateTime? expiresAt;

  const SubscriptionCycle({this.startsAt, this.expiresAt});

  factory SubscriptionCycle.fromJson(Map<String, dynamic> json) {
    return SubscriptionCycle(
      startsAt: _toDate(json['startsAt']),
      expiresAt: _toDate(json['expiresAt']),
    );
  }
}

/// `GET /drivers/subscription` — everything the screen needs in one call.
///
/// [expiresAt] is shown as-is; the app never computes it — the 6 AM cutover
/// hour is an admin setting on the backend and can change.
class SubscriptionStatus {
  final bool enabled;
  final bool isRequired;
  final String status;
  final DateTime? expiresAt;
  final SubscriptionCycle? currentCycle;
  final List<String> paymentMethods;
  final String onExpiry;
  final ActiveSubscription? subscription;
  final List<SubscriptionPlan> plans;

  const SubscriptionStatus({
    required this.enabled,
    required this.isRequired,
    required this.status,
    this.expiresAt,
    this.currentCycle,
    required this.paymentMethods,
    required this.onExpiry,
    this.subscription,
    required this.plans,
  });

  bool get isActive => status == 'active';

  /// True when a driver without a pass gets no ride requests at all —
  /// either the pass is mandatory, or expiry itself blocks rides.
  bool get blocksRidesWhenExpired => isRequired || onExpiry == 'block';

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) {
    return SubscriptionStatus(
      enabled: json['enabled'] == true,
      isRequired: json['required'] == true,
      status: (json['status'] ?? 'expired').toString(),
      expiresAt: _toDate(json['expiresAt']),
      currentCycle: json['currentCycle'] is Map
          ? SubscriptionCycle.fromJson(Map<String, dynamic>.from(json['currentCycle'] as Map))
          : null,
      paymentMethods: _toStringList(json['paymentMethods']),
      onExpiry: (json['onExpiry'] ?? 'commission').toString(),
      subscription: json['subscription'] is Map
          ? ActiveSubscription.fromJson(Map<String, dynamic>.from(json['subscription'] as Map))
          : null,
      plans: json['plans'] is List
          ? (json['plans'] as List)
              .map((e) => SubscriptionPlan.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList()
          : const [],
    );
  }
}

/// `POST /drivers/subscription/purchase` response — carries the refreshed
/// status so the screen updates without a follow-up GET.
class SubscriptionPurchaseResult {
  final bool requiresPayment;
  final double amount;
  final SubscriptionStatus? status;

  const SubscriptionPurchaseResult({
    required this.requiresPayment,
    required this.amount,
    this.status,
  });

  factory SubscriptionPurchaseResult.fromJson(Map<String, dynamic> json) {
    return SubscriptionPurchaseResult(
      requiresPayment: json['requiresPayment'] == true,
      amount: _toDouble(json['amount']),
      status: json['status'] is Map
          ? SubscriptionStatus.fromJson(Map<String, dynamic>.from(json['status'] as Map))
          : null,
    );
  }
}

/// One row of `GET /drivers/subscription/history`.
class SubscriptionHistoryItem {
  final String planName;
  final double amount;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final DateTime? paidAt;
  final String paymentMethod;
  final int tripsCovered;
  final double commissionWaived;

  const SubscriptionHistoryItem({
    required this.planName,
    required this.amount,
    this.startsAt,
    this.expiresAt,
    this.paidAt,
    required this.paymentMethod,
    required this.tripsCovered,
    required this.commissionWaived,
  });

  factory SubscriptionHistoryItem.fromJson(Map<String, dynamic> json) {
    return SubscriptionHistoryItem(
      planName: (json['planName'] ?? '').toString(),
      amount: _toDouble(json['amount']),
      startsAt: _toDate(json['startsAt']),
      expiresAt: _toDate(json['expiresAt']),
      paidAt: _toDate(json['paidAt']),
      paymentMethod: (json['paymentMethod'] ?? '').toString(),
      tripsCovered: (json['tripsCovered'] is num) ? (json['tripsCovered'] as num).toInt() : 0,
      commissionWaived: _toDouble(json['commissionWaived']),
    );
  }
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0.0;
}

DateTime? _toDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

List<String> _toStringList(dynamic value) {
  if (value is List) return value.map((e) => e.toString()).toList();
  return const [];
}
