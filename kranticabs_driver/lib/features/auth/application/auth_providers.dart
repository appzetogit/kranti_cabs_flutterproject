import 'dart:async';
import 'dart:io' show Platform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/constants/storage_keys.dart';
import '../../../core/navigation/navigator_key.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/services/ride_offer_channel.dart';
import '../../../core/services/ride_offer_permission_flow.dart';
import '../../ride/application/ride_providers.dart';
import '../data/auth_repository.dart';
import '../data/driver_model.dart';
import 'auth_state.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(apiClientProvider));
});

class AuthNotifier extends StateNotifier<AuthState> {
  final Ref ref;

  /// Guarded so repeated `onAuthenticated` calls (session restore, then login)
  /// can never stack duplicate listeners.
  StreamSubscription<String>? _fcmRefreshSub;

  AuthNotifier(this.ref) : super(const AuthState());

  @override
  void dispose() {
    _fcmRefreshSub?.cancel();
    super.dispose();
  }

  Future<void> restoreSession() async {
    final token = await ref.read(secureStorageServiceProvider).readToken();
    if (token == null || token.isEmpty) {
      state = state.copyWith(status: AuthStatus.unauthenticated);
      return;
    }
    try {
      final driver = await ref.read(authRepositoryProvider).getCurrentDriver();
      state = AuthState(status: AuthStatus.authenticated, driver: driver);
      _cacheDriver(driver);
      onAuthenticated(token);
    } catch (_) {
      await ref.read(secureStorageServiceProvider).deleteToken();
      state = state.copyWith(status: AuthStatus.unauthenticated);
    }
  }

  Future<OtpSendResult> sendOtp(String phone) {
    return ref.read(authRepositoryProvider).sendLoginOtp(phone);
  }

  Future<DriverModel> verifyOtp(String phone, String otp) async {
    final result = await ref.read(authRepositoryProvider).verifyLoginOtp(phone, otp);
    if (result.token == null || result.driver == null) {
      throw Exception('Verification failed. Please try again.');
    }
    await ref.read(secureStorageServiceProvider).saveToken(result.token!);
    _cacheDriver(result.driver!);
    state = AuthState(status: AuthStatus.authenticated, driver: result.driver);
    onAuthenticated(result.token!);
    return result.driver!;
  }

  /// Central hook run every time a driver session becomes active (session
  /// restore, OTP login, or signup completion): connects the ride socket,
  /// eagerly binds ride-request listeners (so an incoming ride can never be
  /// missed while the driver is still on an earlier screen), and starts push
  /// notifications.
  void onAuthenticated(String token) {
    ref.read(socketServiceProvider).connect(token);
    ref.read(rideProvider);
    unawaited(_initPushNotifications());
    unawaited(_requestRideOfferPermissions());
    // Lets the native offer card decline against the server while the app is
    // closed, instead of the decline waiting for the next app launch.
    unawaited(RideOfferChannel.saveSession(
      token: token,
      apiBaseUrl: ApiConstants.baseUrl,
    ));
  }

  /// Asks for the full-screen-alert, overlay and battery permissions the ride
  /// offer card depends on.
  ///
  /// Deferred until after login: each one opens a Settings page, and a driver
  /// who has not signed in yet has no reason to grant any of them. The flow
  /// itself is sequential — see [RideOfferPermissionFlow].
  Future<void> _requestRideOfferPermissions() async {
    // Lets the post-login screen settle before the first Settings page opens.
    await Future<void>.delayed(const Duration(seconds: 2));
    await ref.read(rideOfferPermissionFlowProvider.notifier).requestMissing();
  }

  Future<void> _initPushNotifications() async {
    final notifications = ref.read(notificationServiceProvider);
    final token = await notifications.init(
      onForegroundMessage: _handleRemoteMessage,
      onMessageOpened: _handleNotificationTap,
    );

    // Re-register whenever FCM rotates the token, otherwise the server keeps a
    // dead one and ride offers stop arriving with no visible symptom.
    _fcmRefreshSub ??= notifications.onTokenRefresh.listen(_registerFcmToken);

    // A push that launched the app from terminated is delivered here, not
    // through `onMessageOpenedApp` — and a cold start is exactly the case where
    // the socket was guaranteed to be down when the offer was dispatched.
    final launchMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (launchMessage != null) {
      _handleNotificationTap(launchMessage);
    }

    if (token == null || token.isEmpty) {
      // Plain print (not developer.log): must show up in `adb logcat` on a
      // standalone-launched build with no debugger attached, since
      // developer.log only reaches a live VM-service listener.
      // ignore: avoid_print
      print('FCM token unavailable — push notifications will not arrive');
      return;
    }

    await _registerFcmToken(token);
  }

  Future<void> _registerFcmToken(String token) async {
    if (token.isEmpty) return;
    try {
      await ref.read(apiClientProvider).post(ApiConstants.fcmToken, data: {
        'token': token,
        'platform': kIsWeb ? 'web' : (Platform.isIOS ? 'ios' : 'android'),
      });
      // ignore: avoid_print
      print('FCM token registered with server (${token.length} chars)');
    } catch (error) {
      // Deliberately logged rather than swallowed: a rejected token means this
      // driver receives no push at all, and a silent catch hides that entirely.
      // ignore: avoid_print
      print('FCM token registration failed: $error');
    }
  }

  /// A `ride_request` push is the only signal that reaches the driver when the
  /// socket has dropped, so it doubles as the trigger to bring the transport
  /// back up. The server does not re-emit `rideRequest` to a driver it already
  /// marked as notified, hence the explicit resync rather than relying on
  /// reconnect alone.
  void _handleRemoteMessage(RemoteMessage message) {
    if (message.data['type'] != 'ride_request') return;

    final socket = ref.read(socketServiceProvider);
    final hasSession = socket.ensureConnected();
    if (!hasSession) return;

    unawaited(ref.read(rideProvider.notifier).syncPendingOffers());
  }

  void _handleNotificationTap(RemoteMessage message) {
    // Recover the offer before routing, otherwise the request screen opens
    // against empty state when the push arrived on a dead socket.
    _handleRemoteMessage(message);

    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    final type = message.data['type'];
    if (type == 'ride_request') {
      GoRouter.of(context).push('/ride-request');
    } else {
      GoRouter.of(context).push('/home');
    }
  }

  void updateDriver(DriverModel driver) {
    state = state.copyWith(driver: driver);
    _cacheDriver(driver);
  }

  /// Re-fetches the full driver profile from the backend. Use this after any PATCH
  /// endpoint that returns only a partial driver object, to avoid clobbering cached
  /// fields (vehicle, documents, rating, status) with their JSON defaults.
  Future<void> refresh() async {
    final driver = await ref.read(authRepositoryProvider).getCurrentDriver();
    updateDriver(driver);
  }

  void authenticateWithDriver(DriverModel driver) {
    state = AuthState(status: AuthStatus.authenticated, driver: driver);
    _cacheDriver(driver);
  }

  void _cacheDriver(DriverModel driver) {
    final box = ref.read(localStorageServiceProvider).settings;
    box.put(StorageKeys.driverJson, ref.read(authRepositoryProvider).encodeDriver(driver));
  }

  Future<void> logout() async {
    ref.read(socketServiceProvider).disconnect();
    await RideOfferChannel.clearSession();
    await ref.read(secureStorageServiceProvider).clearAll();
    final box = ref.read(localStorageServiceProvider).settings;
    await box.delete(StorageKeys.driverJson);
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref);
});
