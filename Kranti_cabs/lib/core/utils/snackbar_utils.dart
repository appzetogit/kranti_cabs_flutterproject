import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class SnackbarUtils {
  SnackbarUtils._();

  static void success(BuildContext context, String message) => _show(
        context,
        message,
        icon: Icons.check_circle_rounded,
        color: AppColors.success,
      );

  static void error(BuildContext context, String message) => _show(
        context,
        message,
        icon: Icons.error_rounded,
        color: AppColors.error,
      );

  static void info(BuildContext context, String message) => _show(
        context,
        message,
        icon: Icons.info_rounded,
        color: AppColors.info,
      );

  static void _show(
    BuildContext context,
    String message, {
    required IconData icon,
    required Color color,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
  }
}
