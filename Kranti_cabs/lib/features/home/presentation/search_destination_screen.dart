import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../application/booking_controller.dart';
import '../application/booking_state.dart';
import '../application/home_providers.dart';
import '../application/location_aware_ranking_service.dart';
import '../application/recent_searches_provider.dart';
import 'location_access.dart';

class _GeoResult {
  final String title;
  final String address;
  final double lat;
  final double lng;
  final String? placeId;

  /// Distance from the rider's current location, filled in by
  /// [_SearchDestinationScreenState._rankAndAnnotate] once ranking runs —
  /// null for a provider/candidate where either the candidate's coordinates
  /// or the current location aren't known. Not sent by any provider itself.
  final double? distanceMeters;

  const _GeoResult({
    required this.title,
    required this.address,
    required this.lat,
    required this.lng,
    this.placeId,
    this.distanceMeters,
  });

  _GeoResult withDistance(double? meters) => _GeoResult(
    title: title,
    address: address,
    lat: lat,
    lng: lng,
    placeId: placeId,
    distanceMeters: meters,
  );
}

enum FieldTargetType { pickup, drop, stop }

class FieldTarget {
  final FieldTargetType type;
  final int? stopIndex;
  const FieldTarget.pickup() : type = FieldTargetType.pickup, stopIndex = null;
  const FieldTarget.drop() : type = FieldTargetType.drop, stopIndex = null;
  const FieldTarget.stop(int index)
    : type = FieldTargetType.stop,
      stopIndex = index;
}

class SearchDestinationScreen extends ConsumerStatefulWidget {
  final String? title;

  /// Set when the rider arrived from the Outstation module, which switches the
  /// booking to the intercity tariff.
  final bool isOutstation;

  /// The app module the rider tapped, so the vehicle list can be limited to
  /// what that module offers.
  final String? moduleId;

  const SearchDestinationScreen({
    super.key,
    this.title,
    this.isOutstation = false,
    this.moduleId,
  });

  @override
  ConsumerState<SearchDestinationScreen> createState() =>
      _SearchDestinationScreenState();
}

