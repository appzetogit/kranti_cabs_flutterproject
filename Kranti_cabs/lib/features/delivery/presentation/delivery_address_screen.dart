import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../auth/application/auth_providers.dart';
import '../../home/application/booking_state.dart';
import '../../home/application/home_providers.dart';
import '../../home/application/recent_searches_provider.dart';
import '../application/delivery_booking_controller.dart';
import 'delivery_contacts_sheet.dart';

class _Suggestion {
  final String title;
  final String address;
  final String placeId;
  final double lat;
  final double lng;
  const _Suggestion({
    required this.title,
    required this.address,
    required this.placeId,
    this.lat = 0.0,
    this.lng = 0.0,
  });
}

/// Step 2: Details & Address Screen matching user's exact reference UI.
class DeliveryAddressScreen extends ConsumerStatefulWidget {
  const DeliveryAddressScreen({super.key});

  @override
  ConsumerState<DeliveryAddressScreen> createState() =>
      _DeliveryAddressScreenState();
}

class _DeliveryAddressScreenState extends ConsumerState<DeliveryAddressScreen> {
  final _dropController = TextEditingController();
  Timer? _debounce;
  List<_Suggestion> _results = [];
  bool _searching = false;
  bool _booking = false;
  String _sessionToken = '';

  @override
  void initState() {
    super.initState();
    final state = ref.read(deliveryBookingProvider);
    if (state.drop != null) _dropController.text = state.drop!.address;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(authControllerProvider).user;
      ref
          .read(deliveryBookingProvider.notifier)
          .prefillSenderFrom(name: user?.name, phone: user?.phone);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _dropController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      if (!mounted) return;
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _search(query.trim()),
    );
  }

  Future<void> _search(String query) async {
    setState(() => _searching = true);
    if (_sessionToken.isEmpty) {
      _sessionToken = DateTime.now().microsecondsSinceEpoch.toString();
    }

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ),
    );

    // Bias results toward the sender's pickup area (same city) so the matches
    // are nearby and precise rather than prominent places from across India.
    // location+radius is a soft bias in the Autocomplete API (not a hard
    // restriction unless strictbounds=true, which we deliberately omit), so a
    // genuinely distant exact match can still surface.
    final pickup = ref.read(deliveryBookingProvider).pickup;
    final biasLat = pickup?.lat;
    final biasLng = pickup?.lng;

    // 1. Google Places Autocomplete API
    try {
      final response = await dio.get(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json',
        queryParameters: {
          'input': query,
          'key': AppConstants.mapKey,
          'sessiontoken': _sessionToken,
          'components': 'country:in',
          if (biasLat != null && biasLng != null) 'location': '$biasLat,$biasLng',
          if (biasLat != null && biasLng != null) 'radius': '50000',
        },
      );

      if (response.data?['status'] == 'OK') {
        final predictions = response.data['predictions'] as List;
        final suggestions = predictions
            .map(
              (p) => _Suggestion(
                title:
                    (p['structured_formatting']?['main_text'] ??
                            (p['description'] ?? '')
                                .toString()
                                .split(',')
                                .first)
                        .toString(),
                address: (p['description'] ?? '').toString(),
                placeId: (p['place_id'] ?? '').toString(),
              ),
            )
            .toList();

        if (suggestions.isNotEmpty) {
          if (!mounted) return;
          setState(() {
            _results = suggestions;
            _searching = false;
          });
          return;
        }
      }
    } catch (_) {}

    // 2. Fallback: Nominatim API
    try {
      final response = await dio.get(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {
          'q': query,
          'format': 'json',
          'addressdetails': '1',
          'limit': '10',
          'countrycodes': 'in',
          // Soft-bias toward a ~1° box around the pickup (bounded=0 keeps it a
          // preference, not a hard cut) so nearby results rank first here too.
          if (biasLat != null && biasLng != null)
            'viewbox': '${biasLng - 0.5},${biasLat + 0.5},${biasLng + 0.5},${biasLat - 0.5}',
          if (biasLat != null && biasLng != null) 'bounded': '0',
        },
        options: Options(
          headers: {'User-Agent': 'KrantiCabsUserApp/1.0 (flutter_taxi_user)'},
        ),
      );

      if (response.data != null &&
          response.data is List &&
          (response.data as List).isNotEmpty) {
        final items = response.data as List;
        final suggestions = <_Suggestion>[];
        for (final item in items) {
          final name = (item['name'] ?? '').toString();
          final displayName = (item['display_name'] ?? '').toString();
          final lat = double.tryParse(item['lat']?.toString() ?? '') ?? 0.0;
          final lon = double.tryParse(item['lon']?.toString() ?? '') ?? 0.0;
          final title = name.isNotEmpty
              ? name
              : (displayName.isNotEmpty ? displayName.split(',').first : query);

          if (displayName.isNotEmpty && (lat != 0.0 || lon != 0.0)) {
            suggestions.add(
              _Suggestion(
                title: title,
                address: displayName,
                placeId: '',
                lat: lat,
                lng: lon,
              ),
            );
          }
        }

        if (mounted && suggestions.isNotEmpty) {
          if (!mounted) return;
          setState(() {
            _results = suggestions;
            _searching = false;
          });
          return;
        }
      }
    } catch (_) {}

    // 3. Fallback: Photon API
    try {
      final response = await dio.get(
        'https://photon.komoot.io/api/',
        queryParameters: {'q': query, 'limit': '10'},
      );

      if (response.data != null && response.data['features'] != null) {
        final features = response.data['features'] as List;
        final suggestions = <_Suggestion>[];
        for (final item in features) {
          final props = item['properties'] ?? {};
          final coords = item['geometry']?['coordinates'] as List?;
          final name = (props['name'] ?? props['street'] ?? query).toString();
          final city =
              (props['city'] ?? props['district'] ?? props['state'] ?? '')
                  .toString();
          final country = (props['country'] ?? '').toString();
          final addressParts = [
            name,
            props['street']?.toString(),
            city,
            country,
          ].where((s) => s != null && s.isNotEmpty).toSet().join(', ');

          final lon = (coords != null && coords.isNotEmpty)
              ? (coords[0] as num).toDouble()
              : 0.0;
          final lat = (coords != null && coords.length > 1)
              ? (coords[1] as num).toDouble()
              : 0.0;

          if (lat != 0.0 || lon != 0.0) {
            suggestions.add(
              _Suggestion(
                title: name.isNotEmpty ? name : query,
                address: addressParts.isNotEmpty ? addressParts : name,
                placeId: '',
                lat: lat,
                lng: lon,
              ),
            );
          }
        }

        if (mounted && suggestions.isNotEmpty) {
          if (!mounted) return;
          setState(() {
            _results = suggestions;
            _searching = false;
          });
          return;
        }
      }
    } catch (_) {}

    if (mounted)
      setState(() {
        _results = [];
        _searching = false;
      });
  }

  Future<void> _selectSuggestion(_Suggestion suggestion) async {
    FocusScope.of(context).unfocus();
    double lat = suggestion.lat;
    double lng = suggestion.lng;

    if (suggestion.placeId.isNotEmpty) {
      try {
        final response = await Dio().get(
          'https://maps.googleapis.com/maps/api/place/details/json',
          queryParameters: {
            'place_id': suggestion.placeId,
            'key': AppConstants.mapKey,
            'sessiontoken': _sessionToken,
            'fields': 'formatted_address,geometry',
          },
        );
        _sessionToken = '';

        if (response.data?['status'] == 'OK') {
          final location = response.data['result']['geometry']['location'];
          lat = (location['lat'] as num).toDouble();
          lng = (location['lng'] as num).toDouble();
        }
      } catch (_) {}
    }

    if (lat == 0 && lng == 0) {
      try {
        final response =
            await Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 4),
                receiveTimeout: const Duration(seconds: 4),
              ),
            ).get(
              'https://nominatim.openstreetmap.org/search',
              queryParameters: {
                'q': suggestion.address.isNotEmpty
                    ? suggestion.address
                    : suggestion.title,
                'format': 'json',
                'limit': '1',
              },
              options: Options(
                headers: {'User-Agent': 'KrantiCabsUserApp/1.0 (flutter_taxi_user)'},
              ),
            );
        if (response.data != null &&
            response.data is List &&
            (response.data as List).isNotEmpty) {
          final first = (response.data as List).first;
          lat = double.tryParse(first['lat']?.toString() ?? '') ?? 0.0;
          lng = double.tryParse(first['lon']?.toString() ?? '') ?? 0.0;
        }
      } catch (_) {}
    }

    if (lat == 0 && lng == 0) {
      // Last resort. Nominatim rate-limits aggressively and returns nothing
      // rather than an error when it throttles, so one more free provider is
      // the difference between a booking and a dead end.
      try {
        final response =
            await Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 4),
                receiveTimeout: const Duration(seconds: 4),
              ),
            ).get(
              'https://photon.komoot.io/api/',
              queryParameters: {
                'q': suggestion.address.isNotEmpty
                    ? suggestion.address
                    : suggestion.title,
                'limit': '1',
              },
            );
        final features = response.data?['features'] as List?;
        // Pulled apart rather than written as one ternary: `as List?` directly
        // before a `:` reads as the start of a conditional to the parser.
        List? coords;
        if (features != null && features.isNotEmpty) {
          coords = features.first['geometry']?['coordinates'] as List?;
        }
        if (coords != null && coords.length >= 2) {
          lng = double.tryParse('${coords[0]}') ?? 0.0;
          lat = double.tryParse('${coords[1]}') ?? 0.0;
        }
      } catch (_) {}
    }

    if (lat == 0 && lng == 0) {
      if (mounted) {
        SnackbarUtils.error(
          context,
          'Could not find ${suggestion.title}. Try picking it on the map.',
        );
      }
      return;
    }

    ref
        .read(recentSearchesProvider.notifier)
        .add(address: suggestion.address, lat: lat, lng: lng);
    ref
        .read(deliveryBookingProvider.notifier)
        .setDrop(
          BookingLocation(lat: lat, lng: lng, address: suggestion.address),
        );

    if (!mounted) return;
    setState(() {
      _dropController.text = suggestion.address;
      _results = [];
    });
  }

  Future<void> _confirm() async {
    final state = ref.read(deliveryBookingProvider);

    if (state.drop == null) {
      SnackbarUtils.info(context, 'Choose where the parcel is going');
      return;
    }

    setState(() => _booking = true);
    try {
      if (!state.hasSender || !state.hasReceiver) {
        final saved = await DeliveryContactsSheet.show(context);
        if (!saved) return;
      }

      if (!mounted) return;

      // What is in the box, how heavy, and what it looks like. On its own
      // screen rather than in the contacts sheet because the photos need the
      // room, and skipped once filled in so a failed booking does not ask
      // twice.
      if (!ref.read(deliveryBookingProvider).hasParcelDetails) {
        final saved = await context.push<bool>('/delivery/details');
        if (saved != true || !mounted) return;
      }

      // Pricing and the actual vehicle choice both happen on the next screen
      // — this address/contacts step no longer picks a vehicle or fetches a
      // fare itself, so there is nothing left to wait on here.
      if (!mounted) return;
      await context.push('/delivery/vehicle-select');
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final state = ref.watch(deliveryBookingProvider);
    final recents = ref.watch(recentSearchesProvider);
    final addressAsync = ref.watch(currentAddressProvider);
    // '' means location is off; say so rather than "Fetching" forever.
    final currentAddr = addressAsync.isLoading
        ? 'Finding your location...'
        : ((addressAsync.valueOrNull ?? '').isNotEmpty
            ? addressAsync.valueOrNull!
            : 'Location off - enter pickup');
    final pickupAddressToDisplay =
        (state.pickup?.address != null && state.pickup!.address.isNotEmpty)
        ? state.pickup!.address
        : currentAddr;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0F172A)
          : const Color(0xFFF6F8FC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Material(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            shape: const CircleBorder(),
            elevation: 1,
            child: IconButton(
              icon: Icon(
                Icons.arrow_back,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                size: 20,
              ),
              onPressed: () => Navigator.of(context).maybePop(),
              constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
              padding: EdgeInsets.zero,
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              state.vehicleName.isEmpty
                  ? 'PARCEL DELIVERY'
                  : state.vehicleName.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w800,
                color: isDark
                    ? const Color(0xFF60A5FA)
                    : const Color(0xFF2563EB),
              ),
            ),
            Text(
              'Details & Address',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                //physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                children: [
                  // Top Pickup & Deliver To Route Box
                  _RouteCard(
                    pickup: pickupAddressToDisplay,
                    dropController: _dropController,
                    onDropChanged: _onQueryChanged,
                    onClearDrop: () {
                      if (!mounted) return;
                      setState(() {
                        _dropController.clear();
                        _results = [];
                      });
                      ref.read(deliveryBookingProvider.notifier).clearDrop();
                    },
                  ),

                  const SizedBox(height: 12),

                  // Pin on Map & Contact Details Action Row
                  _ActionRow(
                    onPinMap: () async {
                      final result = await context.push(
                        '/home/map-picker?type=drop',
                      );
                      if (result is Map && mounted) {
                        final lat = (result['lat'] as num).toDouble();
                        final lng = (result['lng'] as num).toDouble();
                        final address = (result['address'] ?? '').toString();

                        if (address.isNotEmpty) {
                          ref
                              .read(recentSearchesProvider.notifier)
                              .add(address: address, lat: lat, lng: lng);
                          ref
                              .read(deliveryBookingProvider.notifier)
                              .setDrop(
                                BookingLocation(
                                  lat: lat,
                                  lng: lng,
                                  address: address,
                                ),
                              );

                          if (!mounted) return;
                          setState(() {
                            _dropController.text = address;
                            _results = [];
                          });
                        }
                      }
                    },
                    onContacts: () async {
                      await DeliveryContactsSheet.show(context);
                      if (mounted) setState(() {});
                    },
                  ),

                  const SizedBox(height: 14),

                  // Sender Info Card
                  _SenderInfoCard(
                    senderName: state.senderName.isEmpty
                        ? 'Add sender name'
                        : state.senderName,
                    senderMobile: state.senderMobile.isEmpty
                        ? ''
                        : state.senderMobile,
                    onEdit: () async {
                      await DeliveryContactsSheet.show(context);
                      if (mounted) setState(() {});
                    },
                  ),

                  const SizedBox(height: 20),

                  // Search Results if typing
                  if (_searching)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (_results.isNotEmpty) ...[
                    const _GroupHeader(title: 'SEARCH RESULTS'),
                    ..._results.map(
                      (r) => _SuggestionTile(
                        title: r.title,
                        subtitle: r.address,
                        onTap: () => _selectSuggestion(r),
                      ),
                    ),
                  ] else ...[
                    // Recents list if available — no more hardcoded
                    // "Suggestions"/"Popular Locations" chips; those pointed
                    // at a fixed set of Indore landmarks regardless of what
                    // city the rider is actually in.
                    if (recents.isNotEmpty) ...[
                      const _SubHeader(title: 'RECENT SEARCHES'),
                      const SizedBox(height: 6),
                      ...recents.map(
                        (place) => _SuggestionTile(
                          title: place.address.split(',').first,
                          subtitle: place.address,
                          onTap: () {
                            ref
                                .read(deliveryBookingProvider.notifier)
                                .setDrop(
                                  BookingLocation(
                                    lat: place.lat,
                                    lng: place.lng,
                                    address: place.address,
                                  ),
                                );
                            setState(
                              () => _dropController.text = place.address,
                            );
                          },
                        ),
                      ),
                    ],
                  ],

                  const SizedBox(
                    height: 80,
                  ), // Padding for sticky bottom button
                ],
              ),
            ),
          ],
        ),
      ),
      bottomSheet: Container(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF6F8FC),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: isDark
                  ? const Color(0xFF2563EB)
                  : const Color(0xFF0F172A),
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
            onPressed: (state.drop != null && !_booking) || state.drop == null
                ? () {
                    if (state.drop == null) {
                      SnackbarUtils.info(
                        context,
                        'Please select or search drop location',
                      );
                    } else {
                      _confirm();
                    }
                  }
                : null,
            child: _booking
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        state.drop == null
                            ? 'Select Drop Location'
                            : 'Confirm Receiver Details',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Route Box Card containing Pickup Address & Drop Search Box
