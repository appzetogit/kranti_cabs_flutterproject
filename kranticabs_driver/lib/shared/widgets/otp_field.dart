import 'package:flutter/material.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import '../../core/theme/app_colors.dart';

class OtpFieldWidget extends StatelessWidget {
  final TextEditingController controller;
  final int length;
  final void Function(String) onCompleted;
  final void Function(String)? onChanged;

  const OtpFieldWidget({
    super.key,
    required this.controller,
    required this.onCompleted,
    this.length = 4,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PinCodeTextField(
      appContext: context,
      length: length,
      controller: controller,
      autoDisposeControllers: false,
      keyboardType: TextInputType.number,
      animationType: AnimationType.fade,
      backgroundColor: Colors.transparent,
      onCompleted: onCompleted,
      onChanged: onChanged ?? (_) {},
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      textStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w900,
        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
      ),
      pinTheme: PinTheme(
        shape: PinCodeFieldShape.box,
        borderRadius: BorderRadius.circular(16),
        fieldHeight: 64,
        fieldWidth: 64,
        borderWidth: 1.5,
        activeColor: AppColors.primary,
        selectedColor: AppColors.primary,
        inactiveColor: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        activeFillColor: isDark ? AppColors.darkCard : Colors.white,
        selectedFillColor: isDark ? AppColors.darkCard : Colors.white,
        inactiveFillColor: isDark ? AppColors.darkCard : Colors.white,
      ),
      enableActiveFill: true,
      cursorColor: AppColors.primary,
    );
  }
}
