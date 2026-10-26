import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/primary_button.dart';
import '../application/destination_providers.dart';
import '../data/destination_mode.dart';
import 'home_map_picker_screen.dart';

/// Where the driver's home is, for Go Home (destination mode).
///
/// Set from the driver's current GPS position or a typed address; either way
/// the resolved address is shown for confirmation before saving. Home can be
/// moved any time unless the admin sets a waiting period, in which case the
/// screen says when (`canChangeHomeAt`).
class HomeLocationScreen extends ConsumerStatefulWidget {
  const HomeLocationScreen({super.key});

  @override
  ConsumerState<HomeLocationScreen> createState() => _HomeLocationScreenState();
}

class _HomeLocationScreenState extends ConsumerState<HomeLocationScreen> {
  bool _busy = false;

  @override
  void dispose() {
    super.dispose();
  }

  String _describe(Placemark p) => [p.name, p.subLocality, p.locality, p.postalCode]
      .whereType<String>()
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet()
      .join(', ');

  Future<void> _useCurrentLocation() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final location = ref.read(locationServiceProvider);
      final permission = await location.ensurePermission();
      if (!permission.granted) {
        SnackbarUtils.error('Allow location access to use where you are now.');
        return;
      }
      final position = await location.getCurrentPosition();
      var address = '';
      try {
        final places = await placemarkFromCoordinates(position.latitude, position.longitude);
        if (places.isNotEmpty) address = _describe(places.first);
      } catch (_) {
        // A name is a nicety; the point is what matters.
      }
      await _confirmAndSave(position.latitude, position.longitude, address.isEmpty ? 'Home' : address);
    } catch (_) {
      SnackbarUtils.error('Could not get your location. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Search with suggestions, or drag the map under a pin.
  Future<void> _pickOnMap() async {
    if (_busy) return;
    final picked = await Navigator.of(context).push<PickedPlace>(
      MaterialPageRoute(builder: (_) => const HomeMapPickerScreen()),
    );
    if (picked == null || !mounted) return;
    await _confirmAndSave(picked.lat, picked.lng, picked.address);
  }

  Future<void> _confirmAndSave(double lat, double lng, String address) async {
    final info = ref.read(destinationModeProvider).valueOrNull;
    final currentHome = (info != null && info.hasHome) ? info.homeAddress : '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save as home?'),
        content: Text(
          currentHome.isNotEmpty ? '$address\n\nThis replaces your current home ($currentHome).' : address,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Save')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(destinationModeProvider.notifier).setHome(lat: lat, lng: lng, address: address);
      SnackbarUtils.success('Home saved');
    } on ApiException catch (error) {
      SnackbarUtils.error(error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(destinationModeProvider).valueOrNull ?? DestinationModeInfo.none;
    // Only a date still ahead is a lock: the server may keep sending a past one,
    // which used to leave both buttons disabled for good.
    final locked = info.canChangeHomeAt != null && info.canChangeHomeAt!.isAfter(DateTime.now());

    return Scaffold(
      appBar: const CustomAppBar(title: 'Home Location'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4CC),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.home_rounded, color: Color(0xFFB45309)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.hasHome ? 'Your home' : 'No home saved yet',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        info.hasHome
                            ? (info.homeAddress.isEmpty ? 'Saved' : info.homeAddress)
                            : 'Save it once, then tap Go Home on the home screen to get only rides on your way there.',
                        style: const TextStyle(color: Color(0xFF475569), fontSize: 13),
                      ),
                      if (locked) ...[
                        const SizedBox(height: 8),
                        Text(
                          'You can move home again from ${MaterialLocalizations.of(context).formatMediumDate(info.canChangeHomeAt!.toLocal())}.',
                          style: const TextStyle(color: Color(0xFFB45309), fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            label: 'Use where I am now',
            icon: Icons.my_location_rounded,
            loading: _busy,
            onPressed: locked ? null : _useCurrentLocation,
          ),
          const SizedBox(height: 20),
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'Search address or pin on map',
            icon: Icons.map_rounded,
            color: AppColors.accent,
            onPressed: locked ? null : _pickOnMap,
          ),
        ],
      ),
    );
  }
}
