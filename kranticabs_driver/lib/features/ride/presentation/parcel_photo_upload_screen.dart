import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../application/ride_providers.dart';
import '../data/ride_model.dart';

class ParcelPhotoUploadScreen extends ConsumerStatefulWidget {
  final RideModel ride;
  final String stage; // 'pickup' or 'delivery'

  const ParcelPhotoUploadScreen({
    super.key,
    required this.ride,
    required this.stage,
  });

  @override
  ConsumerState<ParcelPhotoUploadScreen> createState() => _ParcelPhotoUploadScreenState();
}

class _ParcelPhotoUploadScreenState extends ConsumerState<ParcelPhotoUploadScreen> {
  File? _pickedFile;
  bool _uploading = false;

  bool get _isPickup => widget.stage == 'pickup';

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1280,
      );
      if (picked != null && mounted) {
        setState(() => _pickedFile = File(picked.path));
      }
    } catch (_) {
      if (mounted) {
        SnackbarUtils.error('Could not open camera or gallery');
      }
    }
  }

  void _showSourcePicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF222222),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF475569),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: AppColors.primary, size: 24),
              title: const Text(
                'Take Photo with Camera',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: AppColors.primary, size: 24),
              title: const Text(
                'Choose from Gallery',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                _pickImage(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadAndConfirm() async {
    if (_pickedFile == null || _uploading) return;

    setState(() => _uploading = true);
    try {
      final proofs = await ref.read(rideRepositoryProvider).uploadParcelProof(
            rideId: widget.ride.id,
            stage: widget.stage,
            photo: _pickedFile!,
          );
      ref.read(rideProvider.notifier).applyParcelProof(proofs);

      if (mounted) {
        SnackbarUtils.success(
          _isPickup ? 'Pickup photo uploaded successfully!' : 'Delivery photo uploaded successfully!',
        );
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        SnackbarUtils.error('Could not upload photo. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleText = _isPickup ? 'Photograph Parcel at Pickup' : 'Photograph Parcel at Delivery';
    final stepText = _isPickup ? 'STEP 1 OF 2 • PICKUP PROOF' : 'STEP 2 OF 2 • DELIVERY PROOF';
    final instructionText = _isPickup
        ? 'Take a clear photo of the parcel as you collect it from the sender. The 4-digit start PIN will be requested next.'
        : 'Take a clear photo of the parcel with the receiver to complete the delivery.';

    return Scaffold(
      backgroundColor: const Color(0xFF11191D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF11191D),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: Text(
          titleText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              // Step Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                ),
                child: Text(
                  stepText,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Instruction Banner Box
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF222222),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF2E2E2E)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: Color(0xFF11191D),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt_rounded, color: AppColors.primary, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        instructionText,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12.5,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // --- CENTER OF THE SCREEN: LARGE INTERACTIVE CAMERA UPLOAD BUTTON ---
              GestureDetector(
                onTap: _uploading ? null : _showSourcePicker,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer Pulsing Glow Container
                    Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _pickedFile != null
                            ? const Color(0xFF00C853).withValues(alpha: 0.1)
                            : AppColors.primary.withValues(alpha: 0.08),
                        border: Border.all(
                          color: _pickedFile != null
                              ? AppColors.primary
                              : const Color(0xFF2E2E2E),
                          width: 2,
                        ),
                      ),
                    ),

                    // Main Inner Upload Box
                    Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF222222),
                        border: Border.all(
                          color: _pickedFile != null ? AppColors.primary : const Color(0xFF334155),
                          width: 2.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _pickedFile != null
                                ? AppColors.primary.withValues(alpha: 0.35)
                                : Colors.black45,
                            blurRadius: 20,
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _pickedFile != null
                          ? Image.file(
                              _pickedFile!,
                              fit: BoxFit.cover,
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.camera_enhance_rounded,
                                    size: 42,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                    ),

                    // Badge checkmark if photo is picked
                    if (_pickedFile != null)
                      Positioned(
                        right: 14,
                        bottom: 14,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check_rounded, color: Color(0xFF11191D), size: 20),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Title below center icon
              Text(
                _pickedFile != null ? 'Parcel Photo Captured ✓' : 'TAP CENTER ICON TO UPLOAD',
                style: TextStyle(
                  color: _pickedFile != null ? AppColors.primary : Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 14.5,
                  letterSpacing: 0.8,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                _pickedFile != null
                    ? 'Tap icon to retake photo if needed'
                    : 'Tap the camera icon above to take or select parcel photo',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 16),

              // Quick Action Chips (Camera & Gallery)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _uploading ? null : () => _pickImage(ImageSource.camera),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF2E2E2E)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      backgroundColor: const Color(0xFF222222),
                    ),
                    icon: const Icon(Icons.camera_alt_rounded, size: 16, color: AppColors.primary),
                    label: const Text('Camera', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _uploading ? null : () => _pickImage(ImageSource.gallery),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF2E2E2E)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      backgroundColor: const Color(0xFF222222),
                    ),
                    icon: const Icon(Icons.photo_library_rounded, size: 16, color: AppColors.primary),
                    label: const Text('Gallery', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                ],
              ),

              const Spacer(),

              // --- BOTTOM CONFIRM & CONTINUE BUTTON ---
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: const Color(0xFF11191D),
                    elevation: 4,
                    shadowColor: AppColors.primary.withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  onPressed: (_pickedFile == null || _uploading) ? null : _uploadAndConfirm,
                  child: _uploading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(color: Color(0xFF11191D), strokeWidth: 2.5),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _isPickup ? 'CONFIRM & CONTINUE TO PIN' : 'CONFIRM & COMPLETE TRIP',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward_rounded, size: 20),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
