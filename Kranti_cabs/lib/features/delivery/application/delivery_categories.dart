import 'package:flutter/material.dart';

/// The delivery cards a rider picks from before seeing vehicles.
///
/// Deliberately static in the app: these are a fixed product taxonomy, not
/// catalog data. Each `id` matches `DELIVERY_CATEGORY_TYPES` on the backend and
/// the admin panel's own option list — a vehicle's `delivery_category` is what
/// files it under one of these cards.
///
/// Keep in lockstep with:
///   Backend/src/modules/taxi/admin/models/Vehicle.js  (DELIVERY_CATEGORY_TYPES)
///   frontend/.../price-management/VehicleType.jsx     (DELIVERY_CATEGORY_OPTIONS)
class DeliveryCategory {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final String assetImage;

  const DeliveryCategory({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    this.assetImage = '',
  });
}

const kDeliveryCategories = <DeliveryCategory>[
  DeliveryCategory(
    id: 'trucks',
    title: 'Kranti Mini Truck',
    description: 'Mini trucks and pickups for heavier goods.',
    icon: Icons.local_shipping_rounded,
    assetImage: 'assets/truck_cat.webp',
  ),
  DeliveryCategory(
    id: '2wheeler',
    title: 'Kranti Scooty Parcel',
    description: 'Fast lightweight parcel bikes and two-wheel delivery options.',
    icon: Icons.two_wheeler_rounded,
    assetImage: 'assets/scooter_cat.webp',
  ),
  DeliveryCategory(
    id: 'auto',
    title: 'Kranti Luggage Auto',
    description: 'Three-wheeler auto for luggage and medium parcel loads.',
    icon: Icons.electric_rickshaw_rounded,
    assetImage: 'assets/auto_cat.webp',
  ),
  DeliveryCategory(
    id: 'movers',
    title: 'Kranti Bike Parcel',
    description: 'Van-sized parcel and consignment delivery.',
    icon: Icons.inventory_rounded,
    assetImage: 'assets/movers_cat.png',
  ),
];

DeliveryCategory? deliveryCategoryById(String id) {
  for (final category in kDeliveryCategories) {
    if (category.id == id) return category;
  }
  return null;
}
