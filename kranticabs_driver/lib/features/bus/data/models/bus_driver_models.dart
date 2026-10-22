/// Models for the bus-driver profile, assigned bus service, schedules, signup
/// options and approval status. Mirror the backend serializers under
/// `/drivers/me`, `/drivers/onboarding/signup-options` and
/// `/drivers/approval-status`.
library;

int _toInt(dynamic v) => int.tryParse('${v ?? 0}') ?? 0;
double _toDouble(dynamic v) => double.tryParse('${v ?? 0}') ?? 0;
String _toStr(dynamic v) => (v ?? '').toString();
List<String> _toStrList(dynamic v) =>
    (v is List) ? v.map((e) => e.toString()).toList() : const [];

/// One departure schedule on a bus service.
class BusSchedule {
  final String id;
  final String label;
  final String departureTime; // "HH:mm"
  final String arrivalTime;
  final List<String> activeDays; // ['Mon','Tue',...]
  final String status; // active | paused | draft

  const BusSchedule({
    required this.id,
    required this.label,
    required this.departureTime,
    required this.arrivalTime,
    required this.activeDays,
    required this.status,
  });

  factory BusSchedule.fromJson(Map<String, dynamic> j) => BusSchedule(
        id: _toStr(j['id'] ?? j['_id']),
        label: _toStr(j['label']),
        departureTime: _toStr(j['departureTime'] ?? j['departure_time']),
        arrivalTime: _toStr(j['arrivalTime'] ?? j['arrival_time']),
        activeDays: _toStrList(j['activeDays'] ?? j['active_days']),
        status: _toStr(j['status']).isEmpty ? 'active' : _toStr(j['status']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'departureTime': departureTime,
        'arrivalTime': arrivalTime,
        'activeDays': activeDays,
        'status': status,
      };

  BusSchedule copyWith({
    String? label,
    String? departureTime,
    String? arrivalTime,
    List<String>? activeDays,
    String? status,
  }) =>
      BusSchedule(
        id: id,
        label: label ?? this.label,
        departureTime: departureTime ?? this.departureTime,
        arrivalTime: arrivalTime ?? this.arrivalTime,
        activeDays: activeDays ?? this.activeDays,
        status: status ?? this.status,
      );

  static List<BusSchedule> listFrom(dynamic raw) => (raw is List)
      ? raw
          .whereType<Map>()
          .map((e) => BusSchedule.fromJson(Map<String, dynamic>.from(e)))
          .toList()
      : const [];
}

/// The bus service assigned to this driver.
class BusServiceSummary {
  final String id;
  final String operatorName;
  final String busName;
  final String serviceNumber;
  final String registrationNumber;
  final String coachType;
  final String busCategory;
  final double seatPrice;
  final String fareCurrency;
  final String routeName;
  final String originCity;
  final String destinationCity;
  final String status; // draft | active | paused
  final int capacity;
  final List<String> amenities;
  final List<BusSchedule> schedules;

  const BusServiceSummary({
    required this.id,
    required this.operatorName,
    required this.busName,
    required this.serviceNumber,
    required this.registrationNumber,
    required this.coachType,
    required this.busCategory,
    required this.seatPrice,
    required this.fareCurrency,
    required this.routeName,
    required this.originCity,
    required this.destinationCity,
    required this.status,
    required this.capacity,
    required this.amenities,
    required this.schedules,
  });

  bool get isActive => status.toLowerCase() == 'active';

  factory BusServiceSummary.fromJson(dynamic raw) {
    final j = raw is Map ? Map<String, dynamic>.from(raw) : const {};
    final route = j['route'] is Map ? Map<String, dynamic>.from(j['route']) : const {};
    return BusServiceSummary(
      id: _toStr(j['id'] ?? j['_id']),
      operatorName: _toStr(j['operatorName']),
      busName: _toStr(j['busName']),
      serviceNumber: _toStr(j['serviceNumber']),
      registrationNumber: _toStr(j['registrationNumber']),
      coachType: _toStr(j['coachType']),
      busCategory: _toStr(j['busCategory']),
      seatPrice: _toDouble(j['seatPrice']),
      fareCurrency: _toStr(j['fareCurrency']).isEmpty ? 'INR' : _toStr(j['fareCurrency']),
      routeName: _toStr(j['routeName'] ?? route['routeName']),
      originCity: _toStr(j['originCity'] ?? route['originCity']),
      destinationCity: _toStr(j['destinationCity'] ?? route['destinationCity']),
      status: _toStr(j['status']).isEmpty ? 'draft' : _toStr(j['status']),
      capacity: _toInt(j['capacity']),
      amenities: _toStrList(j['amenities']),
      schedules: BusSchedule.listFrom(j['schedules']),
    );
  }
}

/// The bus-driver's own profile from `/drivers/me`.
class BusDriverProfile {
  final String id;
  final String accountType; // "bus_driver"
  final String name;
  final String phone;
  final String email;
  final bool approve;
  final bool active;
  final String status; // pending | approved | blocked
  final String assignedBusServiceId;
  final BusServiceSummary? busService;
  final int upcomingBookings;
  final int totalSchedules;
  final int totalCapacity;

