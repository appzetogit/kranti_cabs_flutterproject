import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../auth/application/auth_providers.dart';
import '../application/profile_providers.dart';

/// Lets the driver save their OWN static payment UPI handle (and optionally a
/// QR image). Riders are shown a QR generated from this UPI at ride-end so they
/// can pay directly. A changed handle/QR goes back to "pending" until admin
/// re-verifies it.
class PaymentUpiScreen extends ConsumerStatefulWidget {
  const PaymentUpiScreen({super.key});

  @override
  ConsumerState<PaymentUpiScreen> createState() => _PaymentUpiScreenState();
}

class _PaymentUpiScreenState extends ConsumerState<PaymentUpiScreen> {
  final _upiController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String _verificationStatus = 'pending';
  String _savedUpiId = '';
  String _savedQrUrl = ''; // existing stored image (http URL)
  String? _newQrDataUrl; // freshly picked image, not yet saved

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _upiController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await ref.read(profileRepositoryProvider).getPaymentUpi();
      if (!mounted) return;
      setState(() {
        _savedUpiId = (data['upiId'] ?? '').toString();
        _upiController.text = _savedUpiId;
        _savedQrUrl = (data['qrCodeImage'] ?? '').toString();
        _verificationStatus = (data['verificationStatus'] ?? 'pending').toString();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _resolveImageUrl(String url) {
    if (url.isEmpty) return url;
    if (url.startsWith('http') || url.startsWith('data:')) return url;
    return '${AppConstants.mediaBaseUrl}$url';
  }

  Future<void> _pickQr(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 85, maxWidth: 1080);
    if (picked == null) return;
    final bytes = await File(picked.path).readAsBytes();
    if (!mounted) return;
    setState(() => _newQrDataUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}');
  }

  void _showQrSourcePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: AppColors.primary),
              title: const Text('Take Photo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                _pickQr(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: AppColors.primary),
              title: const Text('Choose from Gallery', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                _pickQr(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final upiId = _upiController.text.trim();
    if (upiId.isEmpty) {
      SnackbarUtils.error('Please enter your UPI ID');
      return;
    }
    // Mirror the backend check (name@bank) so the driver gets instant feedback.
    final valid = RegExp(r'^[a-zA-Z0-9.\-_]{2,256}@[a-zA-Z]{2,64}$').hasMatch(upiId);
    if (!valid) {
      SnackbarUtils.error('Enter a valid UPI ID (e.g. name@bank)');
      return;
    }

    setState(() => _saving = true);
    try {
      final data = await ref.read(profileRepositoryProvider).savePaymentUpi(
            upiId: upiId,
            qrImage: _newQrDataUrl,
          );
      await ref.read(authProvider.notifier).refresh();
      if (!mounted) return;
      setState(() {
        _savedUpiId = (data['upiId'] ?? upiId).toString();
        _savedQrUrl = (data['qrCodeImage'] ?? _savedQrUrl).toString();
        _verificationStatus = (data['verificationStatus'] ?? 'pending').toString();
        _newQrDataUrl = null;
        _saving = false;
      });
      SnackbarUtils.success('Payment UPI saved — sent for verification');
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        SnackbarUtils.error(e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        SnackbarUtils.error('Could not save. Please try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final upiPreview = _upiController.text.trim();
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: const CustomAppBar(title: 'Payment UPI / QR'),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              children: [
                const Text(
                  'PAYMENT COLLECTION',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Add the UPI ID where riders pay you. We show your QR to the rider when a trip ends so they can pay directly.',
                  style: TextStyle(color: AppColors.darkTextSecondary, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 16),
                _statusChip(),
                const SizedBox(height: 16),
                _label('Your UPI ID'),
                const SizedBox(height: 8),
                TextField(
                  controller: _upiController,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
                  decoration: _inputDecoration('e.g. 9876543210@okhdfc'),
                ),
                const SizedBox(height: 20),
                _label('Live preview (what riders scan)'),
                const SizedBox(height: 10),
                Center(child: _qrPreview(upiPreview)),
                const SizedBox(height: 20),
                _label('Or upload your own QR image (optional)'),
                const SizedBox(height: 10),
                _qrUploadBox(),
                const SizedBox(height: 28),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: const Color(0xFF042F2A),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF042F2A)),
                          )
                        : const Text('Save', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
      );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.offline),
        filled: true,
        fillColor: AppColors.darkSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
      );

  Widget _statusChip() {
    final s = _verificationStatus.toLowerCase();
    late Color color;
    late String label;
    late IconData icon;
    if (s == 'verified') {
      color = AppColors.success;
      label = 'Verified — visible to riders';
      icon = Icons.verified_rounded;
    } else if (s == 'rejected') {
      color = AppColors.error;
      label = 'Rejected — please re-check your UPI';
      icon = Icons.error_rounded;
    } else {
      color = AppColors.warning;
      label = 'Pending admin verification';
      icon = Icons.hourglass_bottom_rounded;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13))),
        ],
      ),
    );
  }

  Widget _qrPreview(String upi) {
    if (upi.isEmpty) {
      return Container(
        width: 180,
        height: 180,
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: const Center(
          child: Text('Enter UPI ID\nto preview', textAlign: TextAlign.center, style: TextStyle(color: AppColors.offline)),
        ),
      );
    }
    final payload = 'upi://pay?pa=$upi&cu=INR';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: QrImageView(data: payload, size: 180, version: QrVersions.auto),
    );
  }

  Widget _qrUploadBox() {
    final hasNew = _newQrDataUrl != null;
    final hasExisting = _savedQrUrl.isNotEmpty;
    Widget child;
    if (hasNew) {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(base64Decode(_newQrDataUrl!.split(',').last), height: 120, fit: BoxFit.cover),
      );
    } else if (hasExisting) {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(_resolveImageUrl(_savedQrUrl), height: 120, fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image, color: AppColors.offline)),
      );
    } else {
      child = const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.qr_code_2_rounded, color: AppColors.primary, size: 36),
          SizedBox(height: 8),
          Text('Tap to upload QR image', style: TextStyle(color: AppColors.darkTextSecondary)),
        ],
      );
    }
    return GestureDetector(
      onTap: _showQrSourcePicker,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: Center(child: child),
      ),
    );
  }
}
