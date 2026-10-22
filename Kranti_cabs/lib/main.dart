import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app/app.dart';
import 'core/navigation/navigator_key.dart';
import 'core/providers/core_providers.dart';
import 'core/storage/local_storage_service.dart';
import 'core/storage/secure_storage_service.dart';
import 'features/ride/voice/application/ride_voice_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final localStorageService = LocalStorageService();
  await localStorageService.init();

  final secureStorageService = SecureStorageService();

  try {
    await Firebase.initializeApp();
  } catch (error) {
    // No Firebase project configured yet (missing google-services.json /
    // GoogleService-Info.plist / firebase_options.dart). The app keeps working
    // without push notifications until a real Firebase project is wired up.
    if (kDebugMode) debugPrint('Firebase init skipped: $error');
  }

  runApp(
    ProviderScope(
      overrides: [
        localStorageServiceProvider.overrideWithValue(localStorageService),
        secureStorageServiceProvider.overrideWithValue(secureStorageService),
      ],
      child: const _AppBootstrapper(),
    ),
  );
}

class _AppBootstrapper extends ConsumerStatefulWidget {
  const _AppBootstrapper();

  @override
  ConsumerState<_AppBootstrapper> createState() => _AppBootstrapperState();
}

class _AppBootstrapperState extends ConsumerState<_AppBootstrapper> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initPushNotifications();
      _resumeRideVoice();
    });
  }

  /// Re-arms the in-ride announcements for a trip that was already running when
  /// the app started. Fire-and-forget and fully self-contained: if it fails,
  /// or there is no trip, nothing about the rest of the app changes.
  void _resumeRideVoice() {
    try {
      ref.read(rideVoiceSchedulerProvider).resumeActiveRide();
    } catch (_) {}
  }

  Future<void> _initPushNotifications() async {
    final service = ref.read(notificationServiceProvider);
    await service.init(
      onForegroundMessage: (message) {
        if (kDebugMode) debugPrint('Foreground FCM message: ${message.messageId}');
      },
      onMessageOpened: (message) {
        final context = rootNavigatorKey.currentContext;
        if (context == null) return;
        final type = message.data['type']?.toString();

        // A cancelled search has no trip to track — routing to the tracking
        // screen would open a dead ride, so send the rider somewhere they can
        // actually rebook.
        if (type == 'no_drivers_found') {
          GoRouter.of(context).go('/home/no-driver');
          return;
        }

        final rideId = message.data['rideId'];
        if (rideId != null && rideId.toString().isNotEmpty) {
          GoRouter.of(context).push('/ride/tracking/$rideId');
        } else {
          GoRouter.of(context).push('/notifications');
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) => const TaxiUserApp();
}
