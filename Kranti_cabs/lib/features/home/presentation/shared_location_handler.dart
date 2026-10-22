import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../core/navigation/navigator_key.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/application/auth_state.dart';
import '../application/booking_controller.dart';
import '../application/booking_state.dart';
import '../application/home_providers.dart';
import '../application/shared_location_parser.dart';

/// Lets a rider tap a location in another app (a WhatsApp pin or live
/// location, a pasted Google Maps link) and choose Kranti Cabs from the "Open with"
/// sheet: the place becomes the drop point and they land on the ride-type
/// screen, pickup already set to where they are.
///
/// MainActivity forwards the incoming intent over [_channel]. A link that
/// arrives before sign-in has finished (a cold start from the sheet) is held
/// and applied as soon as the rider is authenticated.
class SharedLocationHandler extends ConsumerStatefulWidget {
  final Widget child;

  const SharedLocationHandler({super.key, required this.child});

  @override
  ConsumerState<SharedLocationHandler> createState() => _SharedLocationHandlerState();
}

class _SharedLocationHandlerState extends ConsumerState<SharedLocationHandler> {
  static const _channel = MethodChannel('zicab/shared_location');

  SharedPlace? _pending;
  bool _dispatching = false;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onShare') {
        await _onShared(call.arguments as String?);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final initial = await _channel.invokeMethod<String>('getInitialShare');
        await _onShared(initial);
      } on MissingPluginException {
        // Platforms without the native side (iOS, web) simply never share in.
      }
    });
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  void _toast(String message) {
    final context = rootNavigatorKey.currentContext;
    if (context != null && context.mounted) SnackbarUtils.info(context, message);
  }

  Future<void> _onShared(String? raw) async {
    if (raw == null || raw.trim().isEmpty) return;

    final place = await parseSharedLocation(raw);
    if (place == null) {
      _toast("Couldn't find a location in what you shared.");
      return;
    }

    _pending = place;
    await _dispatch();
  }

  Future<void> _dispatch() async {
    if (_pending == null || _dispatching) return;
    if (ref.read(authControllerProvider).status != AuthStatus.authenticated) return;

    _dispatching = true;
    try {
      // After a cold start the splash screen is still deciding where to send
      // the rider; navigating before it finishes would be overwritten.
      for (var i = 0; i < 25; i++) {
        final path = appRouter.routerDelegate.currentConfiguration.uri.path;
        final settled = path != '/' &&
            !path.startsWith('/language') &&
            !path.startsWith('/onboarding') &&
            !path.startsWith('/auth');
        if (settled) break;
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }

      final place = _pending;
      _pending = null;
      if (place == null || !mounted) return;

      final step = ref.read(bookingControllerProvider).step;
      if (step == BookingStep.findingDriver || step == BookingStep.dispatched) {
        _toast('Finish your current booking before starting another.');
        return;
      }

      final position = await ref.read(currentPositionProvider.future);
      if (position == null) {
        _toast('Turn on location so we can set your pickup.');
        return;
      }
      final pickupAddress = await ref.read(currentAddressProvider.future);

      var dropAddress = place.label ?? '';
      if (dropAddress.isEmpty) {
        try {
          dropAddress = await ref
              .read(locationServiceProvider)
              .getAddressFromCoordinates(place.lat, place.lng);
        } catch (_) {
          // Falls through to the raw coordinates below.
        }
      }
      if (dropAddress.isEmpty) {
        dropAddress = '${place.lat.toStringAsFixed(5)}, ${place.lng.toStringAsFixed(5)}';
      }

      if (!mounted) return;
      ref.read(bookingControllerProvider.notifier)
        ..reset()
        ..setPickup(
          BookingLocation(
            lat: position.latitude,
            lng: position.longitude,
            address: pickupAddress.isNotEmpty ? pickupAddress : 'Current location',
          ),
        )
        ..setDrop(BookingLocation(lat: place.lat, lng: place.lng, address: dropAddress))
        ..goToStep(BookingStep.selectingVehicle);

      appRouter.go('/home');
      unawaited(appRouter.push('/home/ride-types'));
    } finally {
      _dispatching = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (previous, next) {
      if (next.status == AuthStatus.authenticated) unawaited(_dispatch());
    });
    return widget.child;
  }
}
