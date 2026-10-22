import 'parcel_info.dart';

class RideHistoryItem {
  final String id;
  final String status;
  final String? liveStatus;
  final double fare;
  final double baseFare;
  final double commissionAmount;
  final double driverEarnings;
  final double estimatedDistanceMeters;
  final double estimatedDurationMinutes;
  final String pickupAddress;
  final String dropAddress;
  final String paymentMethod;
  final DateTime? completedAt;
  final DateTime? createdAt;
  final String riderName;
  final String? serviceType;
  final ParcelInfo parcel;

  const RideHistoryItem({
    required this.id,
    required this.status,
    this.liveStatus,
    required this.fare,
    this.baseFare = 0,
    this.commissionAmount = 0,
    required this.driverEarnings,
    required this.estimatedDistanceMeters,
    this.estimatedDurationMinutes = 0,
    required this.pickupAddress,
    required this.dropAddress,
    required this.paymentMethod,
    this.completedAt,
    this.createdAt,
    required this.riderName,
    this.serviceType,
    this.parcel = ParcelInfo.none,
  });

  factory RideHistoryItem.fromJson(Map<String, dynamic> json) {
    final user = json['user'] is Map ? Map<String, dynamic>.from(json['user'] as Map) : null;
    return RideHistoryItem(
      id: (json['rideId'] ?? json['_id'] ?? json['id'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      liveStatus: json['liveStatus']?.toString(),
      fare: (json['fare'] as num?)?.toDouble() ?? 0,
      baseFare: (json['baseFare'] as num?)?.toDouble() ?? 0,
      commissionAmount: (json['commissionAmount'] as num?)?.toDouble() ?? 0,
      driverEarnings: (json['driverEarnings'] as num?)?.toDouble() ?? 0,
      estimatedDistanceMeters: (json['estimatedDistanceMeters'] as num?)?.toDouble() ?? 0,
      estimatedDurationMinutes: (json['estimatedDurationMinutes'] as num?)?.toDouble() ?? 0,
      pickupAddress: (json['pickupAddress'] ?? '').toString(),
      dropAddress: (json['dropAddress'] ?? '').toString(),
      paymentMethod: (json['paymentMethod'] ?? '').toString(),
      completedAt: json['completedAt'] != null ? DateTime.tryParse(json['completedAt'].toString()) : null,
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'].toString()) : null,
      riderName: (user?['name'] ?? '').toString(),
      serviceType: json['serviceType']?.toString(),
      parcel: json['parcel'] is Map ? ParcelInfo.fromJson(Map<String, dynamic>.from(json['parcel'] as Map)) : ParcelInfo.none,
    );
  }

  bool get isCompleted => status.toLowerCase() == 'completed';
  bool get isCancelled => status.toLowerCase() == 'cancelled';
  bool get isParcel => (serviceType ?? '').toLowerCase() == 'parcel' || parcel.isNotEmpty;
}

class RideHistoryPage {
  final List<RideHistoryItem> results;
  final int total;
  final bool hasNextPage;

  const RideHistoryPage({required this.results, required this.total, required this.hasNextPage});

  static const empty = RideHistoryPage(results: [], total: 0, hasNextPage: false);
}
