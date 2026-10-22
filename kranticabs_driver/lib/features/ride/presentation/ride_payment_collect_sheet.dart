import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../profile/application/profile_providers.dart';
import '../data/ride_model.dart';
import '../application/ride_providers.dart';
import 'rental_widgets.dart';
import 'toll_widgets.dart';

/// Shown to the driver when a trip ends. Displays the fare, the driver's own
/// UPI QR (to turn the phone toward the rider), and two completion actions.
///
/// Returns the collection tender — `'cash'` or `'upi'` — or `null` if the
/// driver dismissed it without collecting. Either tender settles the same way
/// (cash-like); the value only records how the fare was taken.
class RidePaymentCollectSheet {
  static Future<String?> show(BuildContext context, WidgetRef ref, RideModel ride) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      backgroundColor: AppColors.darkBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _SheetBody(ref: ref, ride: ride),
    );
  }
}

class _SheetBody extends StatefulWidget {
  final WidgetRef ref;
  final RideModel ride;
  const _SheetBody({required this.ref, required this.ride});

  @override
  State<_SheetBody> createState() => _SheetBodyState();
}

class _SheetBodyState extends State<_SheetBody> {
  bool _loading = true;
  String _upiId = '';
  String _qrImage = '';
  String _payeeName = '';
  String _verificationStatus = 'pending';
  late bool _paidOnline = widget.ride.paidOnline;
  // Rental overage is added server-side when the trip ends, so the ride handed
  // in may predate the final fare; refreshed from the server below.
  late RideModel _ride = widget.ride;
  Timer? _paymentPoll;

  @override
  void initState() {
    super.initState();
    _loadUpi();
    // The rider may pay online in their app while this is open: check every
    // few seconds, so the driver never takes cash for a fare already paid.
    if (widget.ride.rental != null) _refreshRide();
    if (!_paidOnline) {
      _paymentPoll = Timer.periodic(const Duration(seconds: 4), (_) => _checkPaidOnline());
      _checkPaidOnline();
    }
  }

  @override
  void dispose() {
    _paymentPoll?.cancel();
    super.dispose();
  }

  Future<void> _refreshRide() async {
    try {
      final latest = await widget.ref.read(rideRepositoryProvider).getRideById(widget.ride.id);
      if (mounted) setState(() => _ride = latest);
    } catch (_) {
      // Keep the fare already shown; the socket state may still correct it.
    }
  }

  Future<void> _checkPaidOnline() async {
    try {
      final latest = await widget.ref.read(rideRepositoryProvider).getRideById(widget.ride.id);
      if (!mounted || !latest.paidOnline) return;
      _paymentPoll?.cancel();
      setState(() => _paidOnline = true);
    } catch (_) {
      // A missed check is retried on the next tick.
    }
  }

