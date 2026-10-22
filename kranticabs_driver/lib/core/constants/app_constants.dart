import 'dart:io';
import 'package:flutter/foundation.dart';

/// Single source of truth for every environment-specific value the app needs
/// (backend host, package identity, support contact). Update values here
/// only — nothing else in the codebase should hardcode these.
///
/// Platform keys are deliberately not here: Firebase reads its config from
/// `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist`,
/// and the Maps SDK key lives in `AndroidManifest.xml` and `AppDelegate.swift`,
/// which is where each SDK looks for it. Copies here were never read and only
/// spread the keys further.
class AppConstants {
  AppConstants._();

  static const String title = 'KrantiCabs Rider';

  /// Backend REST API base URL (all endpoints are mounted under `/api/v1`).
  static const String baseUrl = 'https://kranticabs.com/api/v1';

  /// Socket.IO server base (same host, root path — see `Backend/socket-server.js`).
  static const String socketUrl = 'https://kranticabs.com';

  /// Plain host, no `/api/v1` — what a server-relative media path like
  /// `/uploads/vehicle-types/…` needs prefixed onto it. Same value as
  /// [socketUrl]; named separately so call sites read as "resolving a media
  /// URL", not "hitting the socket server".
  static const String mediaBaseUrl = socketUrl;



  static String firebaseApiKey = (kIsWeb || Platform.isAndroid)
      ? 'AIzaSyBcp-P8Gxh7r7huHJVM8A1hwvRUG3gO940'
      : ''; // TODO: fill in once GoogleService-Info.plist is added for iOS
  static String firebaseAppId = (kIsWeb || Platform.isAndroid)
      ? '1:1092116530873:android:53164867b06f5c99a3fd68'
      : '';
  static String firebaseMessagingSenderId = (kIsWeb || Platform.isAndroid)
      ? '1092116530873'
      : '';
  static String firebaseProjectId = (kIsWeb || Platform.isAndroid)
      ? 'kranticabs-2cfd1'
      : '';

  /// Google Maps API key (Maps SDK for Android/iOS + Geocoding API enabled).
  static const String mapKey = 'AIzaSyArBbII2fgAuVaycfkEAm1GcuyvKPTSWyc';

  /// Razorpay publishable key — not yet provided.
  static const String stripPublishKey = '';


  static const String packageName = 'com.kranticabs.delivery';

  /// Driver support line and inbox shown in the Help Center. Empty until the
  /// real ones exist: an empty value hides its row, so a placeholder number or 
  /// another company's address can never reach a driver again.
  static const String supportPhone = '';
  static const String supportEmail = '';

  // --- App behaviour constants (unrelated to environment/build config) ---
  static const int otpLength = 4;
  static const int phoneLength = 10;
  static const double defaultZoomLevel = 16;
  static const Duration otpResendCooldown = Duration(seconds: 30);
}
