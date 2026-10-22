import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/providers/vehicle_icons_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/vehicle_marker_helper.dart';
import '../../auth/application/auth_providers.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../application/heatmap_controller.dart';
import '../data/opportunity_models.dart';
import 'heatmap_legend.dart';
import 'opportunity_sheet.dart';
import 'opportunity_style.dart';
import 'surge_pill_icon.dart';

/// The driver's own vehicle marker art, resolved from the same
/// backend-configured catalog `active_ride_screen.dart` uses — the driver's
/// own vehicle-type art first, then the family silhouette, both admin-managed.
/// Null (never a bundled placeholder) when the backend has neither, so a
/// driver whose vehicle type has no uploaded art gets the map SDK's own
/// default pin instead of a stand-in vehicle that isn't theirs.
final driverVehicleIconProvider = FutureProvider.autoDispose<BitmapDescriptor?>(
  (ref) async {
    final driver = ref.watch(authProvider).driver;
    final icons = await ref.watch(vehicleMapIconsProvider.future);

    final vehicleTypeId = driver?.vehicleTypeId ?? '';
    final byId = vehicleTypeId.isNotEmpty ? icons[vehicleTypeId] : null;
    if (byId != null) return byId;

    return icons[VehicleMarkerHelper.familyFor(driver?.vehicleType)];
  },
);

/// Where fares are higher and where riders are waiting, so a driver can
/// decide where to go.
///
/// Surging areas are warm (orange to red) with a "1.3x" label; busy areas
/// without a surge are violet. The multiplier is the one riders in that area
/// are quoted - read from the same server value, never recomputed here.
class DemandMapScreen extends ConsumerStatefulWidget {
  const DemandMapScreen({super.key});

  @override
  ConsumerState<DemandMapScreen> createState() => _DemandMapScreenState();
}

class _DemandMapScreenState extends ConsumerState<DemandMapScreen> {
  GoogleMapController? _mapController;
  StreamSubscription? _positionSub;
  LatLng? _driverLatLng;
  Timer? _freshnessTicker;

  bool _showSurge = true;
  bool _showDemand = true;
  bool _showAirports = true;

  /// "1.3x" labels drawn so far, by label. Drawing is async, so a label shows
  /// up a frame after its hexagon the first time and instantly after that.
  final Map<String, BitmapDescriptor> _pills = {};
  final Set<String> _pillsPending = {};

  /// Where the map opens before the driver's position is known. Bengaluru,
  /// where most drivers are; it used to be Indore.
  static const LatLng _fallback = LatLng(12.9716, 77.5946);

  @override
  void initState() {
    super.initState();
    _startTrackingDriver();
    // Redraws only the "updated Ns ago" label, not the map.
    _freshnessTicker = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _startTrackingDriver() async {
    final location = ref.read(locationServiceProvider);

    try {
      final position = await location.getCurrentPosition();
      final here = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() => _driverLatLng = here);
      await ref.read(heatmapControllerProvider.notifier).setLocation(here.latitude, here.longitude, force: true);
      _moveCamera(here, 12.5);
    } catch (_) {
      // No fix yet — show the city and let the map load around it rather
      // than leaving a blank screen.
      if (!mounted) return;
      setState(() => _driverLatLng = _fallback);
      await ref.read(heatmapControllerProvider.notifier).setLocation(_fallback.latitude, _fallback.longitude, force: true);
    }

    // Follow the driver so the visible area refreshes as they move. The
    // controller itself decides whether a move is big enough to refetch.
    _positionSub = location.watchPosition(distanceFilterMeters: 250).listen((position) {
      if (!mounted) return;
      setState(() => _driverLatLng = LatLng(position.latitude, position.longitude));
      ref.read(heatmapControllerProvider.notifier).setLocation(position.latitude, position.longitude);
    });
  }

