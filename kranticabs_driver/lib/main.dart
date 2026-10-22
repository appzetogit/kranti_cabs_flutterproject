import 'dart:developer' as developer;

import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'core/constants/app_locales.dart';
import 'core/providers/core_providers.dart';
import 'core/services/notification_service.dart';
import 'core/storage/local_storage_service.dart';
import 'core/storage/secure_storage_service.dart';
import 'core/utils/marker_icon_loader.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  final localStorage = LocalStorageService();
  await localStorage.init();
  MarkerIconLoader.attachDiskCache(localStorage.vehicleMarkerCache);
  final secureStorage = SecureStorageService();

  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (error, stackTrace) {
    developer.log(
      'Firebase failed to initialise; push notifications are off',
      name: 'main',
      error: error,
      stackTrace: stackTrace,
    );
  }

  runApp(
    EasyLocalization(
      supportedLocales: AppLocales.supported,
      path: AppLocales.path,
      fallbackLocale: AppLocales.fallback,
      child: ProviderScope(
        overrides: [
          localStorageServiceProvider.overrideWithValue(localStorage),
          secureStorageServiceProvider.overrideWithValue(secureStorage),
        ],
        child: const DriverApp(),
      ),
    ),
  );
}
