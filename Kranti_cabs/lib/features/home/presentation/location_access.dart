import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/core_providers.dart';
import '../application/home_providers.dart';

/// Gets location working, from wherever the rider asked for it.
///
/// Asks for permission if it has not been decided, otherwise sends the rider
/// to the screen that explains what is off - GPS, or the permission - and
/// returns true once location is usable.
///
/// The two explanation screens existed before this but nothing ever opened
/// them, so a rider with location off was shown nothing at all.
Future<bool> requestLocationAccess(BuildContext context, WidgetRef ref) async {
  final service = ref.read(locationServiceProvider);

  // Shows the system dialog only when permission is still undecided.
  final result = await service.ensurePermission();
  if (result.granted) {
    _refresh(ref);
    return true;
  }
  if (!context.mounted) return false;

  if (!result.serviceEnabled) {
    await context.push<bool>('/system/gps-disabled');
  } else {
    await context.push<bool>('/system/location-permission-denied');
  }

  // Whatever the screen returned, ask the device: the rider may have fixed it
  // and then pressed back instead of waiting for the screen to close.
  var after = await service.checkStatus();

  // GPS was the problem and is now on, but permission was never asked for:
  // ask now rather than make the rider tap a second time.
  if (after.serviceEnabled && !after.granted && !after.permanentlyDenied) {
    after = await service.ensurePermission();
  }

  if (after.granted) {
    _refresh(ref);
    return true;
  }
  ref.invalidate(locationStatusProvider);
  return false;
}

void _refresh(WidgetRef ref) {
  ref.invalidate(locationStatusProvider);
  ref.invalidate(currentPositionProvider);
}
