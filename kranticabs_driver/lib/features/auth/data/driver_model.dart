class DriverTodaySummary {
  final int rides;
  final double earnings;
  final double distanceMeters;
  final int activeMinutes;

  const DriverTodaySummary({
    this.rides = 0,
    this.earnings = 0,
    this.distanceMeters = 0,
    this.activeMinutes = 0,
  });

  factory DriverTodaySummary.fromJson(Map<String, dynamic> json) =>
      DriverTodaySummary(
        rides: (json['rides'] as num?)?.toInt() ?? 0,
        earnings: (json['earnings'] as num?)?.toDouble() ?? 0,
        distanceMeters: (json['distanceMeters'] as num?)?.toDouble() ?? 0,
        activeMinutes: (json['activeMinutes'] as num?)?.toInt() ?? 0,
      );

  static const empty = DriverTodaySummary();
}

class BankDetails {
  final String accountHolderName;
  final String accountNumber;
  final String ifsc;
  final String branchName;
  final String upiId;
  final bool isVerified;

  const BankDetails({
    this.accountHolderName = '',
    this.accountNumber = '',
    this.ifsc = '',
    this.branchName = '',
    this.upiId = '',
    this.isVerified = false,
  });

  factory BankDetails.fromJson(Map<String, dynamic> json) => BankDetails(
    accountHolderName: (json['accountHolderName'] ?? '').toString(),
    accountNumber: (json['accountNumber'] ?? '').toString(),
    ifsc: (json['ifsc'] ?? '').toString(),
    branchName: (json['branchName'] ?? '').toString(),
    upiId: (json['upiId'] ?? '').toString(),
    isVerified: json['isVerified'] == true || json['bankVerified'] == true,
  );

  bool get hasDetails => accountNumber.isNotEmpty || upiId.isNotEmpty;

  static const empty = BankDetails();
}

class DriverModel {
  final String id;
  final String name;
  final String phone;
  final String? email;
  final String? gender;
  final String? vehicleType;

  /// Catalog id of the driver's vehicle type — selects that type's exact map art.
  final String? vehicleTypeId;

  /// Every vehicle category this driver is enrolled in (a driver can pick
  /// more than one at onboarding). Always includes [vehicleTypeId] as its
  /// first entry when the driver has one.
  final List<String> vehicleTypeIds;
  final String? registerFor;
  final String? vehicleNumber;
  final String? vehicleColor;
  final String? city;
  final bool approve;
  final String status;
  final double rating;
  final bool isOnline;
  final bool isOnRide;
  final String? profileImage;
  final double walletBalance;
  final DriverTodaySummary todaySummary;
  final BankDetails bankDetails;
  final Map<String, dynamic> documents;

  /// Registration time, from the server; null for an older cached session.
  final DateTime? createdAt;

  const DriverModel({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    this.gender,
    this.vehicleType,
    this.vehicleTypeId,
    this.vehicleTypeIds = const [],
    this.registerFor,
    this.vehicleNumber,
    this.vehicleColor,
    this.city,
    required this.approve,
    required this.status,
    required this.rating,
    required this.isOnline,
    required this.isOnRide,
    this.profileImage,
    this.walletBalance = 0,
    this.todaySummary = DriverTodaySummary.empty,
    this.bankDetails = BankDetails.empty,
    this.documents = const {},
    this.createdAt,
  });