  const BusDriverProfile({
    required this.id,
    required this.accountType,
    required this.name,
    required this.phone,
    required this.email,
    required this.approve,
    required this.active,
    required this.status,
    required this.assignedBusServiceId,
    required this.busService,
    required this.upcomingBookings,
    required this.totalSchedules,
    required this.totalCapacity,
  });

  bool get isBusDriver => accountType == 'bus_driver';
  bool get isApproved => approve && status.toLowerCase() == 'approved';
  bool get isPending => !isApproved && status.toLowerCase() != 'blocked';
  bool get isBlocked => status.toLowerCase() == 'blocked';

  /// Can actually use the operate screens: approved, active, and the bus itself
  /// is live (the backend blocks seat/booking actions otherwise).
  bool get canOperate => isApproved && active && (busService?.isActive ?? false);

  factory BusDriverProfile.fromJson(Map<String, dynamic> j) {
    final metrics = j['metrics'] is Map ? Map<String, dynamic>.from(j['metrics']) : const {};
    return BusDriverProfile(
      id: _toStr(j['id'] ?? j['_id']),
      accountType: _toStr(j['accountType']),
      name: _toStr(j['name']),
      phone: _toStr(j['phone']),
      email: _toStr(j['email']),
      approve: j['approve'] == true,
      active: j['active'] == true,
      status: _toStr(j['status']).isEmpty ? 'pending' : _toStr(j['status']),
      assignedBusServiceId: _toStr(j['assignedBusServiceId']),
      busService: j['busService'] is Map ? BusServiceSummary.fromJson(j['busService']) : null,
      upcomingBookings: _toInt(metrics['upcomingBookings']),
      totalSchedules: _toInt(metrics['totalSchedules']),
      totalCapacity: _toInt(metrics['totalCapacity']),
    );
  }
}

/// A bus a new driver can join during signup (from signup-options).
class BusSignupOption {
  final String id;
  final String operatorName;
  final String busName;
  final String serviceNumber;
  final String routeName;
  final String originCity;
  final String destinationCity;
  final String status;

  const BusSignupOption({
    required this.id,
    required this.operatorName,
    required this.busName,
    required this.serviceNumber,
    required this.routeName,
    required this.originCity,
    required this.destinationCity,
    required this.status,
  });

  factory BusSignupOption.fromJson(Map<String, dynamic> j) => BusSignupOption(
        id: _toStr(j['id'] ?? j['_id']),
        operatorName: _toStr(j['operatorName']),
        busName: _toStr(j['busName']),
        serviceNumber: _toStr(j['serviceNumber']),
        routeName: _toStr(j['routeName']),
        originCity: _toStr(j['originCity']),
        destinationCity: _toStr(j['destinationCity']),
        status: _toStr(j['status']),
      );
}

/// `/drivers/approval-status` payload (carries rejectionReason).
class BusApprovalStatus {
  final bool approve;
  final String status;
  final String rejectionReason;

  const BusApprovalStatus({
    required this.approve,
    required this.status,
    required this.rejectionReason,
  });

  bool get isApproved => approve && status.toLowerCase() == 'approved';
  bool get isRejected => rejectionReason.trim().isNotEmpty && !isApproved;

  factory BusApprovalStatus.fromJson(Map<String, dynamic> j) => BusApprovalStatus(
        approve: j['approve'] == true,
        status: _toStr(j['status']).isEmpty ? 'pending' : _toStr(j['status']),
        rejectionReason: _toStr(j['rejectionReason']),
      );
}
