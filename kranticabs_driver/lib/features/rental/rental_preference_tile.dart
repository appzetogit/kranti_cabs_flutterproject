import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/providers/core_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/snackbar_utils.dart';

/// GET/PUT /drivers/me/rental-preference.
class RentalPreference {
  final bool accepts;
  final bool blockedByAdmin;
  final bool vehicleRentalEnabled;
  final bool receivesRentals;

  const RentalPreference({
    this.accepts = true,
    this.blockedByAdmin = false,
    this.vehicleRentalEnabled = true,
    this.receivesRentals = true,
  });

  factory RentalPreference.fromJson(dynamic data) {
    final json = data is Map ? Map<String, dynamic>.from(data) : const <String, dynamic>{};
    return RentalPreference(
      accepts: json['accepts'] != false,
      blockedByAdmin: json['blockedByAdmin'] == true,
      vehicleRentalEnabled: json['vehicleRentalEnabled'] != false,
      receivesRentals: json['receivesRentals'] == true,
    );
  }
}

final rentalPreferenceProvider = FutureProvider.autoDispose<RentalPreference>((ref) async {
  final data = await ref.watch(apiClientProvider).get('/drivers/me/rental-preference');
  return RentalPreference.fromJson(data);
});

/// Profile row: "Accept rental trips" switch. Hourly rental requests reach
/// the driver only while it is on, their vehicle type is rental-enabled and
/// admin has not blocked them; the subtitle says which one is missing.
class RentalPreferenceTile extends ConsumerStatefulWidget {
  const RentalPreferenceTile({super.key});

  @override
  ConsumerState<RentalPreferenceTile> createState() => _RentalPreferenceTileState();
}

class _RentalPreferenceTileState extends ConsumerState<RentalPreferenceTile> {
  bool _busy = false;

  Future<void> _set(bool accepts) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).put('/drivers/me/rental-preference', data: {'accepts': accepts});
      ref.invalidate(rentalPreferenceProvider);
      SnackbarUtils.success(accepts ? 'You will get rental trips' : 'Rental trips turned off');
    } on ApiException catch (error) {
      SnackbarUtils.error(error.message);
    } catch (_) {
      SnackbarUtils.error('Could not update. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pref = ref.watch(rentalPreferenceProvider).valueOrNull;
    if (pref == null) return const SizedBox.shrink();

    final subtitle = pref.blockedByAdmin
        ? 'Blocked by admin - contact support'
        : !pref.vehicleRentalEnabled
            ? 'Your vehicle type is not offered for rentals'
            : pref.accepts
                ? 'You get hourly rental requests'
                : 'Off - you get no rental requests';
    final canChange = !pref.blockedByAdmin && pref.vehicleRentalEnabled;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF2E1A47),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.timer_outlined, color: Color(0xFFC084FC)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Accept rental trips', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
              ],
            ),
          ),
          _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
              : Switch(
                  value: pref.accepts && canChange,
                  activeThumbColor: AppColors.primary,
                  onChanged: canChange ? _set : null,
                ),
        ],
      ),
    );
  }
}
