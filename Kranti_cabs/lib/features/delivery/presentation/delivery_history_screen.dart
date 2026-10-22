import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/ride_card.dart';
import '../application/delivery_providers.dart';

class DeliveryHistoryScreen extends ConsumerWidget {
  const DeliveryHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deliveriesAsync = ref.watch(myDeliveriesProvider);

    return Scaffold(
      appBar: const CustomAppBar(title: 'My deliveries'),
      body: deliveriesAsync.when(
        data: (deliveries) {
          if (deliveries.isEmpty) {
            return const EmptyState(
              icon: Icons.local_shipping_outlined,
              title: 'No deliveries yet',
              message: 'Packages you send will show up here.',
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(myDeliveriesProvider.future),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: deliveries.length,
              itemBuilder: (context, index) {
                final delivery = deliveries[index];
                final ride = delivery.ride;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: RideCard(
                    pickup: ride.pickupAddress,
                    drop: ride.dropAddress,
                    date: ride.completedAt ?? ride.acceptedAt ?? DateTime.now(),
                    fare: ride.fare,
                    status: ride.status,
                    vehicleType: delivery.parcel.category.isNotEmpty ? delivery.parcel.category : 'Parcel',
                    onTap: () => context.push('/ride/tracking/${ride.rideId}'),
                  ),
                );
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load deliveries: $e')),
      ),
    );
  }
}
