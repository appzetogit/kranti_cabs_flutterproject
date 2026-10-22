import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../application/ride_providers.dart';
import '../application/ride_tracking_controller.dart';
import '../data/models/ride_message_model.dart';
import '../data/quick_replies.dart';

class RideChatScreen extends ConsumerStatefulWidget {
  final String rideId;
  const RideChatScreen({super.key, required this.rideId});

  @override
  ConsumerState<RideChatScreen> createState() => _RideChatScreenState();
}

class _RideChatScreenState extends ConsumerState<RideChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  static const _replyLangPrefKey = 'chat_quick_reply_lang';
  String _replyLang = 'en';
  bool _sendingPhoto = false;

  /// Message count at the last build, so the list only scrolls when a message
  /// actually arrives rather than on every location-driven rebuild.
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _loadReplyLang();
  }

  Future<void> _loadReplyLang() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_replyLangPrefKey);
      if (saved != null && QuickReplies.langOrder.contains(saved) && mounted) {
        setState(() => _replyLang = saved);
      }
    } catch (_) {}
  }

  Future<void> _setReplyLang(String lang) async {
    setState(() => _replyLang = lang);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_replyLangPrefKey, lang);
    } catch (_) {}
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    final controller = ref.read(rideTrackingControllerProvider(widget.rideId).notifier);
    // An emit on a dropped socket is lost without a trace, so the text is
    // only cleared once it has actually gone out.
    if (!controller.sendMessage(text)) {
      _showNotConnected();
      return;
    }
    _messageController.clear();
  }

  void _sendQuick(String text) {
    final sent = ref.read(rideTrackingControllerProvider(widget.rideId).notifier).sendMessage(text);
    if (!sent) _showNotConnected();
  }

  void _showNotConnected() {
    SnackbarUtils.error(context, 'Not connected. Message not sent, please try again.');
  }

  /// Keeps the newest message in view. Runs after the frame so the list has
  /// laid out the new bubble before its extent is read.
  void _scrollToEndOnNewMessage(int count) {
    if (count == _lastMessageCount) return;
    _lastMessageCount = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  /// Rider captures a photo of their current location and sends it to the driver.
  Future<void> _sendLocationPhoto() async {
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
      ref
          .read(rideTrackingControllerProvider(widget.rideId).notifier)
          .sendImageMessage(url, text: '📍 My current location');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send photo. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingPhoto = false);
    }
  }

  Widget _quickReplyBar() {
    final replies = QuickReplies.repliesFor(_replyLang);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Language selector for the quick replies
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: QuickReplies.langOrder.map((lang) {
                final selected = lang == _replyLang;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(QuickReplies.langLabels[lang] ?? lang,
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                    selected: selected,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    selectedColor: AppColors.primaryOrange,
                    labelStyle: TextStyle(color: selected ? Colors.white : const Color(0xFF475569)),
                    backgroundColor: const Color(0xFFF1F5F9),
                    onSelected: (_) => _setReplyLang(lang),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 6),
          // Quick reply chips in the chosen language
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: replies.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final text = replies[index];
                return ActionChip(
                  label: Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  backgroundColor: const Color(0xFFF8FAFC),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                  labelStyle: const TextStyle(color: Color(0xFF0F172A)),
                  onPressed: () => _sendQuick(text),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _callDriver(String phone) async {
    if (phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final tracking = ref.watch(rideTrackingControllerProvider(widget.rideId));
    final ride = tracking.ride;

    final driverName = (ride?.driver?.name.isNotEmpty == true) ? ride!.driver!.name : 'Driver';
    final vehicleNo = (ride?.driver?.vehicleNumber.isNotEmpty == true) ? ride!.driver!.vehicleNumber : '';
    final vehicleType = (ride?.driver?.vehicleMake.isNotEmpty == true)
        ? ride!.driver!.vehicleMake
        : (ride?.vehicleType?.isNotEmpty == true ? ride!.vehicleType! : '');
    final driverRating = (ride?.driver?.rating != null && ride!.driver!.rating > 0)
        ? ride.driver!.rating.toStringAsFixed(1)
        : '5.0';
    final driverPhone = ride?.driver?.phone ?? '';

    final messages = ride?.messages ?? <RideMessageModel>[];
    _scrollToEndOnNewMessage(messages.length);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A)),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Chat with Driver',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CircleAvatar(
              radius: 20,
              backgroundColor: const Color(0xFFF1F5F9),
              child: IconButton(
                icon: const Icon(Icons.call_outlined, color: Color(0xFF0F172A), size: 18),
                onPressed: () => _callDriver(driverPhone),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // --- DRIVER INFO BANNER ---
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: (ride?.driver?.profileImage != null && ride!.driver!.profileImage.isNotEmpty)
                      ? ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: ride.driver!.profileImage,
                            fit: BoxFit.cover,
                          ),
                        )
                      : const Icon(Icons.person, color: Color(0xFF0F172A), size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        driverName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$vehicleNo • $vehicleType',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFB800)),
                          const SizedBox(width: 3),
                          Text(
                            driverRating,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.two_wheeler_rounded,
                  size: 40,
                  color: Color(0xFF0F172A),
                ),
              ],
            ),
          ),

          // --- CHAT MESSAGES CANVAS ---
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              children: [
                // Date Chip: Today
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      'Today',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                if (messages.isEmpty)
                  _buildEmptyState()
                else
                  ...messages.map((m) {
                    final isUser = m.senderRole == 'user';
                    final timeStr = Formatters.time(m.sentAt);
                    return isUser
                        ? _buildOutgoingBubble(m.message, timeStr, imageUrl: m.imageUrl)
                        : _buildIncomingBubble(m.message, timeStr, imageUrl: m.imageUrl);
                  }),

                const SizedBox(height: 24),

                // --- SAFETY PRIORITY BANNER ---
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFFEDD5)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEDD5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.verified_user_outlined,
                          size: 22,
                          color: AppColors.primaryOrange,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Your safety is our priority',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Never share personal or payment details in chat.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // --- QUICK REPLY BAR (5 languages) ---
          _quickReplyBar(),

          // --- BOTTOM MESSAGE INPUT BAR ---
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: _sendingPhoto ? null : _sendLocationPhoto,
                            child: _sendingPhoto
                                ? const SizedBox(
                                    width: 20, height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF94A3B8)),
                                  )
                                : const Icon(
                                    Icons.camera_alt_rounded,
                                    size: 20,
                                    color: Color(0xFF94A3B8),
                                  ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF0F172A),
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Type a message...',
                                hintStyle: TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF94A3B8),
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(vertical: 12),
                              ),
                              onSubmitted: (_) => _send(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Material(
                    color: AppColors.primaryOrange,
                    shape: const CircleBorder(),
                    elevation: 2,
                    shadowColor: const Color(0x40FF5200),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _send,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(
                          Icons.near_me_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
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

  Widget _buildEmptyState() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.chat_bubble_outline_rounded, size: 36, color: Color(0xFF94A3B8)),
          SizedBox(height: 10),
          Text(
            'Say hi to your driver',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Messages you exchange will appear here.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncomingBubble(String message, String timeStr, {String imageUrl = ''}) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
          ),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageUrl.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(imageUrl: imageUrl, width: 180, fit: BoxFit.cover),
              ),
              if (message.isNotEmpty) const SizedBox(height: 6),
            ],
            if (message.isNotEmpty)
              Text(
                message,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0F172A),
                ),
              ),
            const SizedBox(height: 4),
            Text(
              timeStr,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutgoingBubble(String message, String timeStr, {String imageUrl = ''}) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
        decoration: const BoxDecoration(
          color: AppColors.primaryOrange,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(4),
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x33FF5200),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (imageUrl.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(imageUrl: imageUrl, width: 180, fit: BoxFit.cover),
              ),
              if (message.isNotEmpty) const SizedBox(height: 6),
            ],
            if (message.isNotEmpty)
              Text(
                message,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeStr,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.done_all_rounded,
                  size: 14,
                  color: Colors.white,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
