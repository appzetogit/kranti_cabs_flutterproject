import 'package:flutter/material.dart';

/// Shared palette + building blocks for the bus-driver screens, matching the
/// driver app's dark navy theme.
class BusColors {
  BusColors._();
  static const bg = Color(0xFF11191D);
  static const card = Color(0xFF222222);
  static const border = Color(0xFF2E2E2E);
  static const teal = Color(0xFFF5B400);
  static const tealDark = Color(0xFF0F172A);
  static const textMuted = Color(0xFF94A3B8);
  static const booked = Color(0xFF334155);
}

class BusScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final Widget? bottomBar;
  final List<Widget>? actions;
  final bool showBack;

  const BusScaffold({
    super.key,
    required this.title,
    required this.body,
    this.bottomBar,
    this.actions,
    this.showBack = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BusColors.bg,
      appBar: AppBar(
        backgroundColor: BusColors.bg,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: showBack,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: actions,
      ),
      body: SafeArea(top: false, child: body),
      bottomNavigationBar: bottomBar,
    );
  }
}

class BusCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;

  const BusCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color,
    this.borderColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? BusColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor ?? BusColors.border),
      ),
      child: child,
    );
    if (onTap == null) return content;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16), child: content);
  }
}

/// Sticky bottom primary-action bar.
class BusBottomBar extends StatelessWidget {
  final String actionLabel;
  final bool isLoading;
  final VoidCallback? onPressed;

  const BusBottomBar({
    super.key,
    required this.actionLabel,
    this.isLoading = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || isLoading;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: BusColors.card,
          border: Border(top: BorderSide(color: BusColors.border)),
        ),
        child: Opacity(
          opacity: disabled ? 0.5 : 1,
          child: Material(
            color: BusColors.teal,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: disabled ? null : onPressed,
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 52,
                child: Center(
                  child: isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Color(0xFF053B38)),
                        )
                      : Text(actionLabel,
                          style: const TextStyle(
                              color: Color(0xFF053B38), fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A labelled dark text field used across the registration screens.
class BusField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData? icon;
  final TextInputType? keyboardType;

  const BusField({
    super.key,
    required this.controller,
    required this.label,
    this.hint = '',
    this.icon,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: BusColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: BusColors.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: BusColors.teal, size: 18),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: keyboardType,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    border: InputBorder.none,
                    hintText: hint,
                    hintStyle: const TextStyle(color: BusColors.textMuted, fontWeight: FontWeight.w400),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Small rounded tag chip.
class BusTag extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? color;
  const BusTag({super.key, required this.label, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? BusColors.teal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: c),
            const SizedBox(width: 4),
          ],
          Text(label, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

String busMoney(num v, [String currency = 'INR']) {
  final symbol = currency.toUpperCase() == 'INR' ? '₹' : '';
  return '$symbol${v.round()}';
}