class _SearchDestinationScreenState
    extends ConsumerState<SearchDestinationScreen> {
  final _pickupController = TextEditingController();
  final _dropController = TextEditingController();
  final _pickupFocus = FocusNode();
  final _dropFocus = FocusNode();
  final List<TextEditingController> _stopControllers = [];
  final List<BookingLocation?> _stops = [];

  Timer? _debounce;
  List<_GeoResult> _results = [];
  bool _searching = false;

  /// Bumped at the start of every [_search] call; a response only gets
  /// applied if this still matches when it arrives. Without this, a slower
  /// older request's response could land after a faster newer one's and
  /// silently replace the results the rider is actually looking at.
  int _searchGeneration = 0;

  /// GPS accuracy (meters) of [_pickup]'s coordinates, from the same
  /// position fix already fetched in [_prefillCurrentLocation] — reused
  /// rather than requesting location again just for search ranking. Null
  /// means unknown, treated as trustworthy (no accuracy to doubt); the
  /// ranking service itself only distrusts a fix once it has an actual
  /// number to compare against a threshold.
  double? _currentAccuracy;
  FieldTarget _activeTarget = const FieldTarget.drop();

  /// Mirrors the booking controller so the toggle reflects the real choice.
  /// This used to be screen-local state that nothing ever read, so picking
  /// Round Trip changed the colours and nothing else.
  TripType _tripType = TripType.oneWay;

  /// The rider's chosen return date/time for a round-trip outstation ride.
  DateTime? _returnAt;

  /// When an outstation trip leaves; null is "now". Booked as the ride's
  /// `scheduledAt`, so a later trip reaches drivers as a scheduled ride (their
  /// Scheduled Rides list) instead of a ride-now request.
  DateTime? _leaveAt;

  /// Earliest pickup a rider can schedule, as on Ola / Uber. The server takes
  /// anything 15 minutes out; this leaves room for the time spent booking.
  static const _minScheduleLead = Duration(minutes: 30);

  void _selectTripType(TripType next) {
    setState(() {
      _tripType = next;
      // A one-way trip has no return leg; forget any return time picked earlier.
      if (next != TripType.roundTrip) _returnAt = null;
    });
    ref.read(bookingControllerProvider.notifier).setTripType(next, byRider: true);
  }

  Future<DateTime?> _pickDateTime({
    required DateTime initial,
    required DateTime first,
    required DateTime last,
  }) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first) ? first : initial,
      firstDate: DateTime(first.year, first.month, first.day),
      lastDate: last,
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  /// Date + time the outstation trip leaves. At least [_minScheduleLead] out,
  /// up to 30 days.
  Future<void> _pickLeaveDateTime() async {
    final now = DateTime.now();
    final earliest = now.add(_minScheduleLead);
    final picked = await _pickDateTime(
      initial: _leaveAt ?? earliest.add(const Duration(minutes: 30)),
      first: earliest,
      last: now.add(const Duration(days: 30)),
    );
    if (picked == null || !mounted) return;
    if (picked.isBefore(DateTime.now().add(_minScheduleLead))) {
      SnackbarUtils.error(context, 'Pick a time at least 30 minutes from now, or leave now');
      return;
    }
    setState(() {
      _leaveAt = picked;
      // A return before the new departure no longer makes sense.
      if (_returnAt != null && !_returnAt!.isAfter(picked)) _returnAt = null;
    });
    final booking = ref.read(bookingControllerProvider.notifier);
    booking.setScheduledAt(picked);
    if (_returnAt == null) booking.setReturnAt(null);
  }

  void _leaveNow() {
    setState(() => _leaveAt = null);
    ref.read(bookingControllerProvider.notifier).setScheduledAt(null);
  }

  /// Date + time picker for the return leg of a round-trip outstation ride:
  /// after the departure.
  Future<void> _pickReturnDateTime() async {
    final start = _leaveAt ?? DateTime.now();
    final picked = await _pickDateTime(
      initial: _returnAt ?? start.add(const Duration(days: 1)),
      first: start,
      last: start.add(const Duration(days: 30)),
    );
    if (picked == null || !mounted) return;
    if (!picked.isAfter(start.add(const Duration(hours: 1)))) {
      SnackbarUtils.error(context, 'The return has to be at least an hour after you leave');
      return;
    }
    setState(() => _returnAt = picked);
    ref.read(bookingControllerProvider.notifier).setReturnAt(picked);
  }

  /// A tappable "label / value" row for the outstation departure and return.
  /// [onClear] adds an X that resets it (the departure back to "Now").
  Widget _dateTimeRow({
    required IconData icon,
    required String label,
    required String value,
    required bool highlighted,
    required VoidCallback onTap,
    VoidCallback? onClear,
    required Color cardBgColor,
    required Color borderColor,
    required Color accent,
    required Color textSecondary,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: highlighted ? const Color(0xFF044B47) : cardBgColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: highlighted ? accent : borderColor, width: 1.5),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textSecondary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: highlighted ? Colors.white : Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              if (onClear != null)
                GestureDetector(
                  onTap: onClear,
                  child: Icon(Icons.close_rounded, size: 20, color: textSecondary),
                )
              else
                Icon(Icons.chevron_right_rounded, size: 20, color: textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  String _formatReturnDateTime(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '${dt.day} ${months[dt.month - 1]}, $hour12:$minute $period';
  }

  BookingLocation? _pickup;
  BookingLocation? _drop;
  String _sessionToken = '';

  /// True when the pickup could not be filled from the rider's location -
  /// location off, or not allowed. Shows the prompt to turn it on, and keeps
  /// the pickup empty rather than inventing one.
  bool _locationUnavailable = false;

  void _ensureSessionToken() {
    if (_sessionToken.isEmpty) {
      _sessionToken =
          '${DateTime.now().millisecondsSinceEpoch}_${1000 + (DateTime.now().microsecondsSinceEpoch % 9000)}';
    }
  }

  List<_GeoResult> _nearestAirports = [];
  bool _loadingAirports = false;

  bool get _isAirportMode =>
      (widget.title ?? '').toLowerCase().contains('airport');
  bool get _isRailwayMode =>
      (widget.title ?? '').toLowerCase().contains('railway');
  // Airport and railway share the "nearest 3" list; only the search differs.
  bool get _isNearestMode => _isAirportMode || _isRailwayMode;

  List<_GeoResult> _fallbackNearest(double lat, double lng) => _isRailwayMode
      ? _getFallbackStationsForLocation(lat, lng)
      : _getFallbackAirportsForLocation(lat, lng);

  List<_GeoResult> _getFallbackStationsForLocation(double lat, double lng) {
    if (lat >= 21.0 && lat <= 24.0 && lng >= 74.0 && lng <= 80.5) {
      return const [
        _GeoResult(
          title: 'Indore Junction (INDB)',
          address: 'Jawahar Marg, Indore, Madhya Pradesh',
          lat: 22.7196,
          lng: 75.8681,
        ),
        _GeoResult(
          title: 'Bhopal Junction (BPL)',
          address: 'Hamidia Road, Bhopal, Madhya Pradesh',
          lat: 23.2685,
          lng: 77.4126,
        ),
        _GeoResult(
          title: 'Jabalpur Junction (JBP)',
          address: 'Jabalpur, Madhya Pradesh',
          lat: 23.1636,
          lng: 79.9498,
        ),
      ];
    }
    return const [
      _GeoResult(
        title: 'New Delhi Railway Station (NDLS)',
        address: 'Paharganj, New Delhi',
        lat: 28.6431,
        lng: 77.2197,
      ),
      _GeoResult(
        title: 'Chhatrapati Shivaji Maharaj Terminus (CSMT)',
        address: 'Fort, Mumbai, Maharashtra',
        lat: 18.9398,
        lng: 72.8355,
      ),
      _GeoResult(
        title: 'KSR Bengaluru City Junction (SBC)',
        address: 'Majestic, Bengaluru',
        lat: 12.9784,
        lng: 77.5726,
      ),
    ];
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _pickupController.addListener(_onTextChanged);
    _dropController.addListener(_onTextChanged);
    _pickupFocus.addListener(_onFocusChanged);
    _dropFocus.addListener(_onFocusChanged);
    _prefillCurrentLocation();

    // Location can arrive after this screen opened: the rider turned GPS on
    // from the quick settings panel, or allowed it in Settings and came back.
    // Fill the pickup then, unless they have already chosen one themselves.
    ref.listenManual(currentPositionProvider, (previous, next) {
      if (next.valueOrNull != null && _pickup == null) {
        _prefillCurrentLocation();
      }
    });

    // Applied once on entry so the whole downstream flow — vehicle list, fare,
    // confirm, and the created ride's serviceType — knows which tariff to use.
    // A round trip is the common case for intercity travel, so it is the
    // default there; the rider can still switch with the toggle below.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final booking = ref.read(bookingControllerProvider.notifier);
      // The Home screen's plain search bar and its static "Zi City Ride" /
      // "Zi Airport" / etc. tiles only ever had a `title` to give this screen
      // — never a real `moduleId` — because that id only exists once the
      // backend's module catalog loads. Without one, the vehicle list downstream
      // shows every vehicle in the whole catalog regardless of which tile was
      // tapped. Resolving it here, from the same catalog the dynamic module
      // grid already uses, is what makes those static entry points scope the
      // list correctly too.
      final resolvedModuleId =
          widget.moduleId ?? await _resolveModuleIdFromTitle(widget.title);
      if (!mounted) return;
      booking.setModule(resolvedModuleId);
      // The tile's choice: an Outstation tile stays outstation even when the
      // server classifies the trip as city.
      booking.chooseOutstation(widget.isOutstation);
      // Set on every entry, not only for outstation. The booking controller
      // outlives this screen, so a Round Trip picked on an earlier search
      // stayed in force on the next city ride - the toggle showed One Way
      // while the fare charged every kilometre twice.
      final initialTripType =
          widget.isOutstation ? TripType.roundTrip : TripType.oneWay;
      setState(() {
        _tripType = initialTripType;
        _leaveAt = null;
        _returnAt = null;
      });
      booking.setTripType(initialTripType);
      // A fresh search starts as a ride now: a time or return picked on an
      // earlier booking must not carry over (the controller outlives this
      // screen).
      booking.setScheduledAt(null);
      booking.setReturnAt(null);
    });
  }

  /// Matches [title] against the real module catalog by name — case- and
  /// whitespace-insensitively, since "Zi City Ride" here has to line up with
  /// whatever an admin actually typed as the module's name. Not gated on
  /// `module.active`: that flag only controls whether a tile is shown on the
  /// home screen, not which vehicles belong to the module a rider already
  /// chose to search under.
  Future<String?> _resolveModuleIdFromTitle(String? title) async {
    final normalized = title?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    try {
      final modules = await ref.read(appModulesProvider.future);
      for (final module in modules) {
        final modName = module.name.trim().toLowerCase();
        if (modName == normalized ||
            modName.replaceAll('zi ', 'kranti ') ==
                normalized.replaceAll('zi ', 'kranti ') ||
            modName.replaceAll('kranti ', 'zi ') ==
                normalized.replaceAll('kranti ', 'zi ')) {
          return module.id;
        }
      }
    } catch (_) {
      // No catalog available — same as no moduleId at all, which already
      // falls back to showing the unscoped list rather than an empty one.
    }
    return null;
  }

  /// Fills the pickup from the rider's location, or leaves it empty.
  ///
  /// When there was no location this used to fill in "17/C, New Palasia,
  /// Indore" - or the words "Fetching location..." placed at Indore's
  /// coordinates - and a rider anywhere else could book from there, getting
  /// Indore's prices and Indore's drivers. An empty pickup the rider has to
  /// fill in is the honest answer.
  Future<void> _prefillCurrentLocation({bool overwrite = false}) async {
    final position = await ref.read(currentPositionProvider.future);
    if (!mounted) return;

    if (position == null) {
      setState(() => _locationUnavailable = true);
      return;
    }

    final address = await ref.read(currentAddressProvider.future);
    if (!mounted) return;
    // The rider may have typed or picked a pickup while this was resolving.
    if (_pickup != null && !overwrite) {
      setState(() => _locationUnavailable = false);
      return;
    }

    final label = address.isNotEmpty ? address : 'Current location';
    setState(() {
      _locationUnavailable = false;
      _pickup = BookingLocation(
        lat: position.latitude,
        lng: position.longitude,
        address: label,
      );
      _pickupController.text = label;
      _currentAccuracy = position.accuracy;
    });

    if (_isNearestMode) {
      setState(() {
        _nearestAirports = _fallbackNearest(
          position.latitude,
          position.longitude,
        ).take(3).toList();
      });
      _fetchNearestAirports(position.latitude, position.longitude);
    }
  }

  /// "Use current location": turns location on if it is off, then sets the
  /// pickup from it - replacing whatever pickup was there, because the rider
  /// asked for exactly that.
  Future<void> _useCurrentLocation() async {
    final ok = await requestLocationAccess(context, ref);
    if (!mounted) return;
    if (!ok) {
      setState(() => _locationUnavailable = true);
      SnackbarUtils.info(
        context,
        'Location is still off. You can type the pickup or select it on the map.',
      );
      return;
    }
    await _prefillCurrentLocation(overwrite: true);
    if (mounted) _tryProceedToRideTypes();
  }

  /// "Select on map", for whichever field the rider is editing.
  ///
  /// The map picker existed, but this screen - where pickup and drop are
  /// actually entered - never opened it. A rider whose location was off, or
  /// whose address does not show up in search, had no way to point at a spot.
  Future<void> _selectOnMap() async {
    final target = _activeTarget;
    final type = target.type == FieldTargetType.pickup ? 'pickup' : 'drop';
    final result = await context.push<Map<String, dynamic>>(
      '/home/map-picker?type=$type',
    );
    if (!mounted || result == null) return;

    final address = (result['address'] ?? '').toString();
    final lat = (result['lat'] as num?)?.toDouble() ?? 0;
    final lng = (result['lng'] as num?)?.toDouble() ?? 0;
    if (address.isEmpty || (lat == 0 && lng == 0)) return;

    final location = BookingLocation(lat: lat, lng: lng, address: address);
    setState(() {
      if (target.type == FieldTargetType.pickup) {
        _pickup = location;
        _pickupController.text = address;
        _locationUnavailable = false;
        if (_drop == null) _activeTarget = const FieldTarget.drop();
      } else if (target.type == FieldTargetType.stop &&
          target.stopIndex != null &&
          target.stopIndex! < _stops.length) {
        _stops[target.stopIndex!] = location;
        _stopControllers[target.stopIndex!].text = address;
      } else {
        _drop = location;
        _dropController.text = address;
      }
      _results = [];
    });

    _tryProceedToRideTypes();
  }

  Widget _buildLocationActions({
    required Color tealColor,
    required Color cardBgColor,
    required Color borderColor,
    required Color textSecondary,
  }) {
    Widget action({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: Material(
          color: cardBgColor,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: tealColor),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_locationUnavailable)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              decoration: BoxDecoration(
                color: const Color(0xFF2A1F0D),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF5C4410)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_off_rounded,
                    size: 18,
                    color: Color(0xFFFFB020),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Location is off. Turn it on to set your pickup automatically.',
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: 12.5,
                        height: 1.3,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _useCurrentLocation,
                    child: Text(
                      'Turn on',
                      style: TextStyle(
                        color: tealColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              action(
                icon: Icons.my_location_rounded,
                label: 'Use current location',
                onTap: _useCurrentLocation,
              ),
              const SizedBox(width: 10),
              action(
                icon: Icons.map_outlined,
                label: _activeTarget.type == FieldTargetType.pickup
                    ? 'Select pickup on map'
                    : 'Select on map',
                onTap: _selectOnMap,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _fetchNearestAirports(double lat, double lng) async {
    setState(() => _loadingAirports = true);
    try {
      final dio = Dio();
      final response = await dio.get(
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json',
        queryParameters: {
          'location': '$lat,$lng',
          'radius': '150000',
          'type': _isRailwayMode ? 'train_station' : 'airport',
          'key': AppConstants.mapKey,
        },
      );

      List<_GeoResult> fetched = [];
      if (response.data != null && response.data['results'] != null) {
        final results = response.data['results'] as List;
        for (final item in results) {
          final name = (item['name'] ?? '') as String;
          final vicinity =
              (item['vicinity'] ?? item['formatted_address'] ?? name) as String;
          final loc = item['geometry']?['location'];
          final aLat = (loc?['lat'] ?? 0.0) is num
              ? (loc!['lat'] as num).toDouble()
              : 0.0;
          final aLng = (loc?['lng'] ?? 0.0) is num
              ? (loc!['lng'] as num).toDouble()
              : 0.0;
          final placeId = (item['place_id'] ?? '') as String;

          if (name.isNotEmpty && aLat != 0 && aLng != 0) {
            fetched.add(
              _GeoResult(
                title: name,
                address: vicinity,
                lat: aLat,
                lng: aLng,
                placeId: placeId,
              ),
            );
          }
          if (fetched.length >= 3) break;
        }
      }

      if (fetched.length < 3) {
        final textResp = await dio.get(
          'https://maps.googleapis.com/maps/api/place/textsearch/json',
          queryParameters: {
            'query': _isRailwayMode ? 'railway station' : 'airport',
            'location': '$lat,$lng',
            'radius': '150000',
            'key': AppConstants.mapKey,
          },
        );
        if (textResp.data != null && textResp.data['results'] != null) {
          final results = textResp.data['results'] as List;
          for (final item in results) {
            final name = (item['name'] ?? '') as String;
            final address =
                (item['formatted_address'] ?? item['vicinity'] ?? name)
                    as String;
            final loc = item['geometry']?['location'];
            final aLat = (loc?['lat'] ?? 0.0) is num
                ? (loc!['lat'] as num).toDouble()
                : 0.0;
            final aLng = (loc?['lng'] ?? 0.0) is num
                ? (loc!['lng'] as num).toDouble()
                : 0.0;
            final placeId = (item['place_id'] ?? '') as String;

            if (name.isNotEmpty && aLat != 0 && aLng != 0) {
              if (!fetched.any(
                (f) =>
                    f.title == name ||
                    (placeId.isNotEmpty && f.placeId == placeId),
              )) {
                fetched.add(
                  _GeoResult(
                    title: name,
                    address: address,
                    lat: aLat,
                    lng: aLng,
                    placeId: placeId,
                  ),
                );
              }
            }
            if (fetched.length >= 3) break;
          }
        }
      }

      if (fetched.length < 3) {
        final fallbacks = _fallbackNearest(lat, lng);
        for (final fb in fallbacks) {
          if (!fetched.any((f) => f.title == fb.title)) {
            fetched.add(fb);
          }
          if (fetched.length >= 3) break;
        }
      }

      if (mounted) {
        setState(() {
          _nearestAirports = fetched.take(3).toList();
          _loadingAirports = false;
        });
      }
    } catch (e) {
      debugPrint('Fetch nearest airports error: $e');
      if (mounted) {
        setState(() {
          _nearestAirports = _fallbackNearest(lat, lng).take(3).toList();
          _loadingAirports = false;
        });
      }
    }
  }

  List<_GeoResult> _getFallbackAirportsForLocation(double lat, double lng) {
    if (lat >= 21.0 && lat <= 24.0 && lng >= 74.0 && lng <= 77.0) {
      return const [
        _GeoResult(
          title: 'Devi Ahilya Bai Holkar International Airport (IDR)',
          address: 'Depalpur Road, Indore, Madhya Pradesh',
          lat: 22.7219,
          lng: 75.8011,
        ),
        _GeoResult(
          title: 'Raja Bhoj Airport (BHO)',
          address: 'Gandhi Nagar, Bhopal, Madhya Pradesh',
          lat: 23.2875,
          lng: 77.3374,
        ),
        _GeoResult(
          title: 'Dumna Airport (JLR)',
          address: 'Airport Road, Jabalpur, Madhya Pradesh',
          lat: 23.1778,
          lng: 80.0522,
        ),
      ];
    }
    return const [
      _GeoResult(
        title: 'Devi Ahilya Bai Holkar International Airport (IDR)',
        address: 'Depalpur Road, Indore, Madhya Pradesh',
        lat: 22.7219,
        lng: 75.8011,
      ),
      _GeoResult(
        title: 'Kempegowda International Airport (BLR)',
        address: 'KIAL Road, Devanahalli, Bengaluru',
        lat: 13.1986,
        lng: 77.7066,
      ),
      _GeoResult(
        title: 'Chhatrapati Shivaji Maharaj International Airport (BOM)',
        address: 'Mumbai, Maharashtra',
        lat: 19.0896,
        lng: 72.8656,
      ),
    ];
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(query));
  }

  Future<void> _search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _searchGeneration++;
      setState(() {
        _results = [];
        _searching = false;
      });
      return;
    }
    // Captured once, checked before every setState below that would apply a
    // response — a slower, older request's response arriving after a newer
    // one's must never overwrite what the rider is currently looking at.
    final requestId = ++_searchGeneration;
    setState(() => _searching = true);
    _ensureSessionToken();

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ),
    );

    // Bias (not restrict) every provider below toward the rider's current
    // location when it's known — a soft preference that lets Google/
    // Nominatim/Photon's own relevance ranking still surface a genuinely
    // distant exact match (an airport, another city), rather than a hard
    // radius that would hide it. See location_aware_ranking_service.dart
    // for the client-side re-ranking layered on top of this.
    final biasLat = _pickup?.lat;
    final biasLng = _pickup?.lng;

    // 1. Try Google Places Autocomplete API
    try {
      final response = await dio.get(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json',
        queryParameters: {
          'input': trimmed,
          'key': AppConstants.mapKey,
          'sessiontoken': _sessionToken,
          'components': 'country:in',
          // location+radius alone is a bias in the Autocomplete API — it
          // only becomes a hard restriction with strictbounds=true, which
          // is deliberately not set here.
          if (biasLat != null && biasLng != null)
            'location': '$biasLat,$biasLng',
          if (biasLat != null && biasLng != null) 'radius': '50000',
        },
      );

      if (response.data != null && response.data['status'] == 'OK') {
        final predictions = response.data['predictions'] as List;
        final geoResults = predictions.map((item) {
          final description = (item['description'] ?? '') as String;
          final mainText =
              (item['structured_formatting']?['main_text'] ??
                      description.split(',').first)
                  as String;
          final placeId = (item['place_id'] ?? '') as String;
          return _GeoResult(
            title: mainText,
            address: description,
            placeId: placeId,
            lat: 0,
            lng: 0,
          );
        }).toList();

        if (mounted &&
            requestId == _searchGeneration &&
            geoResults.isNotEmpty) {
          setState(() {
            _results = _rankAndAnnotate(geoResults, trimmed);
            _searching = false;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('Google Places Autocomplete REST error: $e');
    }

    // 2. Fallback: OpenStreetMap Nominatim API (Free, fast & global)
    try {
      final response = await dio.get(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {
          'q': trimmed,
          'format': 'json',
          'addressdetails': '1',
          'limit': '10',
          'countrycodes': 'in',
          // A viewbox without bounded=1 is Nominatim's bias equivalent —
          // preferred, not restricted, toward this box around the rider.
          if (biasLat != null && biasLng != null)
            'viewbox':
                '${biasLng - 0.5},${biasLat + 0.5},${biasLng + 0.5},${biasLat - 0.5}',
        },
        options: Options(
          headers: {'User-Agent': 'KrantiCabsUserApp/1.0 (flutter_taxi_user)'},
        ),
      );

      if (response.data != null &&
          response.data is List &&
          (response.data as List).isNotEmpty) {
        final items = response.data as List;
        final geoResults = <_GeoResult>[];
        for (final item in items) {
          final name = (item['name'] ?? '').toString();
          final displayName = (item['display_name'] ?? '').toString();
          final lat = double.tryParse(item['lat']?.toString() ?? '') ?? 0.0;
          final lon = double.tryParse(item['lon']?.toString() ?? '') ?? 0.0;

          final title = name.isNotEmpty
              ? name
              : (displayName.isNotEmpty
                    ? displayName.split(',').first
                    : trimmed);

          if (displayName.isNotEmpty && (lat != 0.0 || lon != 0.0)) {
            geoResults.add(
              _GeoResult(
                title: title,
                address: displayName,
                lat: lat,
                lng: lon,
              ),
            );
          }
        }

        if (mounted &&
            requestId == _searchGeneration &&
            geoResults.isNotEmpty) {
          setState(() {
            _results = _rankAndAnnotate(geoResults, trimmed);
            _searching = false;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('Nominatim search error: $e');
    }

    // 3. Fallback: Photon Komoot API (Free OpenStreetMap search)
    try {
      final response = await dio.get(
        'https://photon.komoot.io/api/',
        queryParameters: {
          'q': trimmed,
          'limit': '10',
          // Photon's own location-bias params — soft preference, same as
          // the other two providers above.
          if (biasLat != null && biasLng != null) 'lat': '$biasLat',
          if (biasLat != null && biasLng != null) 'lon': '$biasLng',
        },
      );

      if (response.data != null && response.data['features'] != null) {
        final features = response.data['features'] as List;
        final geoResults = <_GeoResult>[];
        for (final item in features) {
          final props = item['properties'] ?? {};
          final coords = item['geometry']?['coordinates'] as List?;
          final name = (props['name'] ?? props['street'] ?? trimmed).toString();
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
            geoResults.add(
              _GeoResult(
                title: name.isNotEmpty ? name : trimmed,
                address: addressParts.isNotEmpty ? addressParts : name,
                lat: lat,
                lng: lon,
              ),
            );
          }
        }

        if (mounted &&
            requestId == _searchGeneration &&
            geoResults.isNotEmpty) {
          setState(() {
            _results = _rankAndAnnotate(geoResults, trimmed);
            _searching = false;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('Photon search error: $e');
    }

    // 4. Native Geocoding Fallback
    try {
      final locations = await locationFromAddress(trimmed);
      if (mounted && requestId == _searchGeneration && locations.isNotEmpty) {
        final geoResults = locations
            .take(6)
            .map(
              (l) => _GeoResult(
                title: trimmed.split(',').first,
                address: trimmed,
                lat: l.latitude,
                lng: l.longitude,
              ),
            )
            .toList();
        setState(() {
          _results = _rankAndAnnotate(geoResults, trimmed);
          _searching = false;
        });
        return;
      }
    } catch (e) {
      debugPrint('Native geocoding error: $e');
    }

    if (mounted && requestId == _searchGeneration) {
      setState(() {
        _results = [];
        _searching = false;
      });
      SnackbarUtils.info(context, 'No matching places found');
    }
  }

  /// Re-orders raw provider results to prefer text-relevant, nearby,
  /// same-locality/city candidates over an equally-relevant but distant one
  /// — see location_aware_ranking_service.dart for the actual scoring.
  /// Distance is computed here (cheap, local, no extra API call) and
  /// attached to each result so the list can optionally show "X km".
  List<_GeoResult> _rankAndAnnotate(List<_GeoResult> raw, String query) {
    final currentLat = _pickup?.lat;
    final currentLng = _pickup?.lng;

    final candidates = <SearchRankCandidate>[];
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      // (0, 0) is these providers' "coordinates not returned" placeholder
      // (see _GeoResult's doc comment), not a real location on the equator
      // — treated as unknown so it can't be scored as implausibly far away.
      final hasCoords = item.lat != 0.0 || item.lng != 0.0;
      candidates.add(
        SearchRankCandidate(
          providerRank: i,
          title: item.title,
          address: item.address,
          lat: hasCoords ? item.lat : null,
          lng: hasCoords ? item.lng : null,
        ),
      );
    }

    final order = rankSearchResults(
      query: query,
      candidates: candidates,
      currentLat: currentLat,
      currentLng: currentLng,
      currentAccuracyMeters: _currentAccuracy,
      currentLocality: ref.read(locationServiceProvider).lastKnownLocality,
      currentCity: ref.read(locationServiceProvider).lastKnownCity,
    );

    return order.map((i) {
      final item = raw[i];
      final candidate = candidates[i];
      final distance =
          (currentLat != null &&
              currentLng != null &&
              candidate.lat != null &&
              candidate.lng != null)
          ? distanceMetersBetween(
              currentLat,
              currentLng,
              candidate.lat!,
              candidate.lng!,
            )
          : null;
      return item.withDistance(distance);
    }).toList();
  }

  Future<void> _selectResult(_GeoResult result) async {
    double lat = result.lat;
    double lng = result.lng;

    if (result.placeId != null && result.placeId!.isNotEmpty) {
      try {
        final dio = Dio();
        final response = await dio.get(
          'https://maps.googleapis.com/maps/api/place/details/json',
          queryParameters: {
            'place_id': result.placeId,
            'key': AppConstants.mapKey,
            'sessiontoken': _sessionToken,
            'fields': 'formatted_address,geometry',
          },
        );

        if (response.data != null && response.data['status'] == 'OK') {
          final loc = response.data['result']['geometry']['location'];
          lat = (loc['lat'] as num).toDouble();
          lng = (loc['lng'] as num).toDouble();
        }
      } catch (e) {
        debugPrint('Place Details fetch error: $e');
      } finally {
        _sessionToken = '';
      }
    }

    // Fallback: If lat/lng are still 0, resolve via Nominatim search
    if (lat == 0 && lng == 0) {
      try {
        final dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 4),
            receiveTimeout: const Duration(seconds: 4),
          ),
        );
        final response = await dio.get(
          'https://nominatim.openstreetmap.org/search',
          queryParameters: {
            'q': result.address.isNotEmpty ? result.address : result.title,
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
      } catch (e) {
        debugPrint('Fallback geocoding for selectResult failed: $e');
      }
    }

    if (lat == 0 && lng == 0) {
      try {
        final locations = await locationFromAddress(result.address);
        if (locations.isNotEmpty) {
          lat = locations.first.latitude;
          lng = locations.first.longitude;
        }
      } catch (_) {}
    }

    if (lat == 0 && lng == 0) {
      if (mounted) {
        SnackbarUtils.info(
          context,
          'Could not locate that place. Please pick another.',
        );
      }
      return;
    }

    final location = BookingLocation(
      lat: lat,
      lng: lng,
      address: result.address,
    );
    ref
        .read(recentSearchesProvider.notifier)
        .add(address: result.address, lat: lat, lng: lng);

    setState(() {
      if (_activeTarget.type == FieldTargetType.pickup) {
        _pickup = location;
        _pickupController.text = result.address;
        if (_drop == null) {
          _activeTarget = const FieldTarget.drop();
        }
      } else if (_activeTarget.type == FieldTargetType.drop) {
        _drop = location;
        _dropController.text = result.address;
      } else if (_activeTarget.type == FieldTargetType.stop &&
          _activeTarget.stopIndex != null &&
          _activeTarget.stopIndex! < _stops.length) {
        final idx = _activeTarget.stopIndex!;
        _stops[idx] = location;
        _stopControllers[idx].text = result.address;
      }
      _results = [];
    });

    _pickupFocus.unfocus();
    _dropFocus.unfocus();
    if (mounted) {
      FocusScope.of(context).unfocus();
    }

    _tryProceedToRideTypes();
  }

  /// Opens the map picker for [type] ('pickup' or 'drop') and applies what the
  /// rider confirms, exactly as if they had chosen a search result.
  Future<void> _pickOnMap(String type) async {
    final result = await context.push<Object?>('/home/map-picker?type=$type');
    if (result is! Map || !mounted) return;

    final lat = (result['lat'] as num?)?.toDouble();
    final lng = (result['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;

    final address = (result['address'] as String?)?.trim() ?? '';
    final location = BookingLocation(
      lat: lat,
      lng: lng,
      address: address.isNotEmpty
          ? address
          : '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
    );

    setState(() {
      if (type == 'pickup') {
        _pickup = location;
        _pickupController.text = location.address;
        if (_drop == null) _activeTarget = const FieldTarget.drop();
      } else {
        _drop = location;
        _dropController.text = location.address;
      }
      _results = [];
    });

    _tryProceedToRideTypes();
  }

  void _tryProceedToRideTypes({bool isExplicitContinue = false}) {
    if (_pickup == null || _drop == null) {
      if (isExplicitContinue) {
        if (_pickup == null) {
          SnackbarUtils.info(context, 'Please enter pickup location');
        } else {
          SnackbarUtils.info(context, 'Please enter drop location');
        }
      }
      return;
    }

    final validStops = _stops.whereType<BookingLocation>().toList();
    ref.read(bookingControllerProvider.notifier)
      ..setPickup(_pickup!)
      ..setStops(validStops)
      ..setDrop(_drop!)
      ..goToStep(BookingStep.selectingVehicle);

    if (mounted) {
      context.push('/home/ride-types');
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _pickupController.removeListener(_onTextChanged);
    _dropController.removeListener(_onTextChanged);
    _pickupFocus.removeListener(_onFocusChanged);
    _dropFocus.removeListener(_onFocusChanged);
    _pickupController.dispose();
    _dropController.dispose();
    _pickupFocus.dispose();
    _dropFocus.dispose();
    for (final c in _stopControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const bgColor = Color(0xFF11191D);
    const cardBgColor = Color(0xFF222222);
    const borderColor = Color(0xFF2E2E2E);
    const tealColor = Color(0xFFF5B400);
    const textSecondary = Color(0xFF94A3B8);

    final recentSearches = ref.watch(recentSearchesProvider);
    final displayPlaces = recentSearches
        .map(
          (place) => _GeoResult(
            title: place.address.split(',').first,
            address: place.address,
            lat: place.lat,
            lng: place.lng,
          ),
        )
        .toList();

    final bool hasResults = _results.isNotEmpty;
    final bool isSearching = _searching || (_isNearestMode && _loadingAirports);
    final String currentQuery = (_activeTarget.type == FieldTargetType.pickup
            ? _pickupController.text
            : _dropController.text)
        .trim();
    final bool isTyping = (_pickupFocus.hasFocus && _pickupController.text.trim().isNotEmpty) ||
        (_dropFocus.hasFocus && _dropController.text.trim().isNotEmpty);
    final bool isSearchMode = hasResults || isSearching || isTyping;

    return Scaffold(
      backgroundColor: bgColor,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            // --- TOP HEADER BAR WITH BACK ARROW & TITLE ---
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: () => context.pop(),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    widget.title?.isNotEmpty == true
                        ? widget.title!
                        : 'Kranti City Ride',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: CustomScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  // --- ROUTE INPUT CARD (Pickup & Drop Box) ---
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: cardBgColor,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: borderColor),
                            ),
                            child: Column(
                              children: [
                                // Pickup Row
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Container(
                                        width: 10,
                                        height: 10,
                                        decoration: const BoxDecoration(
                                          color: tealColor,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Pickup Location',
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF94A3B8),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          TextField(
                                            controller: _pickupController,
                                            focusNode: _pickupFocus,
                                            cursorColor: tealColor,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                            decoration: const InputDecoration(
                                              isDense: true,
                                              filled: false,
                                              fillColor: Colors.transparent,
                                              contentPadding: EdgeInsets.zero,
                                              border: InputBorder.none,
                                              enabledBorder: InputBorder.none,
                                              focusedBorder: InputBorder.none,
                                              hintText: 'Enter pickup location',
                                              hintStyle: TextStyle(
                                                color: textSecondary,
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w400,
                                              ),
                                            ),
                                            onTap: () => setState(
                                              () => _activeTarget =
                                                  const FieldTarget.pickup(),
                                            ),
                                            onChanged: (v) {
                                              setState(
                                                () => _activeTarget =
                                                    const FieldTarget.pickup(),
                                              );
                                              _onQueryChanged(v);
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_pickupController.text.isNotEmpty)
                                      GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            _pickupController.clear();
                                            _pickup = null;
                                            _results = [];
                                          });
                                        },
                                        child: const Padding(
                                          padding: EdgeInsets.all(4.0),
                                          child: Icon(
                                            Icons.cancel_rounded,
                                            color: textSecondary,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),

                                // Vertical Dotted Connector & Divider Line
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 4,
                                    top: 4,
                                    bottom: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 2,
                                        height: 18,
                                        color: const Color(0xFF334155),
                                      ),
                                      const SizedBox(width: 20),
                                      const Expanded(
                                        child: Divider(height: 1, color: Color(0xFF2A2A2A)),
                                      ),
                                    ],
                                  ),
                                ),

                                // Drop Row
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Container(
                                        width: 10,
                                        height: 10,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFEF4444),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Drop Location',
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF94A3B8),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          TextField(
                                            controller: _dropController,
                                            focusNode: _dropFocus,
                                            autofocus: false,
                                            cursorColor: tealColor,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                            decoration: const InputDecoration(
                                              isDense: true,
                                              filled: false,
                                              fillColor: Colors.transparent,
                                              contentPadding: EdgeInsets.zero,
                                              border: InputBorder.none,
                                              enabledBorder: InputBorder.none,
                                              focusedBorder: InputBorder.none,
                                              hintText: 'Enter drop location',
                                              hintStyle: TextStyle(
                                                color: textSecondary,
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w400,
                                              ),
                                            ),
                                            onTap: () => setState(
                                              () =>
                                                  _activeTarget = const FieldTarget.drop(),
                                            ),
                                            onChanged: (v) {
                                              setState(
                                                () => _activeTarget =
                                                    const FieldTarget.drop(),
                                              );
                                              _onQueryChanged(v);
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_dropController.text.isNotEmpty)
                                      GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            _dropController.clear();
                                            _drop = null;
                                            _results = [];
                                          });
                                        },
                                        child: const Padding(
                                          padding: EdgeInsets.all(4.0),
                                          child: Icon(
                                            Icons.cancel_rounded,
                                            color: Color(0xFFEF4444),
                                            size: 22,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (isSearching)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                            child: LinearProgressIndicator(
                              minHeight: 2.5,
                              color: tealColor,
                              backgroundColor: cardBgColor,
                            ),
                          ),
                      ],
                    ),
                  ),

                  // --- CONDITIONAL VIEW: SEARCH MODE VS READY/OVERVIEW MODE ---
                  if (isSearchMode) ...[
                    // Suggestions directly under input card
                    if (hasResults) ...[
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        sliver: SliverList.separated(
                          itemCount: _results.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1, color: borderColor),
                          itemBuilder: (context, index) {
                            final item = _results[index];
                            return _RecentPlaceTile(
                              item: item,
                              onTap: () => _selectResult(item),
                            );
                          },
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _pickOnMap(_activeTarget.type == FieldTargetType.pickup ? 'pickup' : 'drop'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: cardBgColor,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: borderColor),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(
                                      color: tealColor.withValues(alpha: 0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.map_outlined, color: tealColor, size: 18),
                                  ),
                                  const SizedBox(width: 12),
                                  const Text(
                                    'Choose location on map',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const Spacer(),
                                  const Icon(Icons.chevron_right_rounded, color: textSecondary, size: 20),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ] else if (!isSearching && currentQuery.length >= 2) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                          child: Column(
                            children: [
                              const Icon(Icons.location_off_outlined, size: 40, color: Color(0xFF64748B)),
                              const SizedBox(height: 10),
                              const Text(
                                'No locations found',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Try searching with a different name or pick on map',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: textSecondary, fontSize: 13),
                              ),
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                onPressed: () => _pickOnMap(_activeTarget.type == FieldTargetType.pickup ? 'pickup' : 'drop'),
                                icon: const Icon(Icons.map_outlined, size: 18),
                                label: const Text('Choose location on map'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      // Field focused with short or empty query: show Recent Places immediately
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Recent Places',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              InkWell(
                                onTap: () => _pickOnMap(_activeTarget.type == FieldTargetType.pickup ? 'pickup' : 'drop'),
                                child: const Text(
                                  'Choose on map >',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: tealColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        sliver: SliverList.separated(
                          itemCount: displayPlaces.isNotEmpty ? displayPlaces.length : 3,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1, color: borderColor),
                          itemBuilder: (context, index) {
                            if (displayPlaces.isNotEmpty) {
                              final item = displayPlaces[index];
                              return _RecentPlaceTile(
                                item: item,
                                onTap: () => _selectResult(item),
                              );
                            }
                            final defaultMocks = [
                              const _GeoResult(title: 'Home', address: 'MG Road, Bengaluru', lat: 12.9716, lng: 77.5946),
                              const _GeoResult(title: 'Work', address: 'Whitefield, Bengaluru', lat: 12.9698, lng: 77.7500),
                              const _GeoResult(title: 'Kempegowda International Airport', address: 'KIAL, Bengaluru', lat: 13.1986, lng: 77.7066),
                            ];
                            final item = defaultMocks[index];
                            return _RecentPlaceTile(
                              item: item,
                              onTap: () => _selectResult(item),
                            );
                          },
                        ),
                      ),
                    ],
                  ] else ...[
                    // --- OVERVIEW / READY MODE (Not actively searching) ---
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // --- SELECT ON MAP buttons ---
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _pickOnMap('pickup'),
                                    icon: const Icon(Icons.pin_drop_outlined, size: 18),
                                    label: const Text('Pickup on map'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _pickOnMap('drop'),
                                    icon: const Icon(Icons.map_outlined, size: 18),
                                    label: const Text('Drop on map'),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 10),

                          // --- TRIP TYPE SELECTOR (One Way vs Round Trip) ---
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            child: Row(
                              children: [
                                const Text(
                                  'Trip Type',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                const Spacer(),
                                Row(
                                  children: [
                                    GestureDetector(
                                      onTap: () => _selectTripType(TripType.oneWay),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _tripType == TripType.oneWay
                                              ? const Color(0xFF044B47)
                                              : cardBgColor,
                                          borderRadius: BorderRadius.circular(22),
                                          border: Border.all(
                                            color: _tripType == TripType.oneWay
                                                ? tealColor
                                                : borderColor,
                                            width: 1.5,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              _tripType == TripType.oneWay
                                                  ? Icons.radio_button_checked_rounded
                                                  : Icons.radio_button_off_rounded,
                                              size: 16,
                                              color: _tripType == TripType.oneWay
                                                  ? tealColor
                                                  : textSecondary,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'One Way',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: _tripType == TripType.oneWay
                                                    ? tealColor
                                                    : Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    GestureDetector(
                                      onTap: () => _selectTripType(TripType.roundTrip),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _tripType == TripType.roundTrip
                                              ? const Color(0xFF044B47)
                                              : cardBgColor,
                                          borderRadius: BorderRadius.circular(22),
                                          border: Border.all(
                                            color: _tripType == TripType.roundTrip
                                                ? tealColor
                                                : borderColor,
                                            width: 1.5,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              _tripType == TripType.roundTrip
                                                  ? Icons.radio_button_checked_rounded
                                                  : Icons.radio_button_off_rounded,
                                              size: 16,
                                              color: _tripType == TripType.roundTrip
                                                  ? tealColor
                                                  : textSecondary,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Round Trip',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: _tripType == TripType.roundTrip
                                                    ? tealColor
                                                    : Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // When the trip leaves: now, or a time - which books it
                          // as a scheduled ride.
                          if (widget.isOutstation) ...[
                            const SizedBox(height: 10),
                            _dateTimeRow(
                              icon: Icons.schedule_rounded,
                              label: 'Leave on',
                              value: _leaveAt == null ? 'Now' : _formatReturnDateTime(_leaveAt!),
                              highlighted: _leaveAt != null,
                              onTap: _pickLeaveDateTime,
                              onClear: _leaveAt == null ? null : _leaveNow,
                              cardBgColor: cardBgColor,
                              borderColor: borderColor,
                              accent: tealColor,
                              textSecondary: textSecondary,
                            ),
                          ],

                          // Return date/time — only for a round-trip outstation ride
                          if (_tripType == TripType.roundTrip && widget.isOutstation) ...[
                            const SizedBox(height: 10),
                            _dateTimeRow(
                              icon: Icons.event_repeat_rounded,
                              label: 'Return date & time',
                              value: _returnAt == null
                                  ? 'Select return date & time'
                                  : _formatReturnDateTime(_returnAt!),
                              highlighted: _returnAt != null,
                              onTap: _pickReturnDateTime,
                              cardBgColor: cardBgColor,
                              borderColor: borderColor,
                              accent: tealColor,
                              textSecondary: textSecondary,
                            ),
                          ],

                          const SizedBox(height: 10),

                          _buildLocationActions(
                            tealColor: tealColor,
                            cardBgColor: cardBgColor,
                            borderColor: borderColor,
                            textSecondary: textSecondary,
                          ),

                          const SizedBox(height: 10),

                          // --- FIND RIDES FULL WIDTH BUTTON ---
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: tealColor,
                                  foregroundColor: const Color(0xFF0A0A0A),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                onPressed: () =>
                                    _tryProceedToRideTypes(isExplicitContinue: true),
                                child: const Text(
                                  'Find Rides',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0A0A0A),
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // --- RECENT PLACES / NEAREST AIRPORTS HEADER ---
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    if (_isNearestMode)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 6),
                                        child: Icon(
                                          _isRailwayMode
                                              ? Icons.train_rounded
                                              : Icons.flight_takeoff_rounded,
                                          color: tealColor,
                                          size: 20,
                                        ),
                                      ),
                                    Text(
                                      _isRailwayMode
                                          ? '3 Nearest Railway Stations'
                                          : _isAirportMode
                                              ? '3 Nearest Airports'
                                              : 'Recent Places',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                                if (!_isNearestMode)
                                  InkWell(
                                    onTap: () => context.push('/home/saved-places'),
                                    child: const Text(
                                      'View all >',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: tealColor,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (_isNearestMode)
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        sliver: SliverList.builder(
                          itemCount: _nearestAirports.length,
                          itemBuilder: (context, index) {
                            final airport = _nearestAirports[index];
                            return _AirportTile(
                              airport: airport,
                              icon: _isRailwayMode
                                  ? Icons.train_rounded
                                  : Icons.flight_takeoff_rounded,
                              onTap: () => _selectResult(airport),
                            );
                          },
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        sliver: SliverList.separated(
                          itemCount: displayPlaces.isNotEmpty
                              ? displayPlaces.length
                              : 3,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1, color: borderColor),
                          itemBuilder: (context, index) {
                            if (displayPlaces.isNotEmpty) {
                              final item = displayPlaces[index];
                              return _RecentPlaceTile(
                                item: item,
                                onTap: () => _selectResult(item),
                              );
                            }
                            // 1:1 Default mock recent places
                            final defaultMocks = [
                              const _GeoResult(
                                title: 'Home',
                                address: 'MG Road, Bengaluru',
                                lat: 12.9716,
                                lng: 77.5946,
                              ),
                              const _GeoResult(
                                title: 'Work',
                                address: 'Whitefield, Bengaluru',
                                lat: 12.9698,
                                lng: 77.7500,
                              ),
                              const _GeoResult(
                                title: 'Kempegowda International Airport',
                                address: 'KIAL, Bengaluru',
                                lat: 13.1986,
                                lng: 77.7066,
                              ),
                            ];
                            final item = defaultMocks[index];
                            return _RecentPlaceTile(
                              item: item,
                              onTap: () => _selectResult(item),
                            );
                          },
                        ),
                      ),
                  ],
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 32),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentPlaceTile extends StatelessWidget {
  final _GeoResult item;
  final VoidCallback onTap;

  const _RecentPlaceTile({required this.item, required this.onTap});

  IconData _getIconFor(String title) {
    final t = title.toLowerCase();
    if (t.contains('home')) return Icons.home_rounded;
    if (t.contains('work')) return Icons.work_rounded;
    if (t.contains('airport') || t.contains('kial')) {
      return Icons.flight_takeoff_rounded;
    }
    return Icons.location_on_rounded;
  }

  Color _getIconColorFor(String title) {
    final t = title.toLowerCase();
    if (t.contains('work')) return const Color(0xFF1E88E5);
    return Colors.white;
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: Center(
                child: Icon(
                  _getIconFor(item.title),
                  color: _getIconColorFor(item.title),
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.star_border_rounded,
                  color: Color(0xFF94A3B8),
                  size: 20,
                ),
                if (item.distanceMeters != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _formatDistance(item.distanceMeters!),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AirportTile extends StatelessWidget {
  final _GeoResult airport;
  final VoidCallback onTap;
  final IconData icon;

  const _AirportTile({
    required this.airport,
    required this.onTap,
    this.icon = Icons.flight_takeoff_rounded,
  });

  @override
  Widget build(BuildContext context) {
    const cardBgColor = Color(0xFF222222);
    const borderColor = Color(0xFF2E2E2E);
    const tealColor = Color(0xFFF5B400);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF044B47),
                  shape: BoxShape.circle,
                  border: Border.all(color: tealColor.withValues(alpha: 0.4)),
                ),
                child: Icon(
                  icon,
                  color: tealColor,
                  size: 21,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      airport.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      airport.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: tealColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Select',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0A0A0A),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
