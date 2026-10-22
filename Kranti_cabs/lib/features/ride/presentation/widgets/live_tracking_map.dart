import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/services/route_polyline_service.dart';
import '../../../../core/theme/app_map_style.dart';
import '../../../../core/utils/polyline_decoder.dart';
import '../../../../core/utils/route_geometry.dart';
import '../../data/models/ride_model.dart';

enum _AnimMode { none, route, straight }

/// The live map: pickup/drop/stop pins, the road route, and a driver marker
/// that moves smoothly along that route rather than snapping to each raw GPS
/// fix — the fix only tells us where the driver actually is; the animation is
/// what makes the drive between two fixes look continuous.
///
/// Split out from [RideTrackingScreen] on purpose: the animation drives a
/// `setState` on every frame for ~2 seconds after each fix, and isolating
/// that here means only this widget repaints at that rate, not the whole
/// screen (driver card, address timeline, cancel button, …) underneath it.
class LiveTrackingMap extends StatefulWidget {
  final RideModel ride;
  final BitmapDescriptor driverIcon;

  const LiveTrackingMap({
    super.key,
    required this.ride,
    required this.driverIcon,
  });

  @override
  State<LiveTrackingMap> createState() => _LiveTrackingMapState();
}

class _LiveTrackingMapState extends State<LiveTrackingMap>
    with TickerProviderStateMixin {
  GoogleMapController? _mapController;
  late final AnimationController _animController;

  /// Starting duration before the first real fix has arrived to measure an
  /// actual interval from — after that, [_updateAnimationDuration] takes
  /// over and adapts this per fix instead of leaving it fixed.
  static const _updateInterval = Duration(milliseconds: 1900);

  /// Floor/ceiling for that adaptive window. Real spacing between fixes
  /// varies with how the driver app is currently sending (event-driven while
  /// moving vs. a 30s stationary heartbeat), so a fixed duration either
  /// restarts mid-tween during a burst of close-together fixes or sits idle
  /// waiting after a sparse one. Clamped rather than used raw so a very
  /// short gap (a near-duplicate resend) doesn't produce a flash-cut
  /// animation, and a very long one (after a dropped connection) doesn't
  /// visibly crawl for tens of seconds once it resumes.
  static const _minAnimDuration = Duration(milliseconds: 800);
  static const _maxAnimDuration = Duration(milliseconds: 4000);

  /// How far the raw fix has to sit from the drawn route before it counts as
  /// "off route" at all. Wide enough to absorb ordinary GPS noise and a
  /// multi-lane road; tight enough to catch an actual detour.
  static const _offRouteThresholdMeters = 60.0;

  /// How long that deviation has to persist before it is treated as a real
  /// detour rather than a momentary GPS wobble.
  static const _offRouteTriggerDuration = Duration(seconds: 10);

  // --- road route for the current leg (mirrors the old screen's own state) ---
  List<LatLng> _roadRoute = const [];
  String? _roadRouteKey;

  // --- animation state ---
  _AnimMode _mode = _AnimMode.none;
  List<LatLng> _animRoute = const [];
  double _beginDistance = 0;
  double _endDistance = 0;
  LatLng? _beginPoint;
  LatLng? _endPoint;

  LatLng? _animatedDriverPosition;
  double _animatedRotation = 0;

  /// Rotation is tweened along with the position. Assigning it outright made
  /// the icon flick to a new angle while the car glided, which is the one part
  /// of the movement a passenger actually watches.
  double _rotationBegin = 0;
  double _rotationEnd = 0;

  /// The line currently drawn, resolved when a fix arrives rather than while
  /// building. `build` runs on every animation frame; resolving the route
  /// there meant rebuilding the leg, the cache key and - before the first
  /// fetch returned - a fresh straight-line list sixty times a second.
  List<LatLng> _drawnRoute = const [];

  /// Rebuilt only when their inputs change, so the sixty-per-second rebuild
  /// hands the map the *same* objects and its diff finds nothing to push.
  /// Only the driver marker is allowed to change on a frame.
  Set<Marker> _staticMarkers = const {};
  String _staticMarkersKey = '';
  Polyline? _routePolyline;

  /// Marker and camera updates each cross the platform channel. At sixty
  /// frames a second that is a hundred and twenty messages per second to the
  /// native Maps SDK, which is what made the map stutter rather than glide.
  /// The tween still runs at full rate; only what is pushed is gated.
  static const _mapPushInterval = Duration(milliseconds: 40);
  DateTime? _lastMapPushAt;

  LatLng? _lastProcessedFix;
  DateTime? _lastFixReceivedAt;
  DateTime? _offRouteSince;

  /// Set once the driver has been off the drawn route long enough that a
  /// fresh one was fetched from where they actually are.
  ///
  /// From that moment the server's stored polyline is stale: it was computed
  /// at booking time, from the pickup, before this driver existed and before
  /// they left it. Without this the reroute was fetched and then thrown away
  /// - [_routePointsFor] kept returning the booking route - so the old line
  /// stayed on screen no matter which way the car went.
  bool _routeSupersededByReroute = false;

  /// Which leg was last drawn, so a new one starts from the server's route
  /// again rather than inheriting the previous leg's reroute.
  bool _wasAfterPickup = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: _updateInterval,
    )..addListener(_onTick);
    _maybeHandleNewFix(widget.ride);
  }

  @override
  void didUpdateWidget(covariant LiveTrackingMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeHandleNewFix(widget.ride);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _onTick() {
    final t = _animController.value;
    LatLng? position;

    switch (_mode) {
      case _AnimMode.route:
        if (_animRoute.length < 2) return;
        final distance = _beginDistance + ((_endDistance - _beginDistance) * t);
        position = pointAtDistanceAlongPolyline(_animRoute, distance);
        break;
      case _AnimMode.straight:
        final begin = _beginPoint;
        final end = _endPoint;
        if (begin == null || end == null) return;
        position = LatLng(
          begin.latitude + ((end.latitude - begin.latitude) * t),
          begin.longitude + ((end.longitude - begin.longitude) * t),
        );
        break;
      case _AnimMode.none:
        return;
    }

    // The tween itself runs every frame; pushing it to the native map does
    // not. The last frame always lands, so the marker finishes exactly where
    // the fix says rather than a few centimetres short.
    final now = DateTime.now();
    final last = _lastMapPushAt;
    final isFinalFrame = t >= 1.0;
    if (!isFinalFrame && last != null && now.difference(last) < _mapPushInterval) {
      return;
    }
    _lastMapPushAt = now;

    setState(() {
      _animatedDriverPosition = position;
      _animatedRotation = _lerpBearing(_rotationBegin, _rotationEnd, t);
    });
    _followCamera(position);
  }

  /// Turns the short way round. A plain lerp from 350 to 10 degrees sweeps
  /// backwards through the whole circle, which looks like the car spinning on
  /// the spot at every junction.
  static double _lerpBearing(double from, double to, double t) {
    var delta = (to - from) % 360;
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;
    final result = (from + (delta * t)) % 360;
    return result < 0 ? result + 360 : result;
  }

  /// Keeps the vehicle in view continuously as it moves, the way Uber/Ola/
  /// Rapido do, instead of the camera sitting still and only re-centering
  /// once every new GPS fix (every ~2-4s, with a visible jump each time).
  ///
  /// Called on every animation frame with the same interpolated position the
  /// marker itself is drawn at, so the map pans in exact lockstep with it.
  /// Uses [GoogleMapController.moveCamera] (an instant reposition, no SDK
  /// animation of its own) rather than [GoogleMapController.animateCamera]
  /// on purpose: we're already producing a new target ~60 times a second, so
  /// letting the SDK animate toward each one would just be one animation
  /// interrupting the last, which reads as stutter rather than a smooth pan.
  /// Zoom and bearing are left untouched — only the pan target changes.
  void _followCamera(LatLng position) {
    final last = _lastCameraTarget;
    // Roughly a tenth of a metre. Below that the pan is invisible and the
    // platform call is pure cost.
    if (last != null &&
        (last.latitude - position.latitude).abs() < 0.000001 &&
        (last.longitude - position.longitude).abs() < 0.000001) {
      return;
    }
    _lastCameraTarget = position;
    _mapController?.moveCamera(CameraUpdate.newLatLng(position));
  }

  LatLng? _lastCameraTarget;

  bool _samePoint(LatLng a, LatLng b) =>
      a.latitude == b.latitude && a.longitude == b.longitude;

  bool _sameRoute(List<LatLng> a, List<LatLng> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length || a.isEmpty || b.isEmpty) return false;
    return _samePoint(a.first, b.first) && _samePoint(a.last, b.last);
  }

  /// Reacts to a new `ride.lastDriverLocation` — called from both
  /// `initState` and `didUpdateWidget`, so it de-dupes against fixes it has
  /// already animated toward (the parent rebuilds on every socket message,
  /// not just location ones).
  void _maybeHandleNewFix(RideModel ride) {
    // Pickup to drop is a different journey from driver to pickup: the
    // reroute that superseded one says nothing about the other.
    final afterPickup = ride.isUnderway;
    if (afterPickup != _wasAfterPickup) {
      _wasAfterPickup = afterPickup;
      _routeSupersededByReroute = false;
      _roadRouteKey = null;
      // The pickup leg's road is no longer the journey; drawing it until the
      // new leg's fetch lands would show the wrong line.
      _roadRoute = const [];
    }

    // Resolved here rather than in `build`: this runs once per ride update,
    // `build` runs once per frame. It also has to happen before the de-dupe
    // below, so a leg or status change still redraws the line when the fix
    // itself has not moved.
    final route = _routePointsFor(ride);
    if (!identical(route, _drawnRoute)) {
      _drawnRoute = route;
    }

    final loc = ride.lastDriverLocation;
    if (loc == null) return;
    final fix = LatLng(loc.lat, loc.lng);
    if (_lastProcessedFix != null && _samePoint(_lastProcessedFix!, fix)) {
      return;
    }
    _lastProcessedFix = fix;
    _updateAnimationDuration();
    final projection = route.length >= 2
        ? projectOntoPolyline(fix, route)
        : null;

    if (projection == null) {
      // No usable route yet (still loading, or OSRM is down) — ease straight
      // toward the raw fix rather than leaving the marker snapped and inert.
      _mode = _AnimMode.straight;
      _beginPoint = _animatedDriverPosition ?? fix;
      _endPoint = fix;
      _animController
        ..stop()
        ..reset()
        ..forward();
      // No explicit camera move needed here: starting the animation above
      // fires _onTick on the very next frame, which follows it from there.
      return;
    }

    _trackOffRoute(projection, fix, ride);

    // A bearing read off the drawn route only describes the car while the car
    // is on it. Once the fix has drifted away - a detour, a wrong turn, the
    // ten seconds before a reroute lands - the line points one way and the
    // vehicle drives another, so the reported heading is the truthful one.
    final routeBearing = _bearingAlong(
      route,
      projection.distanceAlongRouteMeters,
    );
    final rotation =
        projection.distanceFromRouteMeters > _offRouteThresholdMeters
        ? (ride.lastDriverHeading ?? routeBearing)
        : (routeBearing ?? ride.lastDriverHeading);
    if (rotation != null) {
      _rotationBegin = _animatedRotation;
      _rotationEnd = rotation;
    }

    final sameRoute = _sameRoute(route, _animRoute);
    final currentAnimated = _animatedDriverPosition;

    if (currentAnimated == null) {
      // First fix ever: there is nothing on screen to animate from, so place
      // the marker once.
      _animRoute = route;
      _mode = _AnimMode.none;
      _animController.stop();
      setState(() {
        _animatedDriverPosition = projection.point;
        // Nothing to tween from on a brand-new line, so this one case snaps.
        _animatedRotation = _rotationEnd;
        _rotationBegin = _rotationEnd;
      });
      _lastCameraTarget = projection.point;
      // No animation will run to drive _onTick's per-frame follow (there's
      // nothing to animate *from* yet), so this one case gets an explicit,
      // one-time smooth fly-to instead.
      _mapController?.animateCamera(CameraUpdate.newLatLng(projection.point));
      return;
    }

    // Re-project the marker's actual current position rather than trusting a
    // remembered "last target" — if this fix arrived before the previous
    // animation finished, that remembered value would be ahead of where the
    // marker visually is, and restarting from it would jump. This also covers
    // a replaced polyline (a reroute, a new leg): the marker carries on from
    // where it is on the new line instead of snapping, and the per-frame
    // follow keeps the camera with it, with no separate fly-to fighting it.
    final beginProjection = projectOntoPolyline(currentAnimated, route);
    if (!sameRoute &&
        (beginProjection == null ||
            beginProjection.distanceFromRouteMeters > _offRouteThresholdMeters)) {
      // The new line does not pass near the marker, so a distance along it
      // says nothing about where the car is drawn. Glide straight to the
      // fix's spot on the new line; the next fix animates along it.
      _animRoute = route;
      _mode = _AnimMode.straight;
      _beginPoint = currentAnimated;
      _endPoint = projection.point;
      _animController
        ..stop()
        ..reset()
        ..forward();
      return;
    }
    _mode = _AnimMode.route;
    _animRoute = route;
    _beginDistance =
        beginProjection?.distanceAlongRouteMeters ??
        projection.distanceAlongRouteMeters;
    _endDistance = projection.distanceAlongRouteMeters;
    _animController
      ..stop()
      ..reset()
      ..forward();
    // Starting the animation above fires _onTick on the next frame, which
    // takes over following the camera from there — no explicit move here.
  }

  /// Sizes the next tween to how long it actually took the last fix to
  /// arrive, clamped to [_minAnimDuration]/[_maxAnimDuration], instead of
  /// always assuming ~1.9s. `AnimationController.duration` is a plain
  /// mutable field — setting it here only changes how long the *next*
  /// `forward()` call below takes, it doesn't touch a run already in
  /// progress.
  void _updateAnimationDuration() {
    final now = DateTime.now();
    final last = _lastFixReceivedAt;
    _lastFixReceivedAt = now;
    if (last == null) return; // first fix ever — nothing to measure yet.

    final elapsed = now.difference(last);
    _animController.duration = elapsed < _minAnimDuration
        ? _minAnimDuration
        : (elapsed > _maxAnimDuration ? _maxAnimDuration : elapsed);
  }

  /// Direction of travel a little ahead of [distance] along the route, so the
  /// marker points the way the road actually goes rather than jittering with
  /// noisy raw-GPS headings.
  double? _bearingAlong(List<LatLng> route, double distance) {
    if (route.length < 2) return null;
    const lookaheadMeters = 8.0;
    final a = pointAtDistanceAlongPolyline(route, distance);
    final b = pointAtDistanceAlongPolyline(route, distance + lookaheadMeters);
    if (_samePoint(a, b)) return null;
    return bearingBetween(a, b);
  }

  /// A fix this inaccurate can't tell us anything reliable about whether the
  /// driver has actually left the route — a poor GPS lock alone can put a
  /// correctly-on-road driver 60m+ from the line.
  static const _unreliableAccuracyMeters = 50.0;

  /// Tracks how long the raw fix has been sitting off the drawn route and,
  /// past the threshold, asks for a fresh one from where the driver actually
  /// is.
  ///
  /// Deliberately not triggered by a single noisy fix — a momentary GPS jump
  /// is common and would otherwise cause a needless reroute. It also only
  /// fires once per sustained deviation: the timer resets the moment it
  /// fires, so a still-off-route driver gets one fresh route, not one every
  /// tick while the request is in flight.
  void _trackOffRoute(RouteProjection projection, LatLng fix, RideModel ride) {
    // Neither starts nor resets the timer — an unreliable fix is simply not
    // evidence either way, so this tick is skipped rather than counted.
    final accuracy = ride.lastDriverAccuracy;
    if (accuracy != null && accuracy > _unreliableAccuracyMeters) return;

    if (projection.distanceFromRouteMeters <= _offRouteThresholdMeters) {
      _offRouteSince = null;
      return;
    }

    final since = _offRouteSince ??= DateTime.now();
    if (DateTime.now().difference(since) < _offRouteTriggerDuration) return;

    _offRouteSince = null;
    final leg = _currentLeg(ride);
    _ensureRoadRoute(
      fix,
      leg.end,
      leg.stops,
      toPickup: leg.toPickup,
      fromDriver: true,
      force: true,
    );
  }

  /// The drawn route. Prefers the server's own polyline once the trip is
  /// underway, then the road route fetched below.
  /// [allowFetch] is false when called from inside a fetch's own callback:
  /// the points are already in hand, and re-entering would start a second
  /// request for a route that has just arrived.
  List<LatLng> _routePointsFor(RideModel ride, {bool allowFetch = true}) {
    // Only once the trip is underway, and only until the driver leaves it.
    // Before pickup the rider is watching the car come to them and the
    // server's stored route describes the journey after that, so showing it
    // early draws the wrong leg; after a reroute it describes a road the
    // driver is no longer on.
    if (ride.isUnderway && !_routeSupersededByReroute) {
      final decoded = PolylineDecoder.decode(ride.routePolyline);
      if (decoded.isNotEmpty) return decoded;
    }

    if (_roadRoute.isNotEmpty && !allowFetch) return _roadRoute;

    final leg = _currentLeg(ride);
    if (allowFetch) {
      _ensureRoadRoute(
        leg.start,
        leg.end,
        leg.stops,
        toPickup: leg.toPickup,
        fromDriver: leg.fromDriver,
      );
    }
    if (_roadRoute.isNotEmpty) return _roadRoute;

    // Only until the first fetch returns.
    return RoutePolylineService.getRoutePointsSync(
      leg.start,
      leg.end,
      leg.stops,
    );
  }

  ({
    LatLng start,
    LatLng end,
    List<LatLng> stops,
    bool toPickup,
    bool fromDriver,
  })
  _currentLeg(RideModel ride) {
    final driverLat = ride.lastDriverLocation?.lat;
    final driverLng = ride.lastDriverLocation?.lng;
    final fromDriver = driverLat != null && driverLng != null;
    final start = (driverLat != null && driverLng != null)
        ? LatLng(driverLat, driverLng)
        : LatLng(ride.pickup.lat, ride.pickup.lng);

    // Before pickup the rider wants to watch the car approach; afterwards the
    // leg that matters is the one to the drop.
    final headingToPickup = !ride.isUnderway;
    final end = headingToPickup
        ? LatLng(ride.pickup.lat, ride.pickup.lng)
        : LatLng(ride.drop.lat, ride.drop.lng);
    final stops = headingToPickup
        ? const <LatLng>[]
        : ride.stops
              .map((s) => LatLng(s.location.lat, s.location.lng))
              .toList();

    return (
      start: start,
      end: end,
      stops: stops,
      toPickup: headingToPickup,
      fromDriver: fromDriver,
    );
  }

  /// Fetches the road route for the current leg from OSRM — never Google's
  /// paid Directions/Geocoding API, which is exactly what this whole
  /// throttle-and-cache scheme exists to avoid hitting on every GPS tick.
  ///
  /// Guarded on a key by default. [force] bypasses that key check — used only
  /// by [_trackOffRoute], once, after ten seconds of sustained deviation.
  ///
  /// On the way to the pickup the key leaves out the driver's position. It
  /// used to round it to three decimals, so the route was re-fetched every
  /// ~110 m of an ordinary drive and the marker jumped onto each new line.
  /// The route fetched from the driver's first fix stays valid while they
  /// follow it; leaving it is what [_trackOffRoute] is for. [fromDriver] is
  /// still part of the key so a line drawn before the first fix (from the
  /// pickup to itself) is replaced once one arrives. The drop leg keeps its
  /// coarse start key.
  void _ensureRoadRoute(
    LatLng start,
    LatLng end,
    List<LatLng> stops, {
    required bool toPickup,
    required bool fromDriver,
    bool force = false,
  }) {
    final origin = toPickup
        ? 'pickup_${fromDriver ? 'driver' : 'none'}'
        : 'drop_${start.latitude.toStringAsFixed(3)},${start.longitude.toStringAsFixed(3)}';
    final key =
        '${origin}_${end.latitude.toStringAsFixed(5)},${end.longitude.toStringAsFixed(5)}'
        '_${stops.length}';
    if (!force && key == _roadRouteKey) return;
    _roadRouteKey = key;

    RoutePolylineService.getRoutePoints(pickup: start, drop: end, stops: stops)
        .then((points) {
          if (!mounted) return;
          // Ignore a slow response for a leg the trip has already moved past.
          if (_roadRouteKey != key) return;
          if (points.isEmpty) {
            // Nothing usable came back. With the pickup key no longer moving
            // with the driver, keeping it would never ask again.
            _roadRouteKey = null;
            return;
          }
          setState(() {
            _roadRoute = points;
            // Only now, with a real replacement in hand, is the booking route
            // dropped - flipping this when the request went out would have
            // shown the synthetic fallback path in the gap.
            if (force) _routeSupersededByReroute = true;
            _drawnRoute = _routePointsFor(widget.ride, allowFetch: false);
          });
        })
        .catchError((_) {
          // Clear the key so the next build retries rather than staying stuck on
          // the synthetic path.
          if (_roadRouteKey == key) _roadRouteKey = null;
        });
  }

  /// The pins that do not move: pickup, drop, every stop.
  ///
  /// Rebuilt only when one of them actually changes. Handing `build` a fresh
  /// set of equal-but-new markers on every frame makes the plugin diff and
  /// re-push all of them; handing back the same objects makes that diff empty.
  Set<Marker> _staticMarkersFor(RideModel ride) {
    final key = '${ride.pickup.lat},${ride.pickup.lng}'
        '_${ride.drop.lat},${ride.drop.lng}'
        '_${ride.stops.map((s) => '${s.location.lat},${s.location.lng}').join('|')}';
    if (key == _staticMarkersKey && _staticMarkers.isNotEmpty) {
      return _staticMarkers;
    }

    _staticMarkersKey = key;
    _staticMarkers = {
      Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(ride.pickup.lat, ride.pickup.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(
          title: 'Pickup Location',
          snippet: ride.pickupAddress,
        ),
      ),
      Marker(
        markerId: const MarkerId('drop'),
        position: LatLng(ride.drop.lat, ride.drop.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: 'Drop Location',
          snippet: ride.dropAddress,
        ),
      ),
      for (int i = 0; i < ride.stops.length; i++)
        Marker(
          markerId: MarkerId('stop_$i'),
          position: LatLng(
            ride.stops[i].location.lat,
            ride.stops[i].location.lng,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: InfoWindow(
            title: 'Stop ${i + 1}',
            snippet: ride.stops[i].address,
          ),
        ),
    };
    return _staticMarkers;
  }

  /// The drawn line, kept as one object for as long as its points are the
  /// same list. A new Polyline every frame carrying the same few hundred
  /// points is the whole route being re-uploaded to the native SDK, sixty
  /// times a second.
  Polyline? _routePolylineFor(List<LatLng> route) {
    if (route.isEmpty) {
      _routePolyline = null;
      return null;
    }

    final existing = _routePolyline;
    if (existing != null && identical(existing.points, route)) {
      return existing;
    }

    _routePolyline = Polyline(
      polylineId: const PolylineId('route'),
      points: route,
      color: const Color(0xFFF5B400),
      width: 5,
      jointType: JointType.round,
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
    );
    return _routePolyline;
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final routeLine = _routePolylineFor(_drawnRoute);
    final markerPosition =
        _animatedDriverPosition ??
        (ride.lastDriverLocation != null
            ? LatLng(ride.lastDriverLocation!.lat, ride.lastDriverLocation!.lng)
            : null);

    return GoogleMap(
      style: AppMapStyle.light,
      initialCameraPosition: CameraPosition(
        target: LatLng(ride.pickup.lat, ride.pickup.lng),
        zoom: 15,
      ),
      onMapCreated: (c) => _mapController = c,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      // Gestures the rider makes are not fought over: the follow-camera only
      // pans, and these two are what the SDK would otherwise spend work on.
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      polylines: {if (routeLine != null) routeLine},
      markers: {
        ..._staticMarkersFor(ride),
        if (markerPosition != null)
          Marker(
            markerId: const MarkerId('driver'),
            position: markerPosition,
            rotation: _animatedRotation,
            icon: widget.driverIcon,
            anchor: const Offset(0.5, 0.5),
            flat: true,
          ),
      },
    );
  }
}