  Future<void> _loadUpi() async {
    try {
      final data = await widget.ref.read(profileRepositoryProvider).getPaymentUpi();
      if (!mounted) return;
      setState(() {
        _upiId = (data['upiId'] ?? '').toString();
        _qrImage = (data['qrCodeImage'] ?? '').toString();
        _payeeName = (data['verifiedName'] ?? '').toString();
        _verificationStatus = (data['verificationStatus'] ?? 'pending').toString();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _canShowQr => _upiId.isNotEmpty && _verificationStatus.toLowerCase() == 'verified';

  String get _fareText {
    final f = _ride.fare;
    final s = f == f.roundToDouble() ? f.toInt().toString() : f.toStringAsFixed(2);
    return '₹$s';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(color: AppColors.darkBorder, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 18),
          const Text('Collect Payment',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Amount to collect',
              style: TextStyle(color: AppColors.darkTextSecondary, fontSize: 13)),
          const SizedBox(height: 2),
          Text(_fareText,
              style: const TextStyle(color: AppColors.primary, fontSize: 34, fontWeight: FontWeight.w900)),
          if (_ride.rental != null && _ride.rental!.isSettled) ...[
            const SizedBox(height: 10),
            RentalBill(rental: _ride.rental!),
          ],
          if (widget.ride.tollCharges.hasTolls) ...[
            const SizedBox(height: 8),
            TollChargesNote(tolls: widget.ride.tollCharges, dark: true),
          ],
          const SizedBox(height: 18),
          if (_paidOnline) ...[
            _paidOnlineBanner(),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: _actionButton(
                label: 'Complete Trip',
                icon: Icons.check_circle_rounded,
                filled: true,
                // The server records it as paid online whatever is sent.
                onTap: () => Navigator.pop(context, 'upi'),
              ),
            ),
          ] else ...[
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            else
              _qrArea(),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: _actionButton(
                    label: 'Cash Collected',
                    icon: Icons.payments_rounded,
                    filled: true,
                    onTap: () => Navigator.pop(context, 'cash'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _actionButton(
                    label: 'Online (UPI) Received',
                    icon: Icons.check_circle_rounded,
                    filled: false,
                    // Only allow confirming online when a verified QR exists to pay into.
                    onTap: _canShowQr ? () => Navigator.pop(context, 'upi') : null,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel', style: TextStyle(color: AppColors.darkTextSecondary)),
          ),
        ],
      ),
    );
  }

  Widget _paidOnlineBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded, color: AppColors.success, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Rider paid $_fareText online.\nIt is in your KRANTI CABS wallet - do not collect cash.',
              style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.4, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _qrArea() {
    if (!_canShowQr) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: AppColors.warning),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _upiId.isEmpty
                    ? 'Add your UPI in Documents → Payment UPI/QR to accept online payments. You can still collect cash.'
                    : 'Your UPI is pending admin verification. You can still collect cash.',
                style: const TextStyle(color: AppColors.warning, fontSize: 12.5, height: 1.4),
              ),
            ),
          ],
        ),
      );
    }
    // The driver's own QR from their UPI app (the one they uploaded) is shown
    // as it is: PhonePe and Google Pay accept scanning it like any shop QR.
    // Without one, a plain QR of just the UPI ID - the same static kind. A QR
    // carrying the amount and a note to a personal UPI ID is what the apps
    // decline "for security reasons", so the rider types the amount instead.
    final plainPayload = Uri(
      scheme: 'upi',
      host: 'pay',
      queryParameters: {
        'pa': _upiId,
        if (_payeeName.isNotEmpty) 'pn': _payeeName,
      },
    ).toString();
    final qrUrl = _qrImage.isEmpty
        ? ''
        : (_qrImage.startsWith('http') ? _qrImage : '${AppConstants.mediaBaseUrl}$_qrImage');
    final plainQr = QrImageView(data: plainPayload, size: 200, version: QrVersions.auto);

    return Column(
      children: [
        const Text('Show this QR to the rider',
            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('They scan it and enter $_fareText',
            style: const TextStyle(color: AppColors.darkTextSecondary, fontSize: 12)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
          child: qrUrl.isEmpty
              ? plainQr
              : ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    qrUrl,
                    height: 280,
                    fit: BoxFit.contain,
                    // A QR that will not load must not leave the driver with
                    // nothing to show.
                    errorBuilder: (_, _, _) => plainQr,
                  ),
                ),
        ),
        const SizedBox(height: 8),
        Text(_upiId, style: const TextStyle(color: AppColors.darkTextSecondary, fontSize: 12)),
      ],
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required bool filled,
    required VoidCallback? onTap,
  }) {
    final disabled = onTap == null;
    return SizedBox(
      height: 54,
      child: filled
          ? ElevatedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 20),
              label: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: const Color(0xFF042F2A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            )
          : OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 20, color: disabled ? AppColors.offline : AppColors.primary),
              label: Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: disabled ? AppColors.offline : Colors.white)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: disabled ? AppColors.darkBorder : AppColors.primary, width: 1.4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
    );
  }
}
