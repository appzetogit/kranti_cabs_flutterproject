import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/services/razorpay_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../auth/application/auth_providers.dart';
import '../application/ride_providers.dart';
import '../application/ride_tracking_controller.dart';
import '../data/models/ride_model.dart';

/// "Pay your fare" for a cash ride - from the trip card, and opened by itself
/// as the trip nears the drop.
///
/// Two ways, both on one screen:
///   - Pay online: one tap through Razorpay (UPI apps, card, wallet). The
///     money reaches Kranti Cabs and is credited to the driver's Kranti Cabs wallet.
///   - Pay the driver directly: the driver's own UPI QR (the one they
///     uploaded, or one made from their verified UPI ID) and UPI ID. This
///     money goes straight to the driver's bank. The rider saves the QR and
///     scans it from the gallery in their UPI app, scans the QR on the
///     driver's phone, or pays to the UPI ID.
///
/// There is deliberately no "open my UPI app with this payment" button. A
/// `upi://pay` link to a personal UPI ID, launched from another app, is
/// declined by PhonePe and Google Pay "for security reasons" - scanning a QR
/// or paying to a UPI ID is what they allow. For the same reason the QR holds
/// no amount: they also decline amount-filled QRs to a personal UPI ID.
class RideUpiPaySheet {
  /// What the driver's QR encodes: their UPI ID and name, and deliberately no
  /// amount (PhonePe and Google Pay decline amount-filled personal QRs).
  static String driverUpiPayload(RideDriverPayment payment) => Uri(
        scheme: 'upi',
        host: 'pay',
        queryParameters: {
          'pa': payment.upiId,
          if (payment.payeeName.isNotEmpty) 'pn': payment.payeeName,
        },
      ).toString();

  static Future<void> show(BuildContext context, RideModel ride) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _Body(ride: ride),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  final RideModel ride;
  const _Body({required this.ride});

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  bool _busy = false;
  bool _savingQr = false;

  /// Wraps the QR so it can be saved or shared as an image.
  final GlobalKey _qrKey = GlobalKey();

  /// The amount the server's order actually charges, once one is created.
  /// Shown from then on so the label and the success message match what the
  /// rider paid, not the possibly stale fare the sheet opened with.
  double? _orderAmount;

  RideModel get ride => widget.ride;

  String get _fareDigits {
    final f = _orderAmount ?? ride.fare;
    return f == f.roundToDouble() ? f.toInt().toString() : f.toStringAsFixed(2);
  }