  void _moveCamera(LatLng target, double zoom) {
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(target, zoom));
  }

  /// The normal grid is always drawn, like Rapido's - a quiet map should
  /// still show the hexagons, so it reads as "normal here", not as broken.
  /// The chips only hide the surge and busy layers on top of it.
  bool _visible(OpportunityCell cell) {
    if (cell.isSurging) return _showSurge;
    if (cell.demand == DemandIntensity.normal) return true;
    return _showDemand;
  }

  void _openCell(OpportunityMap map, OpportunityCell cell) {
    showOpportunitySheet(
      context,
      map: map,
      cell: cell,
      onShowOnMap: () {
        Navigator.of(context).pop();
        _moveCamera(cell.center, 14.5);
      },
    );
  }

  void _openHotspot(OpportunityMap map, Hotspot hotspot) {
    _moveCamera(hotspot.center, 14);
    showOpportunitySheet(
      context,
      map: map,
      hotspot: hotspot,
      onShowOnMap: () {
        Navigator.of(context).pop();
        _moveCamera(hotspot.center, 14.5);
      },
    );
  }

  Set<Polygon> _buildPolygons(OpportunityMap map) {
    return map.cells.where(_visible).map((cell) {
      final color = OpportunityStyle.cellColor(cell, maxMultiplier: map.maxMultiplier);
      final quiet = !cell.isSurging && cell.demand == DemandIntensity.normal;
      final strong = cell.isSurging || cell.demand == DemandIntensity.veryHigh;
      return Polygon(
        polygonId: PolygonId(cell.hex),
        points: cell.boundary,
        // The quiet grid is a faint outline, so surge and busy areas stand
        // out against it.
        fillColor: color.withValues(alpha: quiet ? 0.05 : (strong ? 0.34 : 0.22)),
        strokeColor: color.withValues(alpha: quiet ? 0.45 : 0.8),
        strokeWidth: strong ? 2 : 1,
        // Busy and surging areas sit on top of the grid where they meet.
        zIndex: quiet ? 0 : 1,
        consumeTapEvents: true,
        onTap: () => _openCell(map, cell),
      );
    }).toSet();
  }

  /// Starts drawing any "1.3x" label not drawn yet; the map picks it up on
  /// the next build.
  void _ensurePills(OpportunityMap map) {
    for (final cell in map.cells) {
      if (!cell.isSurging) continue;
      final key = SurgePillIcon.labelFor(cell.multiplier);
      if (_pills.containsKey(key) || _pillsPending.contains(key)) continue;
      _pillsPending.add(key);
      SurgePillIcon.forMultiplier(cell.multiplier, max: map.maxMultiplier).then((icon) {
        _pillsPending.remove(key);
        if (!mounted) return;
        setState(() => _pills[key] = icon);
      });
    }
  }

  Set<Marker> _buildMarkers(OpportunityMap map, LatLng? self, BitmapDescriptor? vehicleIcon) {
    final markers = <Marker>{
      if (self != null)
        Marker(
          markerId: const MarkerId('driver_self'),
          position: self,
          icon: vehicleIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          anchor: const Offset(0.5, 0.5),
          flat: true,
          zIndexInt: 3,
        ),
    };

    if (_showSurge) {
      for (final cell in map.cells.where((c) => c.isSurging)) {
        final icon = _pills[SurgePillIcon.labelFor(cell.multiplier)];
        if (icon == null) continue;
        markers.add(Marker(
          markerId: MarkerId('pill_${cell.hex}'),
          position: cell.center,
          icon: icon,
          anchor: const Offset(0.5, 0.5),
          zIndexInt: 2,
          onTap: () => _openCell(map, cell),
        ));
      }
    }

    if (_showAirports) {
      for (final airport in map.airports) {
        final busy = airport.demand != DemandIntensity.normal;
        final distance = OpportunityStyle.distanceLabel(airport.distanceKm);
        markers.add(Marker(
          markerId: MarkerId('airport_${airport.name}'),
          position: airport.position,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            airport.multiplier > 1 ? BitmapDescriptor.hueOrange : BitmapDescriptor.hueAzure,
          ),
          zIndexInt: 1,
          infoWindow: InfoWindow(
            title: airport.name,
            snippet: [
              if (airport.multiplier > 1) '${SurgePillIcon.labelFor(airport.multiplier)} fares',
              busy ? OpportunityStyle.demandLabel(airport.demand) : 'Normal demand',
              if (distance.isNotEmpty) distance,
            ].join(' · '),
          ),
        ));
      }
    }

    return markers;
  }

  String _freshness(DateTime receivedAt) {
    final seconds = DateTime.now().difference(receivedAt).inSeconds;
    if (seconds < 5) return 'Updated just now';
    if (seconds < 60) return 'Updated ${seconds}s ago';
    return 'Updated ${seconds ~/ 60}m ago';
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _freshnessTicker?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(heatmapControllerProvider);
    final map = state.map;
    _ensurePills(map);

    // The same fix the online-and-idle location update keeps synced to the
    // server (`DashboardNotifier`'s tracking loop) — preferred over this
    // screen's own local `_driverLatLng` so the marker shows exactly what the
    // backend, and therefore every rider's ETA, currently sees for this
    // driver. Falls back to the local fix only until that loop has produced
    // its first one (e.g. briefly after going online).
    final dashboard = ref.watch(dashboardProvider);
    final backendPosition =
        (dashboard.lat != null && dashboard.lng != null) ? LatLng(dashboard.lat!, dashboard.lng!) : null;
    final markerPosition = backendPosition ?? _driverLatLng;
    final vehicleIcon = ref.watch(driverVehicleIconProvider).valueOrNull;

    final surgeCount = map.cells.where((c) => c.isSurging).length;
    final busyCount = map.cells.where((c) => !c.isSurging && c.demand != DemandIntensity.normal).length;

    return Scaffold(
      backgroundColor: const Color(0xFF11191D),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _driverLatLng ?? _fallback, zoom: 12.5),
            onMapCreated: (controller) => _mapController = controller,
            // Replaced by the vehicle marker — one indicator for the driver's
            // position, not a generic dot plus a vehicle icon on top of it.
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            polygons: _buildPolygons(map),
            markers: _buildMarkers(map, markerPosition, vehicleIcon),
          ),

          // Back + legend
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: Row(
              children: [
                _CircleButton(icon: Icons.arrow_back_rounded, onTap: () => Navigator.of(context).maybePop()),
                const SizedBox(width: 10),
                Expanded(child: HeatmapLegend(maxMultiplier: map.maxMultiplier)),
              ],
            ),
          ),

          // Recentre
          Positioned(
            right: 16,
            bottom: 236,
            child: _CircleButton(
              icon: Icons.my_location_rounded,
              onTap: () {
                // Same position the vehicle marker is drawn at, so this can
                // never recentre somewhere other than where the marker is.
                if (markerPosition != null) _moveCamera(markerPosition, 15);
              },
            ),
          ),

          // Chips + summary card
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _Chip(
                        icon: Icons.near_me_rounded,
                        label: 'Go to',
                        selected: false,
                        highlight: true,
                        onTap: () {
                          final best = map.best;
                          if (best == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('No surge near you right now — demand is normal.')),
                            );
                            return;
                          }
                          _openHotspot(map, best);
                        },
                      ),
                      _Chip(
                        icon: Icons.trending_up_rounded,
                        label: surgeCount > 0 ? 'Surge ($surgeCount)' : 'Surge',
                        selected: _showSurge,
                        onTap: () => setState(() => _showSurge = !_showSurge),
                      ),
                      _Chip(
                        icon: Icons.local_fire_department_rounded,
                        label: busyCount > 0 ? 'High Demand ($busyCount)' : 'High Demand',
                        selected: _showDemand,
                        onTap: () => setState(() => _showDemand = !_showDemand),
                      ),
                      _Chip(
                        icon: Icons.flight_rounded,
                        label: 'Airport',
                        selected: _showAirports,
                        onTap: () {
                          setState(() => _showAirports = !_showAirports);
                          if (_showAirports && map.airports.isNotEmpty) {
                            _moveCamera(map.airports.first.position, 12);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _SummaryCard(
                    loading: state.loading && state.isInitial,
                    surgeEnabled: map.surgeEnabled,
                    best: map.best,
                    areaCount: busyCount,
                    freshness: state.error ?? _freshness(map.receivedAt),
                    onGoTo: map.best == null ? null : () => _openHotspot(map, map.best!),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool highlight;
  final VoidCallback onTap;

  const _Chip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final background = highlight
        ? AppColors.primary
        : selected
            ? const Color(0xFF1E3A5F)
            : const Color(0xFF222222);
    final foreground = highlight ? const Color(0xFF11191D) : Colors.white;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: background,
        elevation: 3,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: highlight ? AppColors.primary : (selected ? const Color(0xFF38BDF8) : const Color(0xFF2E2E2E)),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: foreground.withValues(alpha: selected || highlight ? 1 : 0.6)),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: foreground.withValues(alpha: selected || highlight ? 1 : 0.6),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF222222),
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 21, color: Colors.white),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final bool loading;
  final bool surgeEnabled;
  final Hotspot? best;
  final int areaCount;
  final String freshness;
  final VoidCallback? onGoTo;

  const _SummaryCard({
    required this.loading,
    required this.surgeEnabled,
    required this.best,
    required this.areaCount,
    required this.freshness,
    this.onGoTo,
  });

  @override
  Widget build(BuildContext context) {
    final hotspot = best;

    String title;
    String subtitle;
    Color accent;
    if (hotspot == null) {
      title = surgeEnabled ? 'No surge near you right now' : 'Surge pricing is off in your city';
      subtitle = 'Demand is normal — stay where you are.';
      accent = const Color(0xFF7C8BA1);
    } else {
      final place = hotspot.title.isNotEmpty ? hotspot.title : OpportunityStyle.distanceLabel(hotspot.distanceKm);
      title = hotspot.isSurging
          ? '${SurgePillIcon.labelFor(hotspot.multiplier)} fares${place.isNotEmpty ? ' at $place' : ''}'
          : '${OpportunityStyle.demandLabel(hotspot.demand)}${place.isNotEmpty ? ' · $place' : ''}';
      final fare = hotspot.exampleFare;
      final distance = OpportunityStyle.distanceLabel(hotspot.distanceKm);
      subtitle = [
        if (hotspot.title.isNotEmpty && distance.isNotEmpty) distance,
        if (fare != null && fare.extra > 0) '₹${fare.extra} more per ${fare.km.toStringAsFixed(0)} km trip',
        if (hotspot.isSurging && hotspot.surgeEndsInMinutes > 0) 'ends in ${hotspot.surgeEndsInMinutes} min',
      ].join(' · ');
      if (subtitle.isEmpty) subtitle = '$areaCount busy area${areaCount == 1 ? '' : 's'} around you';
      accent = hotspot.isSurging ? SurgePillIcon.colorFor(hotspot.multiplier) : OpportunityStyle.demandColor(hotspot.demand);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF222222),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2E2E2E)),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 6))],
      ),
      child: loading
          ? const Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                ),
                SizedBox(width: 12),
                Text('Loading the map…', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      hotspot != null ? Icons.trending_up_rounded : Icons.remove_rounded,
                      size: 18,
                      color: accent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(freshness, style: const TextStyle(color: Color(0xFF7C8BA1), fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(subtitle, style: const TextStyle(color: Color(0xFFB6C2D2), fontSize: 12.5)),
                if (onGoTo != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: ElevatedButton.icon(
                      onPressed: onGoTo,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: const Color(0xFF11191D),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(21)),
                      ),
                      icon: const Icon(Icons.near_me_rounded, size: 17),
                      label: const Text('Go to', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
