import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../navigation/navigator_key.dart';
import '../network/api_client.dart';
import '../network/dio_client.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/razorpay_service.dart';
import '../services/ringtone_service.dart';
import '../services/voice_announce_service.dart';
import '../services/socket_service.dart';
import '../storage/local_storage_service.dart';
import '../storage/secure_storage_service.dart';

/// These are overridden in main.dart with instances created during app bootstrap.
final secureStorageServiceProvider = Provider<SecureStorageService>((ref) {
  throw UnimplementedError('secureStorageServiceProvider must be overridden');
});

final localStorageServiceProvider = Provider<LocalStorageService>((ref) {
  throw UnimplementedError('localStorageServiceProvider must be overridden');
});

final dioClientProvider = Provider<DioClient>((ref) {
  final client = DioClient(ref.watch(secureStorageServiceProvider));
  client.onUnauthorized = () {
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    final router = GoRouter.of(context);
    if (router.routerDelegate.currentConfiguration.uri.path != '/session-expired') {
      router.go('/session-expired');
    }
  };
  return client;
});

final dioProvider = Provider<Dio>((ref) {
  return ref.watch(dioClientProvider).dio;
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref.watch(dioProvider));
});

final socketServiceProvider = Provider<SocketService>((ref) {
  final service = SocketService();
  ref.onDispose(service.disconnect);
  return service;
});

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

final razorpayServiceProvider = Provider<RazorpayService>((ref) {
  final service = RazorpayService();
  ref.onDispose(service.dispose);
  return service;
});

final ringtoneServiceProvider = Provider<RingtoneService>((ref) {
  final service = RingtoneService();
  ref.onDispose(service.dispose);
  return service;
});

final voiceAnnounceServiceProvider = Provider<VoiceAnnounceService>((ref) {
  final service = VoiceAnnounceService();
  ref.onDispose(service.stop);
  return service;
});
