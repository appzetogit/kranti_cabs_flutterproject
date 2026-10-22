import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/services/location_service.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_map_style.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../application/home_providers.dart';
import 'location_access.dart';

/// Where the map opens when the rider's location is unknown. Only the camera:
/// nothing is booked from here unless the rider moves the pin and confirms.
/// Bengaluru, where most riders are - it used to be Indore, so a Bengaluru
/// rider with location off had to pan across the country to find their street.
const _fallbackLatLng = LatLng(12.9716, 77.5946);

class MapPickerScreen extends ConsumerStatefulWidget {
  final String type; // 'pickup' or 'drop'

  const MapPickerScreen({super.key, required this.type});

  @override
  ConsumerState<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends ConsumerState<MapPickerScreen> {
  GoogleMapController? _controller;
  LatLng _center = _fallbackLatLng;
  String _address = _addressPlaceholder;
  bool _resolving = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _initPosition();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _initPosition() async {
    final position = await ref.read(currentPositionProvider.future);
    if (position == null || !mounted) return;
    final target = LatLng(position.latitude, position.longitude);
    setState(() => _center = target);
    _controller?.animateCamera(CameraUpdate.newLatLngZoom(target, 16.5));
  }

  /// The "my location" button. With location off it used to do nothing at
  /// all; now it asks to turn location on, then centres on the rider.
  Future<void> _recenterToCurrentLocation() async {
    var position = await ref.read(currentPositionProvider.future);
    if (!mounted) return;

    if (position == null) {
      // Used to do nothing at all, leaving the map where it was with no word.
      final issue = await ref.read(locationServiceProvider).diagnose();
      if (!mounted) return;

      if (issue == LocationIssue.none) {
        SnackbarUtils.info(context, "Couldn't get your location yet. Move the map to set it.");
        return;
      }

      await context.push(
        issue == LocationIssue.gpsOff
            ? '/system/gps-disabled'
            : '/system/location-permission-denied',
      );
      if (!mounted) return;
      position = await ref.read(currentPositionProvider.future);
      if (position == null || !mounted) return;
    }

    final target = LatLng(position.latitude, position.longitude);
    setState(() => _center = target);
    _controller?.animateCamera(CameraUpdate.newLatLngZoom(target, 16.5));
  }

  Future<void> _resolveAddress(LatLng point) async {
    if (!mounted) return;
    setState(() => _resolving = true);
    try {
      final service = ref.read(locationServiceProvider);
      final addr = await service.getAddressFromCoordinates(point.latitude, point.longitude);
      if (mounted) {
        setState(() => _address = addr.isNotEmpty
            ? addr
            : '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _address =
            '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}');
      }
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  static const _addressPlaceholder = 'Move the map to set location';

  Future<void> _confirm() async {
    // Confirming before the first lookup finishes would hand back the
    // placeholder sentence as if it were the address.
    if (_address == _addressPlaceholder) {
      _debounceTimer?.cancel();
      await _resolveAddress(_center);
      if (!mounted) return;
    }

    Navigator.of(context).pop({
      'type': widget.type,
      'lat': _center.latitude,
      'lng': _center.longitude,
      'address': _address == _addressPlaceholder ? '' : _address,
    });
  }

  void _onCameraIdle() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 1500), () {
      _resolveAddress(_center);
    });
  }

  void _onCameraMove(CameraPosition position) {
    _debounceTimer?.cancel();
    _center = position.target;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isPickup = widget.type == 'pickup';
    final cardBgColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            style: AppMapStyle.light,
            initialCameraPosition: CameraPosition(target: _center, zoom: 16.5),
            onMapCreated: (c) {
              _controller = c;
              _initPosition();
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onCameraMove: _onCameraMove,
            onCameraIdle: _onCameraIdle,
          ),

          // --- CENTER MAP LOCATION PIN POINTER ---
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isPickup ? const Color(0xFF10B981) : AppColors.primaryOrange,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 4),
                      ],
                    ),
                    child: Text(
                      isPickup ? 'Set Pickup' : 'Set Drop',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Icon(
                    Icons.location_on_rounded,
                    size: 46,
                    color: isPickup ? const Color(0xFF10B981) : AppColors.primaryOrange,
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.black26,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // --- TOP LEFT BACK BUTTON ---
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Material(
                color: cardBgColor,
                shape: const CircleBorder(),
                elevation: 3,
                child: IconButton(
                  icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: textPrimary),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
          ),

          // --- CURRENT LOCATION FAB BUTTON ---
          Positioned(
            bottom: 185,
            right: 16,
            child: FloatingActionButton(
              heroTag: 'recenter_map_picker_fab',
              backgroundColor: cardBgColor,
              elevation: 4,
              onPressed: _recenterToCurrentLocation,
              child: const Icon(
                Icons.my_location_rounded,
                color: AppColors.primaryOrange,
                size: 24,
              ),
            ),
          ),

          // --- BOTTOM ADDRESS & CONFIRM CARD ---
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              decoration: BoxDecoration(
                color: cardBgColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isPickup ? 'Set pickup point' : 'Set drop point',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _resolving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryOrange),
                        )
                      : Text(
                          _address,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: textSecondary,
                          ),
                        ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: 'Confirm ${isPickup ? 'pickup' : 'drop'}',
                    onPressed: _resolving ? null : _confirm,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