  void _copy(String value, String what) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$what copied')));
  }

  /// The QR as PNG bytes, read off the screen at a size a scanner reads well.
  Future<Uint8List?> _qrPng() async {
    final boundary = _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  String get _qrFileName =>
      'KRANTI_pay_driver_${(ride.driverPayment?.upiId ?? 'upi').replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}';

  /// Saves the driver's QR to the gallery, so the rider can open their UPI
  /// app, tap Scan and pick it from the gallery.
  Future<void> _saveQr() async {
    if (_savingQr) return;
    setState(() => _savingQr = true);
    try {
      final bytes = await _qrPng();
      if (bytes == null) throw StateError('QR not ready');
      if (!await Gal.hasAccess(toAlbum: false)) await Gal.requestAccess(toAlbum: false);
      await Gal.putImageBytes(bytes, name: _qrFileName);
      if (mounted) {
        SnackbarUtils.success(context, 'QR saved. In your UPI app tap Scan, then pick it from the gallery.');
      }
    } catch (_) {
      // No gallery access (or no gallery): share it instead, which offers
      // "save" on most phones and sends it straight to a UPI app on others.
      if (mounted) await _shareQr();
    } finally {
      if (mounted) setState(() => _savingQr = false);
    }
  }

  Future<void> _shareQr() async {
    try {
      final bytes = await _qrPng();
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$_qrFileName.png');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: 'Pay ₹$_fareDigits to ${ride.driverPayment?.upiId ?? 'the driver'} (Kranti Cabs ride)',
      );
    } catch (_) {
      if (mounted) SnackbarUtils.error(context, 'Could not share the QR. Copy the UPI ID instead.');
    }
  }

  Future<void> _payOnline() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final order = await ref.read(rideRepositoryProvider).createFareOrder(ride.rideId);
      final user = ref.read(authControllerProvider).user;

      final keyId = (order['keyId'] ?? order['key_id'] ?? '').toString();
      final orderId = (order['orderId'] ?? order['order_id'] ?? '').toString();
      // What the server charges, which can differ from the card if the fare
      // was updated a moment ago.
      final amount = double.tryParse('${order['fare'] ?? ''}') ?? ride.fare;
      if (keyId.isEmpty || orderId.isEmpty) {
        throw ApiException('Could not start the payment. Please try again.');
      }
      if (mounted) setState(() => _orderAmount = amount);

      ref.read(razorpayServiceProvider).open(
            request: RazorpayCheckoutRequest(
              keyId: keyId,
              orderId: orderId,
              // Rupees - the service converts to paise.
              amount: amount,
              name: 'Kranti Cabs',
              description: 'Ride fare',
              contact: user?.phone,
              email: user?.email,
            ),
            onSuccess: (PaymentSuccessResponse response) async {
              try {
                // Paid only once the server has verified it.
                await ref.read(rideRepositoryProvider).verifyFarePayment(ride.rideId, {
                  'razorpay_payment_id': response.paymentId,
                  'razorpay_order_id': response.orderId,
                  'razorpay_signature': response.signature,
                });
                await ref.read(rideTrackingControllerProvider(ride.rideId).notifier).refresh();
                if (!mounted) return;
                SnackbarUtils.success(context, 'Paid ₹$_fareDigits. Your driver has been told.');
                Navigator.of(context).pop();
              } on ApiException catch (e) {
                if (mounted) {
                  SnackbarUtils.error(context, 'Paid but not confirmed yet: ${e.message}');
                  setState(() => _busy = false);
                }
              } catch (_) {
                // Anything else (a dropped connection, a parse error) would
                // otherwise leave the spinner running with no way out.
                if (mounted) {
                  SnackbarUtils.error(context, 'Paid but not confirmed yet. Please check again shortly.');
                  setState(() => _busy = false);
                }
              }
            },
            onError: (PaymentFailureResponse response) {
              if (!mounted) return;
              SnackbarUtils.error(context, response.message ?? 'Payment failed or cancelled');
              setState(() => _busy = false);
            },
          );
    } on ApiException catch (e) {
      if (mounted) {
        SnackbarUtils.error(context, e.message);
        setState(() => _busy = false);
      }
    } catch (_) {
      if (mounted) {
        SnackbarUtils.error(context, 'Could not start the payment. Please try again.');
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pay = ride.driverPayment;
    final hasUpi = pay != null && pay.hasUpi;
    final payeeName = (pay?.payeeName.isNotEmpty ?? false) ? pay!.payeeName : 'your driver';

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            const Text('Pay your fare',
                style: TextStyle(color: Color(0xFF0F172A), fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('to $payeeName',
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 13)),
            const SizedBox(height: 10),
            Text('₹$_fareDigits',
                style: const TextStyle(color: AppColors.primary, fontSize: 32, fontWeight: FontWeight.w900)),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _payOnline,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.lock_rounded, size: 18),
                label: Text('Pay ₹$_fareDigits online',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'One tap with any UPI app, card or wallet. Credited to your driver\'s Kranti Cabs wallet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
            if (hasUpi) ...[
              const SizedBox(height: 18),
              const Row(
                children: [
                  Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text('or pay the driver directly',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                  ),
                  Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Goes straight to your driver\'s bank account',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
              const SizedBox(height: 12),
              _DriverQr(repaintKey: _qrKey, payment: pay),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _savingQr ? null : _saveQr,
                      icon: _savingQr
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.download_rounded, size: 18),
                      label: const Text('Save QR', style: TextStyle(fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        minimumSize: const Size(0, 46),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _shareQr,
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: const Text('Share', style: TextStyle(fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF334155),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        minimumSize: const Size(0, 46),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _CopyRow(label: 'UPI ID', value: pay.upiId, onCopy: () => _copy(pay.upiId, 'UPI ID')),
              const SizedBox(height: 10),
              _CopyRow(label: 'Amount to enter', value: '₹$_fareDigits', onCopy: () => _copy(_fareDigits, 'Amount')),
              const SizedBox(height: 12),
              _HowToPay(fare: _fareDigits),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('I paid cash', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onCopy;

  const _CopyRow({required this.label, required this.value, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                const SizedBox(height: 2),
                SelectableText(value,
                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 16, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onCopy,
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy', style: TextStyle(fontWeight: FontWeight.w700)),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          ),
        ],
      ),
    );
  }
}

/// The driver's own UPI QR: the image they uploaded, or one made from their
/// verified UPI ID when they have not uploaded one (or it will not load). No
/// amount in it - see [RideUpiPaySheet].
class _DriverQr extends StatelessWidget {
  final GlobalKey repaintKey;
  final RideDriverPayment payment;

  const _DriverQr({required this.repaintKey, required this.payment});

  @override
  Widget build(BuildContext context) {
    final generated = QrImageView(
      data: RideUpiPaySheet.driverUpiPayload(payment),
      size: 200,
      backgroundColor: Colors.white,
      version: QrVersions.auto,
    );
    final uploaded = payment.qrCodeImage.trim();
    final imageUrl = uploaded.isEmpty
        ? ''
        : (uploaded.startsWith('http') ? uploaded : '${AppConstants.mediaBaseUrl}$uploaded');

    return RepaintBoundary(
      key: repaintKey,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            imageUrl.isEmpty
                ? generated
                : Image.network(
                    imageUrl,
                    height: 240,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => generated,
                  ),
            const SizedBox(height: 6),
            Text(
              payment.payeeName.isNotEmpty ? '${payment.payeeName} · ${payment.upiId}' : payment.upiId,
              style: const TextStyle(color: Color(0xFF334155), fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// The three ways to pay the driver directly, in the rider's terms.
class _HowToPay extends StatelessWidget {
  final String fare;
  const _HowToPay({required this.fare});

  @override
  Widget build(BuildContext context) {
    Widget step(String number, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: Color(0xFFF1F5F9), shape: BoxShape.circle),
                child: Text(number, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF334155))),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text, style: const TextStyle(color: Color(0xFF475569), fontSize: 12.5, height: 1.35)),
              ),
            ],
          ),
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('How to pay your driver',
              style: TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          step('1', 'Tap Save QR, open PhonePe / Google Pay / Paytm, tap Scan and pick the QR from your gallery.'),
          step('2', 'Or scan the same QR on your driver\'s phone.'),
          step('3', 'Or choose "Pay to UPI ID" in your UPI app and paste the UPI ID.'),
          Text('Enter ₹$fare and pay. Then let your driver know.',
              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 12.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
