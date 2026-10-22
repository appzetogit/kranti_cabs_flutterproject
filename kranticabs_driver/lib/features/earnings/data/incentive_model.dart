class MilestoneModel {
  final String id;
  final String name;
  final bool enabled;
  final double payoutAmount;
  final String notes;
  final int qualifyingWeeks;
  final int targetWeeks;
  final int qualifyingDays;
  final int targetDays;
  final bool isEligible;
  final bool isClaimed;

  const MilestoneModel({
    required this.id,
    required this.name,
    required this.enabled,
    required this.payoutAmount,
    required this.notes,
    required this.qualifyingWeeks,
    required this.targetWeeks,
    required this.qualifyingDays,
    required this.targetDays,
    required this.isEligible,
    required this.isClaimed,
  });

  factory MilestoneModel.fromJson(Map<String, dynamic> json) {
    final progress = Map<String, dynamic>.from(json['progress'] as Map? ?? {});
    return MilestoneModel(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      enabled: json['enabled'] == true,
      payoutAmount: (json['payout_amount'] as num?)?.toDouble() ?? 0,
      notes: (json['notes'] ?? '').toString(),
      qualifyingWeeks: (progress['qualifyingWeeks'] as num?)?.toInt() ?? 0,
      targetWeeks: (progress['targetWeeks'] as num?)?.toInt() ?? 0,
      qualifyingDays: (progress['qualifyingDays'] as num?)?.toInt() ?? 0,
      targetDays: (progress['targetDays'] as num?)?.toInt() ?? 0,
      isEligible: json['isEligible'] == true,
      isClaimed: json['isClaimed'] == true,
    );
  }

  double get dayProgress => targetDays == 0 ? 0 : (qualifyingDays / targetDays).clamp(0, 1);
}

class FeatureRewardModel {
  final String key;
  final String label;
  final bool enabled;
  final double rewardAmount;
  final double targetValue;
  final double currentValue;
  final String unit;
  final String description;
  final bool isEligible;
  final bool isClaimed;

  const FeatureRewardModel({
    required this.key,
    required this.label,
    required this.enabled,
    required this.rewardAmount,
    required this.targetValue,
    required this.currentValue,
    required this.unit,
    required this.description,
    required this.isEligible,
    required this.isClaimed,
  });

  factory FeatureRewardModel.fromJson(Map<String, dynamic> json) => FeatureRewardModel(
        key: (json['key'] ?? '').toString(),
        label: (json['label'] ?? '').toString(),
        enabled: json['enabled'] == true,
        rewardAmount: (json['reward_amount'] as num?)?.toDouble() ?? 0,
        targetValue: (json['targetValue'] as num?)?.toDouble() ?? 0,
        currentValue: (json['currentValue'] as num?)?.toDouble() ?? 0,
        unit: (json['unit'] ?? '').toString(),
        description: (json['description'] ?? '').toString(),
        isEligible: json['isEligible'] == true,
        isClaimed: json['isClaimed'] == true,
      );

  double get progress => targetValue == 0 ? 0 : (currentValue / targetValue).clamp(0, 1);
}

class IncentiveSnapshot {
  final List<MilestoneModel> milestones;
  final List<FeatureRewardModel> features;
  final int streakDays;
  final int currentWeekTrips;

  const IncentiveSnapshot({
    required this.milestones,
    required this.features,
    required this.streakDays,
    required this.currentWeekTrips,
  });

  factory IncentiveSnapshot.fromJson(Map<String, dynamic> json) {
    final summary = Map<String, dynamic>.from(json['summary'] as Map? ?? {});
    return IncentiveSnapshot(
      milestones: (json['milestones'] as List? ?? const [])
          .map((e) => MilestoneModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((m) => m.enabled)
          .toList(),
      features: (json['features'] as List? ?? const [])
          .map((e) => FeatureRewardModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((f) => f.enabled)
          .toList(),
      streakDays: (summary['streakDays'] as num?)?.toInt() ?? 0,
      currentWeekTrips: (summary['currentWeekTrips'] as num?)?.toInt() ?? 0,
    );
  }

  static const empty = IncentiveSnapshot(milestones: [], features: [], streakDays: 0, currentWeekTrips: 0);
}
