import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/providers/core_providers.dart';
import '../data/bus_driver_repository.dart';
import '../data/models/bus_driver_models.dart';

final busDriverRepositoryProvider = Provider<BusDriverRepository>((ref) {
  return BusDriverRepository(ref.watch(apiClientProvider));
});

enum BusAuthStatus { unknown, authenticated, unauthenticated }

class BusAuthState {
  final BusAuthStatus status;
  final BusDriverProfile? profile;

  const BusAuthState({this.status = BusAuthStatus.unknown, this.profile});

  BusAuthState copyWith({BusAuthStatus? status, BusDriverProfile? profile}) =>
      BusAuthState(status: status ?? this.status, profile: profile ?? this.profile);
}

/// Marks that the saved token belongs to a bus driver, so the splash screen can
/// route to the bus flow without first treating it as a taxi session.
const _kBusSessionFlag = 'bus_session_active';

class BusAuthNotifier extends StateNotifier<BusAuthState> {
  final Ref ref;
  BusAuthNotifier(this.ref) : super(const BusAuthState());

  BusDriverRepository get _repo => ref.read(busDriverRepositoryProvider);

  Future<String?> sendLoginOtp(String phone) => _repo.sendLoginOtp(phone);

  /// Verifies the login OTP, saves the token, loads the full profile and marks
  /// the session as a bus session. Returns the profile.
  Future<BusDriverProfile> loginWithOtp(String phone, String otp) async {
    final result = await _repo.verifyLoginOtp(phone, otp);
    if (result.token == null || result.token!.isEmpty) {
      throw Exception('Verification failed. Please try again.');
    }
    return _establishSession(result.token!);
  }

  /// Called after onboarding completes (which already issued a token).
  Future<BusDriverProfile> completeSignup(String token) => _establishSession(token);

  Future<BusDriverProfile> _establishSession(String token) async {
    await ref.read(secureStorageServiceProvider).saveToken(token);
    await _setBusFlag(true);
    final profile = await _repo.getProfile();
    state = BusAuthState(status: BusAuthStatus.authenticated, profile: profile);
    unawaited(_registerFcm());
    return profile;
  }

  /// Restores a bus session on launch. Returns the profile when the saved token
  /// is a bus driver's, otherwise null (so the caller falls back to taxi).
  Future<BusDriverProfile?> restore() async {
    if (!await _busFlag()) return null;
    final token = await ref.read(secureStorageServiceProvider).readToken();
    if (token == null || token.isEmpty) {
      await _setBusFlag(false);
      return null;
    }
    try {
      final profile = await _repo.getProfile();
      if (!profile.isBusDriver) {
        await _setBusFlag(false);
        return null;
      }
      state = BusAuthState(status: BusAuthStatus.authenticated, profile: profile);
      unawaited(_registerFcm());
      return profile;
    } catch (_) {
      // Keep the token (could be a transient network error); report no session.
      return null;
    }
  }

  Future<BusDriverProfile?> refreshProfile() async {
    try {
      final profile = await _repo.getProfile();
      state = state.copyWith(status: BusAuthStatus.authenticated, profile: profile);
      return profile;
    } catch (_) {
      return null;
    }
  }

  Future<BusApprovalStatus?> checkApproval() async {
    final phone = state.profile?.phone ?? '';
    try {
      return await _repo.getApprovalStatus(phone);
    } catch (_) {
      return null;
    }
  }

  Future<void> logout() async {
    await _setBusFlag(false);
    await ref.read(secureStorageServiceProvider).clearAll();
    state = const BusAuthState(status: BusAuthStatus.unauthenticated);
  }

  Future<void> _registerFcm() async {
    try {
      final notifications = ref.read(notificationServiceProvider);
      final token = await notifications.init(
        onForegroundMessage: (_) {},
        onMessageOpened: (_) {},
      );
      if (token == null || token.isEmpty) return;
      await ref.read(apiClientProvider).post(ApiConstants.fcmToken, data: {
        'token': token,
        'platform': kIsWeb ? 'web' : (Platform.isIOS ? 'ios' : 'android'),
      });
    } catch (_) {
      // Non-fatal: a bus driver can still operate without push.
    }
  }

  Future<bool> _busFlag() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kBusSessionFlag) ?? false;
  }

  Future<void> _setBusFlag(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBusSessionFlag, value);
  }
}

final busAuthProvider = StateNotifierProvider<BusAuthNotifier, BusAuthState>((ref) {
  return BusAuthNotifier(ref);
});
