/// Destination mode ("Go Home") state, from GET/PUT /drivers/me/destination.
///
/// While [enabled], the server offers this driver only rides whose pickup and
/// drop lie along their road route to [destinationLabel], and turns the mode
/// off on arrival or at [expiresAt].
class DestinationModeInfo {
  final bool enabled;
  final String destinationLabel;
  final bool isHome;
  final DateTime? expiresAt;

  /// Saved home, if any.
  final double? homeLat;
  final double? homeLng;
  final String homeAddress;

  /// When home may next be moved; null when it can be moved now.
  final DateTime? canChangeHomeAt;

  /// Whether the admin has the feature switched on.
  final bool featureEnabled;
  final int usesPerDay;
  final int usedToday;

  const DestinationModeInfo({
    this.enabled = false,
    this.destinationLabel = '',
    this.isHome = false,
    this.expiresAt,
    this.homeLat,
    this.homeLng,
    this.homeAddress = '',
    this.canChangeHomeAt,
    this.featureEnabled = true,
    this.usesPerDay = 0,
    this.usedToday = 0,
  });

  bool get hasHome => homeLat != null && homeLng != null;

  /// Uses left today; null when there is no daily limit.
  int? get usesLeft => usesPerDay > 0 ? (usesPerDay - usedToday).clamp(0, usesPerDay) : null;

  static const none = DestinationModeInfo();

  factory DestinationModeInfo.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? map(dynamic value) => value is Map ? Map<String, dynamic>.from(value) : null;
    double? number(dynamic value) => value == null ? null : double.tryParse('$value');
    DateTime? date(dynamic value) => value == null ? null : DateTime.tryParse('$value');

    final destination = map(json['destination']);
    final home = map(json['home']);
    return DestinationModeInfo(
      enabled: json['enabled'] == true,
      destinationLabel: (destination?['label'] ?? '').toString(),
      isHome: destination?['isHome'] == true,
      expiresAt: date(json['expiresAt']),
      homeLat: number(home?['lat']),
      homeLng: number(home?['lng']),
      homeAddress: (home?['address'] ?? '').toString(),
      canChangeHomeAt: date(json['canChangeHomeAt']),
      featureEnabled: json['featureEnabled'] != false,
      usesPerDay: int.tryParse('${json['usesPerDay'] ?? 0}') ?? 0,
      usedToday: int.tryParse('${json['usedToday'] ?? 0}') ?? 0,
    );
  }
}
