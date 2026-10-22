import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/image_utils.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../auth/application/auth_providers.dart';
import '../application/profile_providers.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  File? _photo;
  String? _photoDataUrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final driver = ref.read(authProvider).driver;
    _nameController = TextEditingController(text: driver?.name ?? '');
    _emailController = TextEditingController(text: driver?.email ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 800);
    if (picked == null) return;
    final file = File(picked.path);
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _photo = file;
      _photoDataUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
    });
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      SnackbarUtils.error('Name cannot be empty');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(profileRepositoryProvider).updateProfile(
            name: _nameController.text.trim(),
            email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
            profileImage: _photoDataUrl,
          );
      await ref.read(authProvider.notifier).refresh();
      if (mounted) SnackbarUtils.success('Profile updated');
    } on ApiException catch (e) {
      if (mounted) SnackbarUtils.error(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final driver = ref.watch(authProvider).driver;

    return Scaffold(
      appBar: const CustomAppBar(title: 'Edit Profile'),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: GestureDetector(
              onTap: _pickPhoto,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                    backgroundImage: _photo != null
                        ? FileImage(_photo!)
                        : buildSafeImageProvider(driver?.profileImage),
                    child: _photo == null && buildSafeImageProvider(driver?.profileImage) == null
                        ? const Icon(Icons.person, color: AppColors.primary, size: 48)
                        : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                      child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          AppTextField(controller: _nameController, label: 'Full name', hint: 'Your name'),
          const SizedBox(height: 16),
          AppTextField(
            controller: _emailController,
            label: 'Email (optional)',
            hint: 'you@example.com',
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: TextEditingController(text: driver?.phone ?? ''),
            label: 'Phone number',
            enabled: false,
          ),
          const SizedBox(height: 28),
          PrimaryButton(label: 'Save Changes', onPressed: _save, loading: _saving),
        ],
      ),
    );
  }
}
