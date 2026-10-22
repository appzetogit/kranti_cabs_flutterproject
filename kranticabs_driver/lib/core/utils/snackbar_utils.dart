import 'package:flutter/material.dart';
import '../navigation/navigator_key.dart';
import '../theme/app_colors.dart';

class SnackbarUtils {
  SnackbarUtils._();

  /// Shown at the top of the screen.
  ///
  /// The driver's controls — Accept, Arrived, Start, Complete — all sit along
  /// the bottom of the ride screens, and a bottom snackbar landed directly over
  /// them: it covered the next action and swallowed taps aimed at it. Floating
  /// it up top keeps the message visible without blocking the button the driver
  /// is reaching for.
  static void _show(String message, Color color, IconData icon) {
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;

    final media = MediaQuery.maybeOf(context);
    final topInset = media?.padding.top ?? 0;
    final height = media?.size.height ?? 0;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          // `floating` still anchors to the bottom, so the bar is pushed up by
          // everything below it — leaving a gap only for the status bar.
          margin: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: height > 0 ? height - topInset - 130 : 0,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  static void success(String message) => _show(message, AppColors.success, Icons.check_circle_outline);

  static void error(String message) => _show(message, AppColors.error, Icons.error_outline);

  static void info(String message) => _show(message, AppColors.info, Icons.info_outline);

  static void warning(String message) => _show(message, AppColors.warning, Icons.warning_amber_outlined);
}
