import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/empty_state.dart';
import '../application/notifications_providers.dart';

IconData _iconForType(String type) {
  switch (type) {
    case 'ride':
      return Icons.local_taxi_rounded;
    case 'promo':
      return Icons.local_offer_rounded;
    case 'wallet':
      return Icons.account_balance_wallet_rounded;
    default:
      return Icons.notifications_rounded;
  }
}

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsListProvider);

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Notifications',
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all_rounded),
            onPressed: () async {
              await ref.read(notificationsRepositoryProvider).markAllAsRead();
              ref.invalidate(notificationsListProvider);
            },
          ),
        ],
      ),
      body: notificationsAsync.when(
        data: (notifications) => notifications.isEmpty
            ? const EmptyState(
                icon: Icons.notifications_none_rounded,
                title: 'No notifications',
                message: 'You\'re all caught up. New updates will appear here.',
              )
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(notificationsListProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: notifications.length,
                  itemBuilder: (context, index) {
                    final notification = notifications[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                        child: Icon(_iconForType(notification.type), color: AppColors.primary),
                      ),
                      title: Text(
                        notification.title,
                        style: TextStyle(
                          fontWeight: notification.isRead ? FontWeight.w500 : FontWeight.w800,
                        ),
                      ),
                      subtitle: Text(notification.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: Text(
                        Formatters.time(notification.createdAt),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      onTap: () async {
                        await ref.read(notificationsRepositoryProvider).markAsRead(notification.id);
                        ref.invalidate(notificationsListProvider);
                        final rideId = notification.data['rideId']?.toString();
                        if (rideId != null && context.mounted) {
                          context.push('/ride/tracking/$rideId');
                        }
                      },
                    );
                  },
                ),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Could not load notifications',
          message: 'Please check your connection and try again.',
        ),
      ),
    );
  }
}
