import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../data/support_models.dart';

class NotificationDetailScreen extends StatelessWidget {
  final DriverNotification notification;

  const NotificationDetailScreen({super.key, required this.notification});

  @override
  Widget build(BuildContext context) {
    final date = notification.sentAt ?? notification.createdAt;
    return Scaffold(
      appBar: const CustomAppBar(title: 'Notification'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (notification.image.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                notification.image,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          if (notification.image.isNotEmpty) const SizedBox(height: 16),
          Text(
            notification.title.isEmpty ? 'Notification' : notification.title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          if (date != null) ...[
            const SizedBox(height: 6),
            Text(
              '${date.day}/${date.month}/${date.year} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(color: AppColors.lightTextSecondary, fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            notification.body,
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
        ],
      ),
    );
  }
}
