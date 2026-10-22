class DashboardState {
  final bool isOnline;
  final bool busy;
  final double? lat;
  final double? lng;

  const DashboardState({
    this.isOnline = false,
    this.busy = false,
    this.lat,
    this.lng,
  });

  DashboardState copyWith({bool? isOnline, bool? busy, double? lat, double? lng}) {
    return DashboardState(
      isOnline: isOnline ?? this.isOnline,
      busy: busy ?? this.busy,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
    );
  }
}
