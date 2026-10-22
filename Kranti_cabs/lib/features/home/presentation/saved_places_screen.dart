import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../application/booking_controller.dart';
import '../application/booking_state.dart';
import '../application/home_providers.dart';
import '../application/saved_places_provider.dart';
import '../data/models/saved_address_model.dart';
import 'location_access.dart';

class SavedPlacesScreen extends ConsumerWidget {
  const SavedPlacesScreen({super.key});

  /// Books from the rider's location to the saved place.
  ///
  /// With location off this used to set a pickup labelled "415, Gandhi
  /// Nagar, Bengaluru" but placed at Indore's coordinates - the screen said
  /// Bengaluru while the booking was priced and dispatched in Indore. Now it
  /// asks for location, and failing that lets the rider choose the pickup on
  /// the map.
  Future<void> _onPlaceTap(BuildContext context, WidgetRef ref, SavedAddressModel place) async {
    var position = await ref.read(currentPositionProvider.future);
    if (position == null && context.mounted) {
      final ok = await requestLocationAccess(context, ref);
      if (ok) position = await ref.read(currentPositionProvider.future);
    }
    if (!context.mounted) return;

    BookingLocation? pickupLoc;
    if (position != null) {
      final address = await ref.read(currentAddressProvider.future);
      pickupLoc = BookingLocation(
        lat: position.latitude,
        lng: position.longitude,
        address: address.isNotEmpty ? address : 'Current location',
      );
    } else {
      final picked = await context.push<Map<String, dynamic>>(
        '/home/map-picker?type=pickup',
      );
      final address = (picked?['address'] ?? '').toString();
      final lat = (picked?['lat'] as num?)?.toDouble() ?? 0;
      final lng = (picked?['lng'] as num?)?.toDouble() ?? 0;
      if (address.isNotEmpty && !(lat == 0 && lng == 0)) {
        pickupLoc = BookingLocation(lat: lat, lng: lng, address: address);
      }
    }
    if (pickupLoc == null || !context.mounted) return;

    final dropLoc = BookingLocation(
      lat: place.lat,
      lng: place.lng,
      address: place.address.isNotEmpty ? place.address : place.label,
    );

    ref.read(bookingControllerProvider.notifier)
      ..setPickup(pickupLoc)
      ..setDrop(dropLoc)
      ..goToStep(BookingStep.selectingVehicle);

    context.push('/home/ride-types');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const bgColor = Color(0xFF11191D);
    const cardBgColor = Color(0xFF222222);
    const borderColor = Color(0xFF2E2E2E);
    const tealColor = Color(0xFFF5B400);
    const textSecondary = Color(0xFF94A3B8);

    final places = ref.watch(savedPlacesProvider);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Saved Places',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => _showAddSheet(context, ref),
            icon: const Icon(Icons.add_rounded, color: tealColor, size: 20),
            label: const Text(
              'Add',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: tealColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: places.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(
                          color: cardBgColor,
                          shape: BoxShape.circle,
                          border: Border.fromBorderSide(BorderSide(color: borderColor)),
                        ),
                        child: const Icon(
                          Icons.bookmark_border_rounded,
                          color: tealColor,
                          size: 36,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'No saved places yet',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Add your home, work, or favorite spots for faster booking.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: textSecondary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: 180,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: tealColor,
                            foregroundColor: const Color(0xFF0A0A0A),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: () => _showAddSheet(context, ref),
                          child: const Text(
                            'Add a Place',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: places.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final place = places[index];
                  final isHome = place.type.toLowerCase() == 'home' || place.label.toLowerCase() == 'home';
                  final isWork = place.type.toLowerCase() == 'work' || place.label.toLowerCase() == 'work';

                  final iconData = isHome
                      ? Icons.home_rounded
                      : isWork
                          ? Icons.work_rounded
                          : Icons.bookmark_rounded;
                  final iconColor = isHome
                      ? const Color(0xFFEF4444)
                      : isWork
                          ? const Color(0xFF1E88E5)
                          : tealColor;

                  return Container(
                    decoration: BoxDecoration(
                      color: cardBgColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      onTap: () => _onPlaceTap(context, ref, place),
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A0A0A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderColor),
                        ),
                        child: Icon(iconData, color: iconColor, size: 22),
                      ),
                      title: Text(
                        place.label,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      subtitle: Text(
                        place.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: textSecondary,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: textSecondary, size: 20),
                        onPressed: () {
                          ref.read(savedPlacesProvider.notifier).remove(place.id);
                          SnackbarUtils.info(context, 'Place removed');
                        },
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  void _showAddSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF11191D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 20,
          right: 20,
          top: 20,
        ),
        child: _AddPlaceForm(ref: ref),
      ),
    );
  }
}

