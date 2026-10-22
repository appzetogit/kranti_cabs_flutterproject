import '../data/models/ride_model.dart';

class RideTrackingState {
  final RideModel? ride;
  final bool isLoading;
  final String? error;
  final bool isCancelling;

  /// Minutes until the driver reaches the pickup, or the rider the drop -
  /// whichever leg is running. Null when no route could be resolved, which
  /// the UI shows as nothing rather than as a guess.
  final double? etaMinutes;

  const RideTrackingState({
    this.ride,
    this.isLoading = true,
    this.error,
    this.isCancelling = false,
    this.etaMinutes,
  });

  RideTrackingState copyWith({
    RideModel? ride,
    bool? isLoading,
    String? error,
    bool? isCancelling,
    double? etaMinutes,
    bool clearError = false,
    bool clearEta = false,
  }) {
    return RideTrackingState(
      ride: ride ?? this.ride,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      isCancelling: isCancelling ?? this.isCancelling,
      etaMinutes: clearEta ? null : (etaMinutes ?? this.etaMinutes),
    );
  }
}