class _RouteCard extends StatelessWidget {
  final String pickup;
  final TextEditingController dropController;
  final ValueChanged<String> onDropChanged;
  final VoidCallback onClearDrop;

  const _RouteCard({
    required this.pickup,
    required this.dropController,
    required this.onDropChanged,
    required this.onClearDrop,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: isDark ? Border.all(color: const Color(0xFF334155)) : null,
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black38 : const Color(0x0C000000),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Pickup Row
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF10B981), width: 3),
                ),
                child: Center(
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PICK UP FROM',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 0.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      pickup,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Connecting Vertical Line
          Padding(
            padding: const EdgeInsets.only(left: 10, top: 4, bottom: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 2,
                height: 18,
                color: isDark
                    ? const Color(0xFF475569)
                    : const Color(0xFFCBD5E1),
              ),
            ),
          ),

          // Deliver To Row
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primaryOrange, width: 3),
                ),
                child: Center(
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryOrange,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF3B82F6)
                          : const Color(0xFF2563EB),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'DELIVER TO',
                              style: TextStyle(
                                fontSize: 9.5,
                                letterSpacing: 0.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                            TextField(
                              controller: dropController,
                              onChanged: onDropChanged,
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.only(
                                  top: 2,
                                  bottom: 2,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                                errorBorder: InputBorder.none,
                                focusedErrorBorder: InputBorder.none,
                                hintText: 'Search drop location...',
                                hintStyle: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (dropController.text.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: onClearDrop,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF334155)
                                  : const Color(0xFFF1F5F9),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B),
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Action Row with "Pin on map" and "Contact Details" buttons
class _ActionRow extends StatelessWidget {
  final VoidCallback onPinMap;
  final VoidCallback onContacts;

  const _ActionRow({required this.onPinMap, required this.onContacts});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        // Pin on Map Button
        Expanded(
          child: InkWell(
            onTap: onPinMap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: isDark
                    ? Border.all(color: const Color(0xFF334155))
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: isDark ? Colors.black26 : const Color(0x0A000000),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    color: isDark
                        ? const Color(0xFF60A5FA)
                        : const Color(0xFF2563EB),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Pin on map',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Contact Details Button
        Expanded(
          child: InkWell(
            onTap: onContacts,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: isDark
                    ? Border.all(color: const Color(0xFF334155))
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: isDark ? Colors.black26 : const Color(0x0A000000),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.person_outline_rounded,
                    color: isDark
                        ? const Color(0xFF60A5FA)
                        : const Color(0xFF2563EB),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Contact Details',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Sender Info Box with left blue accent line & EDIT pill button
class _SenderInfoCard extends StatelessWidget {
  final String senderName;
  final String senderMobile;
  final VoidCallback onEdit;

  const _SenderInfoCard({
    required this.senderName,
    required this.senderMobile,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final phoneStr = senderMobile.isNotEmpty ? ' ($senderMobile)' : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(20),
        border: Border(
          left: BorderSide(
            color: isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB),
            width: 4,
          ),
        ),
      ),
      child: Row(
        children: [
          // Green dot indicator
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF10B981),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),

          // Sender text label
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'SENDER: ',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                  TextSpan(
                    text: '$senderName$phoneStr',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // EDIT pill button
          InkWell(
            onTap: onEdit,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF334155) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: isDark ? Colors.black26 : const Color(0x0A000000),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                'EDIT',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: isDark
                      ? const Color(0xFF60A5FA)
                      : const Color(0xFF2563EB),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String title;
  const _GroupHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 11,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w800,
        color: Color(0xFF94A3B8),
      ),
    );
  }
}

class _SubHeader extends StatelessWidget {
  final String title;
  const _SubHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 10,
        letterSpacing: 0.6,
        fontWeight: FontWeight.w800,
        color: Color(0xFF94A3B8),
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _SuggestionTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: isDark
            ? const Color(0xFF334155)
            : const Color(0xFFE2E8F0),
        child: Icon(
          Icons.location_on_outlined,
          size: 17,
          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
        ),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 13.5,
          color: isDark ? Colors.white : const Color(0xFF0F172A),
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11.5,
          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
        ),
      ),
      onTap: onTap,
    );
  }
}
