import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class RegistrationProgressBar extends StatelessWidget {
  final int currentStep; // 1, 2, 3
  final int totalSteps; // Default 3

  const RegistrationProgressBar({
    super.key,
    required this.currentStep,
    this.totalSteps = 3,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(totalSteps, (index) {
          final stepNumber = index + 1;
          final isCompleted = stepNumber < currentStep;
          final isActive = stepNumber == currentStep;
          final isReached = stepNumber <= currentStep;
          final isLast = stepNumber == totalSteps;

          return Expanded(
            flex: isLast ? 0 : 1,
            child: Row(
              children: [
                // Animated Step Circle (1, 2, 3)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isReached
                        ? AppColors.primary
                        : const Color(0xFF222222),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isReached
                          ? AppColors.primary
                          : const Color(0xFF334155),
                      width: 1.5,
                    ),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.4),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: isCompleted
                      ? const Icon(
                          Icons.check_rounded,
                          color: Color(0xFF11191D),
                          size: 20,
                        )
                      : Text(
                          '$stepNumber',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: isReached
                                ? const Color(0xFF11191D)
                                : const Color(0xFF94A3B8),
                          ),
                        ),
                ),

                // Connecting Line between Step Circles
                if (!isLast)
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      height: 2.5,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: (index + 2) <= currentStep
                            ? AppColors.primary
                            : const Color(0xFF2E2E2E),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
