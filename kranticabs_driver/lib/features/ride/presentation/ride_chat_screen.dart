import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../auth/application/auth_providers.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../application/ride_providers.dart';
import '../data/ride_model.dart';

class RideChatScreen extends ConsumerStatefulWidget {
  const RideChatScreen({super.key});

  @override
  ConsumerState<RideChatScreen> createState() => _RideChatScreenState();
}

class _RideChatScreenState extends ConsumerState<RideChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sendingPhoto = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Preset quick-message keys (localized). Tapping one sends it immediately in
  // the driver's selected language.
  static const List<String> _quickKeys = [
    'quick_msg.coming',
    'quick_msg.on_the_way',
    'quick_msg.arrived',
    'quick_msg.two_min',
    'quick_msg.waiting',
    'quick_msg.call_me',
    'quick_msg.dont_cancel',
    'quick_msg.thank_you',
  ];

  void _send() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    ref.read(rideProvider.notifier).sendMessage(text);
    _controller.clear();
  }

  void _sendQuick(String key) {
    ref.read(rideProvider.notifier).sendMessage(key.tr());
  }

  /// Driver clicks a photo of where they are standing and shares it with the
  /// rider so the rider can see exactly where the driver is.
  Future<void> _sendPhoto() async {
    if (_sendingPhoto) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
      maxWidth: 1280,
    );
    if (picked == null) return;
    setState(() => _sendingPhoto = true);
    try {
      final url = await ref.read(rideRepositoryProvider).uploadChatImage(File(picked.path));
      if (url.isEmpty) throw Exception('upload failed');
      ref.read(rideProvider.notifier).sendImageMessage(url, text: 'quick_msg.my_location_photo'.tr());
    } catch (_) {
      if (mounted) SnackbarUtils.error('chat.photo_failed'.tr());
    } finally {
      if (mounted) setState(() => _sendingPhoto = false);
    }
  }

  Widget _quickChips() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _quickKeys.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final key = _quickKeys[index];
          return ActionChip(
            label: Text(key.tr(), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            backgroundColor: AppColors.lightSurface,
            side: const BorderSide(color: AppColors.lightBorder),
            labelStyle: const TextStyle(color: AppColors.lightTextPrimary),
            onPressed: () => _sendQuick(key),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ride = ref.watch(rideProvider).activeRide;
    final driverId = ref.watch(authProvider).driver?.id;
    final messages = ride?.messages ?? const <RideMessage>[];

    return Scaffold(
      appBar: CustomAppBar(title: ride?.riderName ?? 'chat.title'.tr()),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? Center(child: Text('chat.empty'.tr(), style: const TextStyle(color: AppColors.lightTextSecondary)))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final isMine = message.senderRole == 'driver' && message.senderId == driverId;
                      return Align(
                        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                          decoration: BoxDecoration(
                            color: isMine ? AppColors.primary : AppColors.lightSurface,
                            borderRadius: BorderRadius.circular(16),
                            border: isMine ? null : Border.all(color: AppColors.lightBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (message.hasImage) ...[
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.network(
                                    message.imageUrl,
                                    width: 180,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const Icon(Icons.broken_image, color: Colors.white54),
                                  ),
                                ),
                                if (message.message.isNotEmpty) const SizedBox(height: 6),
                              ],
                              if (message.message.isNotEmpty)
                                Text(
                                  message.message,
                                  style: TextStyle(color: isMine ? Colors.white : AppColors.lightTextPrimary),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          _quickChips(),
          const SizedBox(height: 8),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  // Share a photo of where the driver is standing.
                  CircleAvatar(
                    backgroundColor: AppColors.lightSurface,
                    child: _sendingPhoto
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                          )
                        : IconButton(
                            icon: const Icon(Icons.camera_alt_rounded, color: AppColors.primary, size: 20),
                            onPressed: _sendPhoto,
                          ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'chat.hint'.tr(),
                        filled: true,
                        fillColor: AppColors.lightBackground,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: AppColors.primary,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white, size: 18),
                      onPressed: _send,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
