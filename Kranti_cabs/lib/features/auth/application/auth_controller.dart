import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/navigation/navigator_key.dart';
import '../../../core/providers/core_providers.dart';
import '../../home/application/ride_search_controller.dart';
import '../data/auth_repository.dart';
import '../data/models/user_model.dart';
import 'auth_providers.dart';
import 'auth_state.dart';

class AuthController extends StateNotifier<AuthState> {
  /// Guarded so repeated auth events cannot stack duplicate listeners.
  StreamSubscription<String>? _fcmRefreshSub;

  final Ref ref;

  AuthController(this.ref) : super(const AuthState.unknown()) {
    ref.read(dioClientProvider).onUnauthorized = _handleUnauthorized;
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<void> bootstrap() async {
    final token = await ref.read(secureStorageServiceProvider).readToken();
    if (token == null || token.isEmpty) {
      state = state.copyWith(status: AuthStatus.unauthenticated);
      return;
    }
    try {
      final user = await _repo.getCurrentUser();
      state = AuthState(status: AuthStatus.authenticated, user: user);
      ref.read(socketServiceProvider).connect(token);
      // Arm dispatch listeners now, not when the search screen mounts —
      // `rideAccepted` can land within a second of the ride being created.
      ref.read(rideSearchControllerProvider);
      unawaited(_registerFcmToken());
    } catch (_) {
      await ref.read(secureStorageServiceProvider).deleteToken();
      state = state.copyWith(status: AuthStatus.unauthenticated);
    }
  }

  /// Registers this device's push token with the backend so it can receive
  /// ride/notification pushes. Best-effort: Firebase may not be configured
  /// yet in every build, and this should never block sign-in.
  Future<void> _registerFcmToken() async {
    if (kIsWeb) return;

    // Goes through NotificationService rather than calling `getToken()` bare:
    // it asks for the notification permission, initialises the local-notification
    // channel and registers the foreground/background handlers. None of that was
    // happening — the service existed but nothing ever called `init()` — so the
    // app had no notification permission on Android 13+, no channel, and no
    // handlers, and every push it was sent went nowhere.
    final token = await ref.read(notificationServiceProvider).init(
          onForegroundMessage: _handlePushMessage,
          onMessageOpened: _handlePushMessage,
        );

    // FCM rotates tokens (reinstall, restore, app-data clear). Without
    // re-registering, the server keeps a dead token and every ride push stops
    // arriving with no visible symptom. Guarded so repeated auth events
    // (bootstrap, then login) cannot stack duplicate subscriptions.
    _fcmRefreshSub ??= FirebaseMessaging.instance.onTokenRefresh.listen(_uploadFcmToken);

    if (token == null || token.isEmpty) {
      developer.log(
        'No FCM token — this device will receive no ride notifications',
        name: 'AuthController',
        level: 1000,
      );
      return;
    }

    await _uploadFcmToken(token);
  }

  /// Ride pushes double as a nudge to resync: a status change that arrived
  /// while the socket was down is otherwise invisible until the next poll.
  void _handlePushMessage(RemoteMessage message) {
    ref.read(socketServiceProvider).ensureConnected();
  }

  Future<void> _uploadFcmToken(String token) async {
    if (token.isEmpty) return;
    try {
      final platform = defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
      await _repo.saveFcmToken(token, platform: platform);
    } catch (error) {
      // Logged rather than swallowed: a rejected token means this rider gets no
      // push at all, and the silent catch here is why that went unnoticed.
      developer.log(
        'FCM token registration failed — no ride notifications will arrive',
        name: 'AuthController',
        error: error,
        level: 1000,
      );
    }
  }

  Future<OtpSendResult> sendOtp(String phone) {
    return _repo.sendOtp(phone);
  }

  Future<OtpVerifyResult> verifyOtp({required String phone, required String otp}) async {
    final result = await _repo.verifyOtp(phone: phone, otp: otp);
    if (result.exists && result.token != null && result.user != null) {
      await _persistSession(token: result.token!, user: result.user!);
    }
    return result;
  }

  Future<void> completeSignup({
    required String phone,
    required String name,
    String? email,
    String? gender,
    String? referralCode,
  }) async {
    final session = await _repo.signup(
      phone: phone,
      name: name,
      email: email,
      gender: gender,
      referralCode: referralCode,
    );
    await _persistSession(token: session.token, user: session.user);
  }

  Future<void> _persistSession({required String token, required UserModel user}) async {
    await ref.read(secureStorageServiceProvider).saveToken(token);
    state = AuthState(status: AuthStatus.authenticated, user: user);
    ref.read(socketServiceProvider).connect(token);
    ref.read(rideSearchControllerProvider);
    unawaited(_registerFcmToken());
  }

  void updateUser(UserModel user) {
    state = state.copyWith(user: user);
  }

  @override
  void dispose() {
    _fcmRefreshSub?.cancel();
    super.dispose();
  }

  Future<void> logout() async {
    await ref.read(secureStorageServiceProvider).deleteToken();
    ref.read(socketServiceProvider).disconnect();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> _handleUnauthorized() async {
    final wasAuthenticated = state.status == AuthStatus.authenticated;
    await logout();
    if (!wasAuthenticated) return;
    final context = rootNavigatorKey.currentContext;
    if (context != null) {
      GoRouter.of(context).go('/system/session-expired');
    }
  }
}
