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
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/loading_widget.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/registration_step_progress_bar.dart';
import '../data/document_template.dart';
import '../application/signup_providers.dart';

IconData _iconForDocument(String name, String key) {
  final lower = (name + key).toLowerCase();
  if (lower.contains('profile') || lower.contains('photo')) {
    return Icons.account_circle_outlined;
  } else if (lower.contains('aadhaar') || lower.contains('id') || lower.contains('pan')) {
    return Icons.badge_outlined;
  } else if (lower.contains('license') || lower.contains('dl')) {
    return Icons.credit_card_outlined;
  } else if (lower.contains('rc') || lower.contains('registration') || lower.contains('vehicle')) {
    return Icons.directions_car_outlined;
  } else if (lower.contains('insurance')) {
    return Icons.security_outlined;
  } else if (lower.contains('pollution') || lower.contains('puc')) {
    return Icons.verified_user_outlined;
  } else if (lower.contains('bank') || lower.contains('cheque') || lower.contains('passbook')) {
    return Icons.account_balance_outlined;
  }
  return Icons.description_outlined;
}

class DocumentsUploadScreen extends ConsumerStatefulWidget {
  const DocumentsUploadScreen({super.key});

  @override
  ConsumerState<DocumentsUploadScreen> createState() => _DocumentsUploadScreenState();
}

class _DocumentsUploadScreenState extends ConsumerState<DocumentsUploadScreen> {
  List<DocumentTemplate> _templates = [];
  bool _loading = true;
  bool _submitting = false;
  int? _selectedIndex;
  final Map<String, File> _files = {};
  final Map<String, TextEditingController> _identifyControllers = {};

  // Keyed with the document being captured so a photo the camera hands back
  // after Android has torn down and recreated this Activity for memory can
  // still be filed into the right slot — see _recoverLostCameraCapture.
  static const _pendingCameraPickPrefsKey = 'pending_doc_pick_key';

  @override
  void initState() {
    super.initState();
    _loadTemplates();
    _restoreSavedPhotos();
    _recoverLostCameraCapture();
  }

  /// Photos taken before the app was killed, which the restored signup still
  /// has on disk - shown again so the driver does not retake them.
  void _restoreSavedPhotos() {
    final saved = ref.read(signupProvider).documentPaths;
    for (final entry in saved.entries) {
      final file = File(entry.value);
      if (file.existsSync()) _files[entry.key] = file;
    }
  }

  /// On some phones, Android kills this Activity in the background to free
  /// memory while the camera app is in the foreground. Without this, the
  /// photo the driver just took (and confirmed) is silently dropped and the
  /// screen simply reappears in whatever state survived — which looks like
  /// the app "restarted" right after upload. image_picker keeps the file on
  /// the native side for exactly this case; retrieveLostData() is what
  /// reads it back.
  Future<void> _recoverLostCameraCapture() async {
    final response = await ImagePicker().retrieveLostData();
    if (response.isEmpty || response.file == null) return;

    final prefs = await SharedPreferences.getInstance();
    final pendingKey = prefs.getString(_pendingCameraPickPrefsKey);
    await prefs.remove(_pendingCameraPickPrefsKey);
    if (pendingKey == null) return;

    await _applyPickedFile(pendingKey, File(response.file!.path));
  }