/// A place suggestion: Google results carry a [placeId] (coordinates fetched
/// on pick), OpenStreetMap results carry [lat]/[lng] directly.
typedef _Suggestion = ({String title, String address, String placeId, double? lat, double? lng});

class _AddPlaceForm extends StatefulWidget {
  final WidgetRef ref;
  const _AddPlaceForm({required this.ref});

  @override
  State<_AddPlaceForm> createState() => _AddPlaceFormState();
}

class _AddPlaceFormState extends State<_AddPlaceForm> {
  final _labelController = TextEditingController();
  final _addressController = TextEditingController();
  String _type = 'other';
  bool _saving = false;

  // Google Places suggestions for the address field. A picked suggestion
  // carries its own coordinates, so saving skips the text geocoder.
  final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ),
  );
  Timer? _debounce;
  int _requestId = 0;
  List<_Suggestion> _suggestions = [];
  ({double lat, double lng})? _picked;

  void _onAddressChanged(String text) {
    _picked = null; // typed over a pick: its coordinates no longer apply
    _debounce?.cancel();
    if (text.trim().length < 3) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _fetchSuggestions(text.trim()));
  }

  Future<void> _fetchSuggestions(String input) async {
    final id = ++_requestId;
    var found = <_Suggestion>[];
    try {
      final res = await _dio.get(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json',
        queryParameters: {
          'input': input,
          'key': AppConstants.mapKey,
          'components': 'country:in',
        },
      );
      final list = res.data?['status'] == 'OK' ? res.data['predictions'] as List : const [];
      found = list.take(5).map<_Suggestion>((e) {
        final desc = (e['description'] ?? '').toString();
        final main = (e['structured_formatting']?['main_text'] ?? desc.split(',').first).toString();
        return (title: main, address: desc, placeId: (e['place_id'] ?? '').toString(), lat: null, lng: null);
      }).toList();
    } catch (_) {}

    // Google refuses without billing on the key; OpenStreetMap is the free fallback.
    if (found.isEmpty) {
      try {
        final res = await _dio.get(
          'https://nominatim.openstreetmap.org/search',
          queryParameters: {'q': input, 'format': 'json', 'limit': '5', 'countrycodes': 'in'},
          options: Options(headers: {'User-Agent': 'KrantiCabsUserApp/1.0 (flutter_taxi_user)'}),
        );
        found = (res.data as List)
            .map<_Suggestion?>((e) {
              final lat = double.tryParse('${e['lat']}');
              final lng = double.tryParse('${e['lon']}');
              if (lat == null || lng == null) return null;
              final full = (e['display_name'] ?? '').toString();
              final name = (e['name'] ?? '').toString();
              return (
                title: name.isNotEmpty ? name : full.split(',').first,
                address: full,
                placeId: '',
                lat: lat,
                lng: lng,
              );
            })
            .whereType<_Suggestion>()
            .toList();
      } catch (_) {}
    }
    if (mounted && id == _requestId) setState(() => _suggestions = found);
  }

  Future<void> _pickSuggestion(_Suggestion s) async {
    FocusScope.of(context).unfocus();
    _debounce?.cancel();
    _requestId++;
    setState(() {
      _addressController.text = s.address;
      _suggestions = [];
    });
    if (s.lat != null && s.lng != null) {
      _picked = (lat: s.lat!, lng: s.lng!);
      return;
    }
    try {
      final res = await _dio.get(
        'https://maps.googleapis.com/maps/api/place/details/json',
        queryParameters: {
          'place_id': s.placeId,
          'key': AppConstants.mapKey,
          'fields': 'geometry',
        },
      );
      final loc = res.data?['result']?['geometry']?['location'];
      if (loc != null && mounted) {
        _picked = (lat: (loc['lat'] as num).toDouble(), lng: (loc['lng'] as num).toDouble());
      }
    } catch (_) {
      // _save falls back to geocoding the address text.
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _labelController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const cardBgColor = Color(0xFF222222);
    const borderColor = Color(0xFF2E2E2E);
    const tealColor = Color(0xFFF5B400);
    const textSecondary = Color(0xFF94A3B8);

    return SingleChildScrollView(
      child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF334155),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 16),

        const Text(
          'Add Saved Place',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),

        // Type Selector Chips
        Row(
          children: [
            _buildTypeChip('Home', 'home', tealColor, cardBgColor, borderColor),
            const SizedBox(width: 8),
            _buildTypeChip('Work', 'work', tealColor, cardBgColor, borderColor),
            const SizedBox(width: 8),
            _buildTypeChip('Other', 'other', tealColor, cardBgColor, borderColor),
          ],
        ),
        const SizedBox(height: 16),

        // Label Input
        const Text(
          'Label Name',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textSecondary),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: cardBgColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: TextField(
            controller: _labelController,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            cursorColor: tealColor,
            decoration: const InputDecoration(
              isDense: true,
              filled: false,
              hintText: 'e.g. My Apartment / Gym',
              hintStyle: TextStyle(color: textSecondary, fontSize: 13.5),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Address Input
        const Text(
          'Address',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textSecondary),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: cardBgColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: TextField(
            controller: _addressController,
            onChanged: _onAddressChanged,
            textInputAction: TextInputAction.search,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            cursorColor: tealColor,
            decoration: const InputDecoration(
              isDense: true,
              filled: false,
              prefixIcon: Icon(Icons.search_rounded, color: textSecondary, size: 20),
              prefixIconConstraints: BoxConstraints(minWidth: 30),
              hintText: 'Search area, street or landmark',
              hintStyle: TextStyle(color: textSecondary, fontSize: 13.5),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: cardBgColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              children: [
                for (var i = 0; i < _suggestions.length; i++) ...[
                  if (i > 0) const Divider(height: 1, color: borderColor),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.location_on_outlined, color: tealColor, size: 20),
                    title: Text(
                      _suggestions[i].title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    subtitle: Text(
                      _suggestions[i].address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: textSecondary, fontSize: 12),
                    ),
                    onTap: () => _pickSuggestion(_suggestions[i]),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),

        // Save Button
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: tealColor,
              foregroundColor: const Color(0xFF0A0A0A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(color: Color(0xFF0A0A0A), strokeWidth: 2.4),
                  )
                : const Text(
                    'Save Place',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    ),
    );
  }

  Widget _buildTypeChip(String label, String value, Color tealColor, Color cardBgColor, Color borderColor) {
    final isSelected = _type == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _type = value;
          if (_labelController.text.isEmpty || _labelController.text == 'Home' || _labelController.text == 'Work') {
            _labelController.text = value == 'home' ? 'Home' : (value == 'work' ? 'Work' : '');
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0x33F5B400) : cardBgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? tealColor : borderColor, width: 1.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isSelected ? tealColor : Colors.white,
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final label = _labelController.text.trim();
    final address = _addressController.text.trim();
    if (label.isEmpty || address.isEmpty) {
      SnackbarUtils.info(context, 'Please enter label and address');
      return;
    }
    setState(() => _saving = true);
    try {
      var coords = _picked;
      if (coords == null) {
        final locations = await locationFromAddress(address);
        if (locations.isEmpty) throw Exception('Address not found');
        coords = (lat: locations.first.latitude, lng: locations.first.longitude);
      }
      await widget.ref.read(savedPlacesProvider.notifier).add(
            label: label,
            address: address,
            lat: coords.lat,
            lng: coords.lng,
            type: _type,
          );
      if (mounted) {
        Navigator.of(context).pop();
        SnackbarUtils.success(context, 'Place saved successfully!');
      }
    } catch (_) {
      if (mounted) {
        SnackbarUtils.error(context, 'Could not resolve address. Try a more specific location.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