  factory DriverModel.fromJson(Map<String, dynamic> json) {
    return DriverModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      email: json['email']?.toString(),
      gender: json['gender']?.toString(),
      vehicleType: json['vehicleType']?.toString(),
      vehicleTypeId: json['vehicleTypeId']?.toString(),
      vehicleTypeIds:
          (json['vehicleTypeIds'] is List &&
              (json['vehicleTypeIds'] as List).isNotEmpty)
          ? (json['vehicleTypeIds'] as List)
                .map((id) => id.toString())
                .where((id) => id.isNotEmpty)
                .toList()
          : [
              if ((json['vehicleTypeId']?.toString() ?? '').isNotEmpty)
                json['vehicleTypeId'].toString(),
            ],
      registerFor: json['registerFor']?.toString(),
      vehicleNumber: json['vehicleNumber']?.toString(),
      vehicleColor: json['vehicleColor']?.toString(),
      city: json['city']?.toString(),
      approve: json['approve'] != false,
      status: (json['status'] ?? 'pending').toString(),
      rating: (json['rating'] is num) ? (json['rating'] as num).toDouble() : 0,
      isOnline: json['isOnline'] == true,
      isOnRide: json['isOnRide'] == true,
      profileImage:
          json['profileImage']?.toString() ??
          json['profileImageUrl']?.toString(),
      // `/drivers/me` returns the balance nested under `wallet`, which none of
      // the flat spellings below ever matched — so this parsed to 0 and every
      // screen that fell back to it showed an empty wallet for a driver who
      // had money. The nested read comes first because it is what the API
      // actually sends; the flat ones stay for older payload shapes.
      walletBalance:
          (json['wallet'] is Map
              ? (Map<String, dynamic>.from(json['wallet'] as Map)['balance']
                        as num?)
                    ?.toDouble()
              : null) ??
          (json['walletBalance'] as num?)?.toDouble() ??
          (json['wallet_balance'] as num?)?.toDouble() ??
          (json['balance'] as num?)?.toDouble() ??
          0,
      todaySummary: json['todaySummary'] is Map
          ? DriverTodaySummary.fromJson(
              Map<String, dynamic>.from(json['todaySummary'] as Map),
            )
          : DriverTodaySummary.empty,
      bankDetails: json['bankDetails'] is Map
          ? BankDetails.fromJson(
              Map<String, dynamic>.from(json['bankDetails'] as Map),
            )
          : BankDetails.empty,
      documents: json['documents'] is Map
          ? Map<String, dynamic>.from(json['documents'] as Map)
          : const {},
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}') ??
          _createdAtFromObjectId((json['id'] ?? json['_id'] ?? '').toString()),
    );
  }

  /// A Mongo ObjectId starts with its creation time (seconds, 8 hex chars), so
  /// the registration date is recoverable even when the API omits `createdAt`.
  static DateTime? _createdAtFromObjectId(String id) {
    if (id.length != 24) return null;
    final secs = int.tryParse(id.substring(0, 8), radix: 16);
    return secs == null ? null : DateTime.fromMillisecondsSinceEpoch(secs * 1000, isUtc: true);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'email': email,
    'gender': gender,
    'vehicleType': vehicleType,
    'vehicleTypeId': vehicleTypeId,
    'vehicleTypeIds': vehicleTypeIds,
    'registerFor': registerFor,
    'vehicleNumber': vehicleNumber,
    'vehicleColor': vehicleColor,
    'city': city,
    'approve': approve,
    'status': status,
    'rating': rating,
    'isOnline': isOnline,
    'isOnRide': isOnRide,
    'profileImage': profileImage,
    'createdAt': createdAt?.toIso8601String(),
  };

  bool get isApproved => approve && status.toLowerCase() != 'pending';
  bool get isPending => status.toLowerCase() == 'pending';
  bool get isRejected =>
      status.toLowerCase() == 'rejected' || status.toLowerCase() == 'blocked';

  String get fullName => name;
  String? get profilePictureUrl => profileImage;
  String? get vehicleModel => vehicleType;

  DriverModel copyWith({
    bool? isOnline,
    bool? isOnRide,
    String? status,
    bool? approve,
  }) {
    return DriverModel(
      id: id,
      name: name,
      phone: phone,
      email: email,
      gender: gender,
      vehicleType: vehicleType,
      vehicleTypeId: vehicleTypeId,
      vehicleTypeIds: vehicleTypeIds,
      registerFor: registerFor,
      vehicleNumber: vehicleNumber,
      vehicleColor: vehicleColor,
      city: city,
      approve: approve ?? this.approve,
      status: status ?? this.status,
      rating: rating,
      isOnline: isOnline ?? this.isOnline,
      isOnRide: isOnRide ?? this.isOnRide,
      profileImage: profileImage,
      walletBalance: walletBalance,
      todaySummary: todaySummary,
      bankDetails: bankDetails,
      documents: documents,
      createdAt: createdAt,
    );
  }
}