  Future<void> _loadTemplates() async {
    try {
      final templates = await ref.read(signupProvider.notifier).getDocumentTemplates();
      if (!mounted) return;
      setState(() {
        _templates = templates;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showImageSourceDialog(String key) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF222222),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                'Select Photo Source',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: Color(0xFF11191D),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: AppColors.primary),
                ),
                title: const Text('Take Photo (Camera)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(key, ImageSource.camera);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: Color(0xFF11191D),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.photo_library_rounded, color: AppColors.primary),
                ),
                title: const Text('Choose from Gallery', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(key, ImageSource.gallery);
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickImage(String key, ImageSource source) async {
    final picker = ImagePicker();
    final prefs = source == ImageSource.camera ? await SharedPreferences.getInstance() : null;
    if (prefs != null) await prefs.setString(_pendingCameraPickPrefsKey, key);

    final picked = await picker.pickImage(source: source, imageQuality: 80, maxWidth: 1280);

    if (prefs != null) await prefs.remove(_pendingCameraPickPrefsKey);
    if (picked == null) return;
    await _applyPickedFile(key, File(picked.path));
  }

  Future<void> _applyPickedFile(String key, File file) async {
    final bytes = await file.readAsBytes();
    final dataUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
    ref.read(signupProvider.notifier).setDocument(key, dataUrl, path: file.path);
    if (!mounted) return;
    setState(() {
      _files[key] = file;
      final recoveredIndex = _templates.indexWhere((t) => t.key == key);
      if (recoveredIndex != -1) _selectedIndex = recoveredIndex;
    });
  }

  Future<void> _submitAll() async {
    for (final template in _templates) {
      if (template.isRequired && !_files.containsKey(template.key)) {
        SnackbarUtils.error('Please upload ${template.name}');
        setState(() => _selectedIndex = _templates.indexOf(template));
        return;
      }
    }

    setState(() => _submitting = true);
    try {
      await ref.read(signupProvider.notifier).saveDocuments();
      await ref.read(signupProvider.notifier).complete();
      if (!mounted) return;
      context.go('/verification-pending');
    } on ApiException catch (e) {
      SnackbarUtils.error(e.message);
    } catch (_) {
      SnackbarUtils.error('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    for (final c in _identifyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF11191D),
        body: LoadingWidget(message: 'Loading document requirements...'),
      );
    }

    // Detail Capture View for selected document (Image 1)
    if (_selectedIndex != null) {
      final template = _templates[_selectedIndex!];
      final file = _files[template.key];
      final identifyController = _identifyControllers.putIfAbsent(template.key, () => TextEditingController());

      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) setState(() => _selectedIndex = null);
        },
        child: Scaffold(
          backgroundColor: const Color(0xFF11191D),
          appBar: CustomAppBar(
            title: template.name,
            showBack: true,
            onBack: () => setState(() => _selectedIndex = null),
          ),
          bottomNavigationBar: const SafeArea(
            child: RegistrationProgressBar(currentStep: 3),
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Text(
                      'Step 3 of 3',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Image Capture Container Box (1:1 with Image 1 reference)
                  GestureDetector(
                    onTap: () => _showImageSourceDialog(template.key),
                    child: Container(
                      height: 200,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFF222222),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: file != null ? AppColors.primary : const Color(0xFFF5B400).withValues(alpha: 0.5),
                          width: 1.5,
                        ),
                      ),
                      child: file != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: Stack(
                                children: [
                                  Image.file(file, fit: BoxFit.cover, width: double.infinity, height: double.infinity),
                                  Positioned(
                                    right: 12,
                                    bottom: 12,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.black,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: const Row(
                                        children: [
                                          Icon(Icons.refresh_rounded, color: Colors.white, size: 14),
                                          SizedBox(width: 4),
                                          Text('Change', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(Icons.camera_alt_outlined, size: 44, color: AppColors.primary),
                                SizedBox(height: 10),
                                Text(
                                  'Tap to capture',
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Identify Document Number Field (e.g. PAN Card Number)
                  if (template.hasIdentifyNumber) ...[
                    AppTextField(
                      controller: identifyController,
                      label: '${template.name} Number',
                      hint: 'Enter document number',
                    ),
                    const SizedBox(height: 24),
                  ],

                  const Spacer(),

                  // Save / Next Button
                  PrimaryButton(
                    label: _selectedIndex! < _templates.length - 1 ? 'Next' : 'Done',
                    onPressed: () {
                      if (!_files.containsKey(template.key)) {
                        SnackbarUtils.error('Please upload ${template.name}');
                        return;
                      }
                      if (_selectedIndex! < _templates.length - 1) {
                        setState(() => _selectedIndex = _selectedIndex! + 1);
                      } else {
                        setState(() => _selectedIndex = null);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Overview List Screen (1:1 with Image 2 reference)
    return Scaffold(
      backgroundColor: const Color(0xFF11191D),
      appBar: const CustomAppBar(title: 'Upload Documents', showBack: true),
      bottomNavigationBar: const SafeArea(
        child: RegistrationProgressBar(currentStep: 3),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Step 3 of 3',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Document List
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                itemCount: _templates.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final template = _templates[index];
                  final isUploaded = _files.containsKey(template.key);

                  return Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF222222),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isUploaded ? AppColors.primary.withValues(alpha: 0.5) : const Color(0xFF2E2E2E),
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      onTap: () => setState(() => _selectedIndex = index),
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF11191D),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _iconForDocument(template.name, template.key),
                          color: isUploaded ? AppColors.primary : const Color(0xFF94A3B8),
                          size: 22,
                        ),
                      ),
                      title: Text(
                        template.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      subtitle: Text(
                        isUploaded ? 'Document Uploaded' : (template.isRequired ? 'Required' : 'Optional'),
                        style: TextStyle(
                          fontSize: 12,
                          color: isUploaded ? AppColors.primary : const Color(0xFF94A3B8),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      trailing: isUploaded
                          ? Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Color(0xFF11191D),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check_circle_rounded,
                                color: AppColors.primary,
                                size: 22,
                              ),
                            )
                          : Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF11191D),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFF2E2E2E)),
                              ),
                              child: const Icon(
                                Icons.camera_alt_outlined,
                                color: AppColors.primary,
                                size: 18,
                              ),
                            ),
                    ),
                  );
                },
              ),
            ),

            // Submit / Continue Button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: PrimaryButton(
                label: 'Continue',
                onPressed: _submitAll,
                loading: _submitting,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
