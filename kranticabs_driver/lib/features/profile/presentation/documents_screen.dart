import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/loading_widget.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/application/signup_providers.dart';
import '../../auth/data/document_template.dart';
import '../application/profile_providers.dart';

class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  List<DocumentTemplate> _templates = [];
  bool _loading = true;
  String? _uploadingKey;

  // See _recoverLostCameraCapture: keeps track of which document a camera
  // capture was for, so it can still be filed correctly if Android tears
  // down this Activity for memory while the camera app is in front.
  static const _pendingCameraPickPrefsKey = 'pending_profile_doc_pick_key';

  @override
  void initState() {
    super.initState();
    _load();
    _recoverLostCameraCapture();
  }

  /// On some phones, Android kills this Activity in the background to free
  /// memory while the camera app is in the foreground, silently dropping the
  /// photo the driver just took and confirmed — the screen just reappears
  /// as if nothing happened. image_picker keeps the file on the native side
  /// for exactly this case; retrieveLostData() reads it back so the upload
  /// isn't lost.
  Future<void> _recoverLostCameraCapture() async {
    final response = await ImagePicker().retrieveLostData();
    if (response.isEmpty || response.file == null) return;

    final prefs = await SharedPreferences.getInstance();
    final pendingKey = prefs.getString(_pendingCameraPickPrefsKey);
    await prefs.remove(_pendingCameraPickPrefsKey);
    if (pendingKey == null) return;

    await _uploadFile(pendingKey, File(response.file!.path));
  }

  Future<void> _load() async {
    try {
      final templates = await ref.read(signupRepositoryProvider).getDocumentTemplates();
      if (!mounted) return;
      setState(() {
        _templates = templates;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  IconData _getDocIcon(String key, String name) {
    final lowerKey = key.toLowerCase();
    final lowerName = name.toLowerCase();
    if (lowerKey.contains('photo') || lowerName.contains('profile photo')) return Icons.account_circle_outlined;
    if (lowerKey.contains('aadhaar') || lowerName.contains('aadhaar')) return Icons.badge_outlined;
    if (lowerKey.contains('license') || lowerName.contains('license')) return Icons.credit_card_rounded;
    if (lowerKey.contains('rc') || lowerName.contains('rc')) return Icons.directions_car_rounded;
    if (lowerKey.contains('insurance') || lowerName.contains('insurance')) return Icons.shield_outlined;
    if (lowerKey.contains('puc') || lowerKey.contains('pollution') || lowerName.contains('pollution')) return Icons.assignment_outlined;
    if (lowerKey.contains('bank') || lowerName.contains('bank') || lowerName.contains('cheque')) return Icons.account_balance_outlined;
    if (lowerKey.contains('vehicle_photo') || lowerName.contains('vehicle photo')) return Icons.directions_car_filled_rounded;
    if (lowerKey.contains('selfie') || lowerName.contains('selfie')) return Icons.portrait_rounded;
    return Icons.description_outlined;
  }

  String _getDocSubtitle(String key, String name) {
    final lowerKey = key.toLowerCase();
    final lowerName = name.toLowerCase();
    if (lowerKey.contains('photo') || lowerName.contains('profile photo')) return 'Clear front face photo';
    if (lowerKey.contains('aadhaar') || lowerName.contains('aadhaar')) return 'Front & Back';
    if (lowerKey.contains('license') || lowerName.contains('license')) return 'Valid Driving License';
    if (lowerKey.contains('rc') || lowerName.contains('rc')) return 'Vehicle RC Book / Smart Card';
    if (lowerKey.contains('insurance') || lowerName.contains('insurance')) return 'Valid Insurance Document';
    if (lowerKey.contains('puc') || lowerKey.contains('pollution') || lowerName.contains('pollution')) return 'Valid PUC Certificate';
    if (lowerKey.contains('bank') || lowerName.contains('bank') || lowerName.contains('cheque')) return 'For payments';
    if (lowerKey.contains('vehicle_photo') || lowerName.contains('vehicle photo')) return 'Front, Back, Left, Right';
    if (lowerKey.contains('selfie') || lowerName.contains('selfie')) return 'Driver standing with vehicle';
    return 'Required document for driver verification';
  }

  void _showImageSourcePicker(String key) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF11191D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF2E2E2E),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Select Document Source',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: AppColors.primary),
                ),
                title: const Text(
                  'Take Photo (Camera)',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUpload(key, ImageSource.camera);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.photo_library_rounded, color: Color(0xFF38BDF8)),
                ),
                title: const Text(
                  'Choose from Gallery',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUpload(key, ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUpload(String key, ImageSource source) async {
    final picker = ImagePicker();
    final prefs = source == ImageSource.camera ? await SharedPreferences.getInstance() : null;
    if (prefs != null) await prefs.setString(_pendingCameraPickPrefsKey, key);

    final picked = await picker.pickImage(source: source, imageQuality: 80, maxWidth: 1280);

    if (prefs != null) await prefs.remove(_pendingCameraPickPrefsKey);
    if (picked == null) return;
    await _uploadFile(key, File(picked.path));
  }

  Future<void> _uploadFile(String key, File file) async {
    final bytes = await file.readAsBytes();
    final dataUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';

    if (!mounted) return;
    setState(() => _uploadingKey = key);
    try {
      await ref.read(profileRepositoryProvider).uploadDocument(key, {
        'previewUrl': dataUrl,
        'secureUrl': dataUrl,
        'url': dataUrl,
      });
      await ref.read(authProvider.notifier).refresh();
      if (mounted) SnackbarUtils.success('Document uploaded for review');
    } on ApiException catch (e) {
      if (mounted) SnackbarUtils.error(e.message);
    } finally {
      if (mounted) setState(() => _uploadingKey = null);
    }
  }

  List<DocumentTemplate> get _defaultTemplates => const [
        DocumentTemplate(
          key: 'profile_photo',
          name: 'Profile Photo',
          hasExpiryDate: false,
          hasIdentifyNumber: false,
          imageType: 'single',
        ),
        DocumentTemplate(
          key: 'aadhaar',
          name: 'Aadhaar Card',
          hasExpiryDate: false,
          hasIdentifyNumber: true,
          imageType: 'double',
        ),
        DocumentTemplate(
          key: 'license',
          name: 'Driving License',
          hasExpiryDate: true,
          hasIdentifyNumber: true,
          imageType: 'double',
        ),
        DocumentTemplate(
          key: 'rc',
          name: 'RC (Vehicle Registration)',
          hasExpiryDate: true,
          hasIdentifyNumber: true,
          imageType: 'double',
        ),
        DocumentTemplate(
          key: 'insurance',
          name: 'Vehicle Insurance',
          hasExpiryDate: true,
          hasIdentifyNumber: true,
          imageType: 'single',
        ),
        DocumentTemplate(
          key: 'puc',
          name: 'Pollution Certificate',
          hasExpiryDate: true,
          hasIdentifyNumber: false,
          imageType: 'single',
        ),
        DocumentTemplate(
          key: 'bank',
          name: 'Bank Passbook / Cancelled Cheque',
          hasExpiryDate: false,
          hasIdentifyNumber: true,
          imageType: 'single',
        ),
        DocumentTemplate(
          key: 'vehicle_photo',
          name: 'Vehicle Photo',
          hasExpiryDate: false,
          hasIdentifyNumber: false,
          imageType: 'single',
        ),
        DocumentTemplate(
          key: 'selfie_vehicle',
          name: 'Selfie with Vehicle',
          hasExpiryDate: false,
          hasIdentifyNumber: false,
          imageType: 'single',
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final documents = ref.watch(authProvider).driver?.documents ?? const {};
    final listTemplates = _templates.isNotEmpty ? _templates : _defaultTemplates;

    return Scaffold(
      backgroundColor: const Color(0xFF11191D),
      appBar: const CustomAppBar(title: 'Documents', showBack: true),
      body: _loading && _templates.isEmpty
          ? const LoadingWidget(message: 'Loading documents...')
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              children: [
                // Cyan Section Title (1:1 with reference image)
                const Text(
                  'DRIVER DOCUMENTS (REQUIRED)',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 16),

                // Payment UPI / QR — opens the dedicated screen. Shown to riders
                // at ride-end so they can pay the driver directly.
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF222222),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      onTap: () => context.push('/payment-upi'),
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.qr_code_2_rounded, color: Color(0xFF0284C7), size: 24),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Payment UPI / QR',
                                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                                  SizedBox(height: 3),
                                  Text('UPI ID shown to riders for payment',
                                      style: TextStyle(color: AppColors.darkTextSecondary, fontSize: 12)),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: AppColors.darkTextSecondary),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Document Templates List
                ...listTemplates.map((template) {
                  final doc = documents[template.key];
                  final status = doc is Map ? (doc['status'] ?? doc['verificationStatus'] ?? '').toString() : '';
                  final uploaded = doc is Map && (doc['uploaded'] == true || (doc['previewUrl'] ?? '').toString().isNotEmpty);
                  final busy = _uploadingKey == template.key;

                  final docIcon = _getDocIcon(template.key, template.name);
                  final docSubtitle = _getDocSubtitle(template.key, template.name);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF222222),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF2E2E2E)),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        onTap: busy ? null : () => _showImageSourcePicker(template.key),
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              // White Rounded Icon Box (1:1 with reference image)
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 4,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  docIcon,
                                  color: const Color(0xFF0284C7),
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),

                              // Document Name & Subtitle
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      template.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      docSubtitle,
                                      style: const TextStyle(
                                        color: Color(0xFF94A3B8),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Upload Action Button or Verification Badge
                              if (busy)
                                const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: AppColors.primary,
                                  ),
                                )
                              else if (uploaded)
                                _DocStatusChip(status: status)
                              else
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt_rounded,
                                    color: AppColors.primary,
                                    size: 18,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}

class _DocStatusChip extends StatelessWidget {
  final String status;

  const _DocStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    final approved = normalized == 'approved' || normalized == 'verified';
    final rejected = normalized == 'rejected';
    final color = approved ? AppColors.primary : (rejected ? const Color(0xFFEF4444) : const Color(0xFFFFB800));
    final label = approved ? 'Verified' : (rejected ? 'Rejected' : 'Pending');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            approved ? Icons.check_circle_rounded : (rejected ? Icons.cancel_rounded : Icons.pending_rounded),
            color: color,
            size: 13,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
