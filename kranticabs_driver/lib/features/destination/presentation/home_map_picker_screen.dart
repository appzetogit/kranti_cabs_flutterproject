import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';

/// What the driver picked: a point and the address shown for it.
typedef PickedPlace = ({double lat, double lng, String address});

typedef _Suggestion = ({String title, String address, String placeId, double? lat, double? lng});

/// Search an address (with suggestions) or drag the map under a fixed pin to
/// choose home. Pops a [PickedPlace], or null when the driver backs out.
class HomeMapPickerScreen extends StatefulWidget {
  final LatLng? start;
  const HomeMapPickerScreen({super.key, this.start});

  @override
  State<HomeMapPickerScreen> createState() => _HomeMapPickerScreenState();
}

class _HomeMapPickerScreenState extends State<HomeMapPickerScreen> {
  // Centre of India until a real fix arrives, so the map never opens blank.
  static const _fallback = LatLng(22.9734, 78.6569);

  final _dio = Dio();
  final _search = TextEditingController();
  GoogleMapController? _map;
  Timer? _debounce;
  int _requestId = 0;
  LatLng _center = _fallback;
  String _address = '';
  bool _resolving = false;
  List<_Suggestion> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _center = widget.start ?? _fallback;
    if (widget.start == null) _goToMyLocation(initial: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _map?.dispose();
    super.dispose();
  }

  Future<void> _goToMyLocation({bool initial = false}) async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 10));
      _moveTo(LatLng(pos.latitude, pos.longitude), zoom: 16);
    } catch (_) {
      if (!initial && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not get your location.')));
      }
    }
  }

  void _moveTo(LatLng target, {double zoom = 16}) {
    _center = target;
    _map?.animateCamera(CameraUpdate.newLatLngZoom(target, zoom));
  }

  Future<void> _resolveAddress() async {
    final at = _center;
    setState(() => _resolving = true);
    var text = '';
    try {
      final places = await placemarkFromCoordinates(at.latitude, at.longitude);
      if (places.isNotEmpty) {
        final p = places.first;
        text = [p.name, p.subLocality, p.locality, p.postalCode]
            .whereType<String>()
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toSet()
            .join(', ');
      }
    } catch (_) {
      // The point is what matters; a name is a nicety.
    }
    if (mounted && at == _center) {
      setState(() {
        _address = text;
        _resolving = false;
      });
    }
  }

  void _onTyped(String text) {
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
        queryParameters: {'input': input, 'key': AppConstants.mapKey, 'components': 'country:in'},
      );
      final list = res.data?['status'] == 'OK' ? res.data['predictions'] as List : const [];
      found = list.take(6).map<_Suggestion>((e) {
        final desc = '${e['description'] ?? ''}';
        final main = '${e['structured_formatting']?['main_text'] ?? desc.split(',').first}';
        return (title: main, address: desc, placeId: '${e['place_id'] ?? ''}', lat: null, lng: null);
      }).toList();
    } catch (_) {}

    // Google refuses when billing is off on the key; OpenStreetMap is the free fallback.
    if (found.isEmpty) {
      try {
        final res = await _dio.get(
          'https://nominatim.openstreetmap.org/search',
          queryParameters: {'q': input, 'format': 'json', 'limit': '6', 'countrycodes': 'in'},
          options: Options(headers: {'User-Agent': 'KrantiCabsDriverApp/1.0'}),
        );
        found = (res.data as List)
            .map<_Suggestion?>((e) {
              final lat = double.tryParse('${e['lat']}');
              final lng = double.tryParse('${e['lon']}');
              if (lat == null || lng == null) return null;
              final full = '${e['display_name'] ?? ''}';
              final name = '${e['name'] ?? ''}';
              return (title: name.isNotEmpty ? name : full.split(',').first, address: full, placeId: '', lat: lat, lng: lng);
            })
            .whereType<_Suggestion>()
            .toList();
      } catch (_) {}
    }
    if (mounted && id == _requestId) setState(() => _suggestions = found);
  }

  Future<void> _pick(_Suggestion s) async {
    FocusScope.of(context).unfocus();
    _debounce?.cancel();
    _requestId++;
    setState(() {
      _search.text = s.address;
      _suggestions = [];
      _address = s.address;
    });
    double? lat = s.lat, lng = s.lng;
    if (lat == null && s.placeId.isNotEmpty) {
      try {
        final res = await _dio.get(
          'https://maps.googleapis.com/maps/api/place/details/json',
          queryParameters: {'place_id': s.placeId, 'key': AppConstants.mapKey, 'fields': 'geometry'},
        );
        final loc = res.data?['result']?['geometry']?['location'];
        if (loc != null) {
          lat = (loc['lat'] as num).toDouble();
          lng = (loc['lng'] as num).toDouble();
        }
      } catch (_) {}
    }
    if (lat == null || lng == null) {
      try {
        final m = await locationFromAddress(s.address);
        if (m.isNotEmpty) {
          lat = m.first.latitude;
          lng = m.first.longitude;
        }
      } catch (_) {}
    }
    if (lat != null && lng != null) _moveTo(LatLng(lat, lng));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _center, zoom: widget.start == null ? 5 : 16),
            onMapCreated: (c) => _map = c,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onCameraMove: (p) => _center = p.target,
            onCameraIdle: _resolveAddress,
          ),
          // Fixed pin: the map moves under it, the tip marks the chosen point.
          const IgnorePointer(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 36),
                child: Icon(Icons.location_pin, size: 48, color: Color(0xFFEF4444)),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(14),
                    child: TextField(
                      controller: _search,
                      // The app theme is dark with white text; these fields sit
                      // on white, so the colours are set explicitly.
                      style: const TextStyle(color: Color(0xFF0F172A), fontSize: 15),
                      cursorColor: AppColors.primary,
                      onChanged: (t) {
                        setState(() {});
                        _onTyped(t);
                      },
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search area, street or landmark',
                        hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                        prefixIcon: IconButton(
                          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                                onPressed: () => setState(() {
                                  _search.clear();
                                  _suggestions = [];
                                }),
                              ),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  if (_suggestions.isNotEmpty)
                    Flexible(
                      child: Container(
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: _suggestions.length,
                          separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
                          itemBuilder: (_, i) {
                            final s = _suggestions[i];
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.place_outlined, color: Color(0xFF64748B)),
                              title: Text(s.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w700)),
                              subtitle: Text(s.address,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                              onTap: () => _pick(s),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 150,
            child: FloatingActionButton.small(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              onPressed: () => _goToMyLocation(),
              child: const Icon(Icons.my_location_rounded),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + MediaQuery.of(context).padding.bottom),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Home location', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFF64748B))),
                  const SizedBox(height: 4),
                  Text(
                    _resolving ? 'Finding address…' : (_address.isEmpty ? 'Move the map to place the pin' : _address),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: const Color(0xFF11191D),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _resolving
                          ? null
                          : () => Navigator.of(context).pop<PickedPlace>((
                                lat: _center.latitude,
                                lng: _center.longitude,
                                address: _address.isEmpty ? 'Home' : _address,
                              )),
                      child: const Text('Confirm this location', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                    ),
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
