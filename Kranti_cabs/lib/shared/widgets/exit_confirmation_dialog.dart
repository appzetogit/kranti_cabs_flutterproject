import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<bool?> showExitConfirmationDialog(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final bgColor = isDark ? const Color(0xFF222222) : Colors.white;
  final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
  final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  final borderColor = isDark ? const Color(0xFF2E2E2E) : const Color(0xFFE2E8F0);
  const goldColor = Color(0xFFF5B400);

  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext dialogContext) {
      return Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: borderColor, width: 1.2),
        ),
        backgroundColor: bgColor,
        elevation: 16,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Kranti Gold Power / Exit Icon Badge
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: goldColor.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: goldColor.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: goldColor.withValues(alpha: 0.22),
                      blurRadius: 16,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.power_settings_new_rounded,
                  color: goldColor,
                  size: 30,
                ),
              ),
              const SizedBox(height: 18),

              // Title with Kranti Gold accent
              RichText(
                textAlign: TextAlign.center,
                text: const TextSpan(
                  children: [
                    TextSpan(
                      text: 'Exit ',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                    TextSpan(
                      text: 'Kranti Cabs',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: goldColor,
                        letterSpacing: -0.3,
                      ),
                    ),
                    TextSpan(
                      text: '?',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Message
              Text(
                'Are you sure you want to exit the app?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),

              // Actions Row (Cancel & Exit)
              Row(
                children: [
                  // Cancel Button
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textPrimary,
                          backgroundColor: isDark ? const Color(0xFF11191D) : const Color(0xFFF1F5F9),
                          side: BorderSide(
                            color: borderColor,
                            width: 1.2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Exit Button (Kranti Gold Brand Accent)
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: goldColor,
                          foregroundColor: const Color(0xFF0A0A0A),
                          elevation: 0,
                          shadowColor: goldColor.withValues(alpha: 0.35),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(dialogContext).pop(true);
                          SystemNavigator.pop();
                        },
                        child: const Text(
                          'Exit',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0A0A0A),
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
