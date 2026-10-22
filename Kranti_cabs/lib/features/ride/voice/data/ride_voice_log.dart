import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show kDebugMode;

/// Structured, prefixed logging for the voice system.
///
/// Debug builds only. The announcements run on a live trip, so this must never
/// become noise in a release log — and it must never carry a rider's addresses,
/// phone number or ride id. Callers pass timings, language codes and state
/// names only.
void rideVoiceLog(String message) {
  if (!kDebugMode) return;
  developer.log('[RideVoice] $message', name: 'RideVoice');
}
