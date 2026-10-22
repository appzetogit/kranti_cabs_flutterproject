import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

class UpdateService {
  UpdateService._();

  /// Checks for available updates on the Google Play Store (Android only).
  ///
  /// For flexible updates, it starts the download and completes it automatically.
  /// For immediate updates, it displays a fullscreen overlay blocking app usage.
  static Future<void> checkForUpdate() async {
    if (!Platform.isAndroid) {
      debugPrint('In-App Update: Supported on Android only. Skipping check.');
      return;
    }

    try {
      debugPrint('In-App Update: Checking for available updates...');
      final AppUpdateInfo updateInfo = await InAppUpdate.checkForUpdate();

      if (updateInfo.updateAvailability == UpdateAvailability.updateAvailable) {
        debugPrint('In-App Update: An update is available.');

        if (updateInfo.immediateUpdateAllowed) {
          debugPrint('In-App Update: Starting immediate (forced) update flow.');
          final AppUpdateResult result = await InAppUpdate.performImmediateUpdate();
          debugPrint('In-App Update: Immediate update result: $result');
        } else if (updateInfo.flexibleUpdateAllowed) {
          debugPrint('In-App Update: Starting flexible (background) update flow.');
          final AppUpdateResult result = await InAppUpdate.startFlexibleUpdate();

          if (result == AppUpdateResult.success) {
            debugPrint('In-App Update: Flexible update downloaded. Completing...');
            await InAppUpdate.completeFlexibleUpdate();
            debugPrint('In-App Update: Flexible update applied successfully.');
          } else {
            debugPrint('In-App Update: Flexible update result: $result');
          }
        } else {
          debugPrint('In-App Update: Update available, but neither immediate nor flexible allowed.');
        }
      } else {
        debugPrint('In-App Update: App is up to date.');
      }
    } catch (e) {
      debugPrint('In-App Update Error: Update check failed: $e');
    }
  }
}
