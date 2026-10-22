import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../application/delivery_booking_controller.dart';

/// Sender & receiver capture, shown over the address screen.
///
/// Both contacts are mandatory server-side (the driver calls them at each end),
/// so this validates before it will save rather than failing at booking time.
class DeliveryContactsSheet extends ConsumerStatefulWidget {
  const DeliveryContactsSheet({super.key});

  static Future<bool> show(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => const DeliveryContactsSheet(),
    );
    return saved ?? false;
  }

  @override
  ConsumerState<DeliveryContactsSheet> createState() => _DeliveryContactsSheetState();
}

class _DeliveryContactsSheetState extends ConsumerState<DeliveryContactsSheet> {
  late final TextEditingController _senderName;
  late final TextEditingController _senderPhone;
  late final TextEditingController _receiverName;
  late final TextEditingController _receiverPhone;
  late final TextEditingController _goodsType;

  bool _sameAsSender = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final state = ref.read(deliveryBookingProvider);
    _senderName = TextEditingController(text: state.senderName);
    _senderPhone = TextEditingController(text: state.senderMobile);
    _receiverName = TextEditingController(text: state.receiverName);
    _receiverPhone = TextEditingController(text: state.receiverMobile);
    _goodsType = TextEditingController(text: state.goodsType);
  }

  @override
  void dispose() {
    _senderName.dispose();
    _senderPhone.dispose();
    _receiverName.dispose();
    _receiverPhone.dispose();
    _goodsType.dispose();
    super.dispose();
  }

  void _applySameAsSender(bool value) {
    if (!mounted) return;
    setState(() {
      _sameAsSender = value;
      if (value) {
        _receiverName.text = _senderName.text;
        _receiverPhone.text = _senderPhone.text;
      }
    });
  }

  void _save() {
    final senderName = _senderName.text.trim();
    final senderPhone = _senderPhone.text.trim();
    final receiverName = _receiverName.text.trim();
    final receiverPhone = _receiverPhone.text.trim();

    if (senderName.isEmpty || senderPhone.length < 10) {
      setState(() => _error = 'Enter the sender name and a 10-digit mobile number');
      return;
    }
    if (receiverName.isEmpty || receiverPhone.length < 10) {
      setState(() => _error = 'Enter the receiver name and a 10-digit mobile number');
      return;
    }

    final goodsType = _goodsType.text.trim();
    if (goodsType.isEmpty) {
      // The driver decides whether they can carry it, so this cannot be blank.
      setState(() => _error = 'Tell us what you are sending');
      return;
    }

    ref.read(deliveryBookingProvider.notifier).setContacts(
          senderName: senderName,
          senderMobile: senderPhone,
          receiverName: receiverName,
          receiverMobile: receiverPhone,
          goodsType: goodsType,
        );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 16,
        bottom: 18 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'BOOKING DETAILS',
                  style: TextStyle(
                    fontSize: 9.5,
                    letterSpacing: 0.7,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF94A3B8),
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: Icon(Icons.close, size: 20, color: isDark ? Colors.white : const Color(0xFF0F172A)),
                ),
              ],
            ),
            Text(
              'Sender & receiver',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 18),
            const _SectionLabel(icon: Icons.person_outline, label: 'Sender', color: AppColors.primary),
            const SizedBox(height: 8),
            _Field(controller: _senderName, hint: 'Sender name'),
            const SizedBox(height: 10),
            const Text('MOBILE NUMBER', style: _labelStyle),
            const SizedBox(height: 6),
            _Field(controller: _senderPhone, hint: '10-digit mobile number', phone: true),
            const SizedBox(height: 20),
            const _SectionLabel(icon: Icons.location_on_outlined, label: 'Receiver', color: Color(0xFFEF4444)),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _applySameAsSender(!_sameAsSender),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: isDark ? Border.all(color: const Color(0xFF334155)) : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      _sameAsSender ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 20,
                      color: isDark ? const Color(0xFF60A5FA) : AppColors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Same as Sender',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            "Use sender's name and mobile for receiver",
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            _Field(controller: _receiverName, hint: 'Receiver name', enabled: !_sameAsSender),
            const SizedBox(height: 10),
            const Text('MOBILE NUMBER', style: _labelStyle),
            const SizedBox(height: 6),
            _Field(
              controller: _receiverPhone,
              hint: '10-digit mobile number',
              phone: true,
              enabled: !_sameAsSender,
            ),
            const SizedBox(height: 20),
            const _SectionLabel(
              icon: Icons.inventory_2_outlined,
              label: 'Goods type',
              color: Color(0xFF0EA5E9),
            ),
            const SizedBox(height: 8),
            _Field(controller: _goodsType, hint: 'e.g. Documents, medicines, clothes'),
            const SizedBox(height: 4),
            const Text(
              'Shown to the delivery captain so they know what they are carrying.',
              style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12.5)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: isDark ? const Color(0xFF2563EB) : const Color(0xFF0F172A),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _save,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Save Details', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                    SizedBox(width: 6),
                    Icon(Icons.chevron_right, size: 18, color: Colors.white),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _labelStyle = TextStyle(
  fontSize: 9.5,
  letterSpacing: 0.7,
  fontWeight: FontWeight.w800,
  color: Color(0xFF94A3B8),
);

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _SectionLabel({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool phone;
  final bool enabled;

  const _Field({
    required this.controller,
    required this.hint,
    this.phone = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: phone ? TextInputType.phone : TextInputType.name,
      inputFormatters: phone
          ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)]
          : null,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: enabled
            ? (isDark ? Colors.white : const Color(0xFF0F172A))
            : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          fontSize: 13.5,
          color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
        ),
        filled: true,
        fillColor: enabled
            ? (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC))
            : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB), width: 1.5),
        ),
      ),
    );
  }
}
