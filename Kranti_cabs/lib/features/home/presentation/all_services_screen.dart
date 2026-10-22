import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/snackbar_utils.dart';
import '../../../shared/widgets/app_bottom_navigation_bar.dart';
import '../application/home_providers.dart';
import '../data/models/app_module_model.dart';

class ServiceCardData {
  final String title;
  final String subtitle;
  final IconData badgeIcon;
  final String assetImage;
  final String route;

  const ServiceCardData({
    required this.title,
    required this.subtitle,
    required this.badgeIcon,
    required this.assetImage,
    required this.route,
  });
}

class AllServicesScreen extends ConsumerWidget {
  const AllServicesScreen({super.key});

  static const List<ServiceCardData> _fallbackServices = [
    ServiceCardData(
      title: 'Instant Booking',
      subtitle: 'Book a ride instantly',
      badgeIcon: Icons.directions_car_filled_rounded,
      assetImage: 'assets/service_instant.webp',
      route: '/home/search?title=Instant%20Booking',
    ),
    ServiceCardData(
      title: 'Outstation',
      subtitle: 'One Way & Round Trip',
      badgeIcon: Icons.add_road_rounded,
      assetImage: 'assets/service_outstation.webp',
      route: '/home/search?title=Outstation&outstation=1',
    ),
    ServiceCardData(
      title: 'Car Rental',
      subtitle: 'Hourly, Daily & Long Term',
      badgeIcon: Icons.more_time_rounded,
      assetImage: 'assets/service_rental.webp',
      route: '/rental',
    ),
    ServiceCardData(
      title: 'Airport Booking',
      subtitle: 'Cab Booking + Parking Fee',
      badgeIcon: Icons.flight_takeoff_rounded,
      assetImage: 'assets/service_airport.webp',
      route: '/home/search?title=Airport%20Booking',
    ),
    ServiceCardData(
      title: 'Railway Station Booking',
      subtitle: 'Cab Booking + Parking Fee',
      badgeIcon: Icons.train_rounded,
      assetImage: 'assets/service_railway.webp',
      route: '/home/search?title=Railway%20Station',
    ),
  ];

  static int _modulePriority(AppModuleModel m) {
    if (m.orderBy > 1) return m.orderBy;
    final lower = m.name.toLowerCase();
    if (lower.contains('instant') || lower.contains('city')) return 1;
    if (lower.contains('outstation')) return 2;
    if (lower.contains('rental')) return 3;
    if (lower.contains('airport')) return 4;
    if (lower.contains('railway')) return 5;
    return 10;
  }

  static String _displayTitleForModule(AppModuleModel module) {
    final lower = module.name.toLowerCase();
    if (lower.contains('airport')) return 'Airport Booking';
    if (lower.contains('railway')) return 'Railway Station Booking';
    if (lower.contains('rental')) return 'Car Rental';
    return module.name;
  }

  static String _subtitleForModule(AppModuleModel module) {
    if (module.shortDescription.isNotEmpty &&
        module.shortDescription.length > 3) {
      return module.shortDescription;
    }
    final lower = module.name.toLowerCase();
    if (lower.contains('instant') || lower.contains('city')) {
      return 'Book a ride instantly';
    }
    if (lower.contains('outstation')) return 'One Way & Round Trip';
    if (lower.contains('rental')) return 'Hourly, Daily & Long Term';
    if (lower.contains('airport')) return 'Cab Booking + Parking Fee';
    if (lower.contains('railway')) return 'Cab Booking + Parking Fee';
    if (lower.contains('parcel') || lower.contains('delivery')) {
      return 'Parcel Delivery';
    }
    return 'Ride & Delivery';
  }

  static IconData _badgeIconForModule(AppModuleModel module) {
    final lower =
        '${module.name} ${module.transportType} ${module.serviceType}'
            .toLowerCase();
    if (lower.contains('instant') || lower.contains('city')) {
      return Icons.directions_car_filled_rounded;
    }
    if (lower.contains('outstation')) return Icons.add_road_rounded;
    if (lower.contains('rental')) return Icons.more_time_rounded;
    if (lower.contains('airport') || lower.contains('flight')) {
      return Icons.flight_takeoff_rounded;
    }
    if (lower.contains('railway') || lower.contains('train')) {
      return Icons.train_rounded;
    }
    if (lower.contains('parcel') || lower.contains('delivery')) {
      return Icons.inventory_2_rounded;
    }
    if (lower.contains('bus')) return Icons.directions_bus_rounded;
    return Icons.directions_car_rounded;
  }

  static String _fallbackAssetForModule(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('instant') || lower.contains('city')) {
      return 'assets/service_instant.webp';
    }
    if (lower.contains('airport')) return 'assets/service_airport.webp';
    if (lower.contains('railway')) return 'assets/service_railway.webp';
    if (lower.contains('rental')) return 'assets/service_rental.webp';
    if (lower.contains('outstation')) return 'assets/service_outstation.webp';
    return 'assets/service_instant.webp';
  }

  static String _routeForModule(AppModuleModel module) {
    final tt = module.transportType.toLowerCase();
    final st = module.serviceType.toLowerCase();
    if (tt == 'delivery' || st == 'delivery') {
      return '/delivery/vehicle?moduleId=${Uri.encodeComponent(module.id)}';
    }
    if (st == 'rental') return '/rental';

    final query = <String>[
      'moduleId=${Uri.encodeComponent(module.id)}',
      if (st == 'outstation') 'outstation=1',
    ].join('&');
    return '/home/search?$query';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const bgColor = Color(0xFF11191D);
    final modulesAsync = ref.watch(appModulesProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.go('/home');
      },
      child: Scaffold(
        backgroundColor: bgColor,
        bottomNavigationBar: const AppBottomNavigationBar(currentIndex: 1),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- TOP HEADER BAR WITH BACK ARROW & TITLE ---
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  children: [
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                      onPressed: () => context.go('/home'),
                    ),
                    const SizedBox(width: 16),
                    const Text(
                      'All Services',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),

              // --- VERTICAL LIST OF SERVICE CARDS & PROMO BANNER ---
              Expanded(
                child: modulesAsync.when(
                  data: (modules) {
                    final activeModules = modules
                        .where((m) => m.active)
                        .toList()
                      ..sort((a, b) =>
                          _modulePriority(a).compareTo(_modulePriority(b)));

                    if (activeModules.isNotEmpty) {
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: activeModules.length + 1,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          if (index == activeModules.length) {
                            return _buildSmartSavingsBanner(context);
                          }
                          final module = activeModules[index];
                          final title = _displayTitleForModule(module);
                          final subtitle = _subtitleForModule(module);
                          final badgeIcon = _badgeIconForModule(module);
                          final fallbackAsset =
                              _fallbackAssetForModule(module.name);

                          return _AllServiceCard(
                            title: title,
                            subtitle: subtitle,
                            imageUrl: module.mobileMenuIcon,
                            fallbackAsset: fallbackAsset,
                            badgeIcon: badgeIcon,
                            onTap: () => _onModuleTap(context, module),
                          );
                        },
                      );
                    }
                    return _buildFallbackList(context);
                  },
                  loading: () => _buildFallbackList(context),
                  error: (error, stack) => _buildFallbackList(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void _onModuleTap(BuildContext context, AppModuleModel module) {
    if (module.name.toLowerCase().contains('bus') ||
        module.serviceType.toLowerCase().contains('bus') ||
        module.transportType.toLowerCase().contains('bus')) {
      SnackbarUtils.info(context, 'Feature is Upcoming...');
      return;
    }
    final route = _routeForModule(module);
    final targetRoute = route == '/search' ? '/home/search' : route;
    final finalRoute = targetRoute.contains('?')
        ? '$targetRoute&title=${Uri.encodeComponent(module.name)}'
        : '$targetRoute?title=${Uri.encodeComponent(module.name)}';
    context.push(finalRoute, extra: module.name);
  }

  Widget _buildFallbackList(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: _fallbackServices.length + 1,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == _fallbackServices.length) {
          return _buildSmartSavingsBanner(context);
        }
        final item = _fallbackServices[index];
        return _AllServiceCard(
          title: item.title,
          subtitle: item.subtitle,
          imageUrl: '',
          fallbackAsset: item.assetImage,
          badgeIcon: item.badgeIcon,
          onTap: () {
            context.push(item.route, extra: item.title);
          },
        );
      },
    );
  }

  Widget _buildSmartSavingsBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/smart_savings_banner.webp',
        width: double.infinity,
        fit: BoxFit.cover,
      ),
    );
  }
}

class _AllServiceCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String imageUrl;
  final String fallbackAsset;
  final IconData badgeIcon;
  final VoidCallback onTap;

  const _AllServiceCard({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.fallbackAsset,
    required this.badgeIcon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 110,
      decoration: BoxDecoration(
        color: const Color(0xFF222222),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2E2E), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          splashColor: const Color(0xFFF5B400).withValues(alpha: 0.15),
          child: Stack(
            children: [
              // 1. Right-aligned vehicle / landscape photo
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: MediaQuery.of(context).size.width * 0.72,
                child: _buildCardImage(),
              ),

              // 2. Smooth gradient from solid dark on left to transparent on right
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      stops: [0.0, 0.40, 0.68, 1.0],
                      colors: [
                        Color(0xFF222222),
                        Color(0xFF222222),
                        Color(0x88222222),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // 3. Left Content: Badge Icon + Title + Subtitle
              Positioned(
                left: 16,
                top: 8,
                bottom: 8,
                right: 60,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF94A3B8),
                          letterSpacing: -0.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 4. Circular Yellow Arrow Button on far right
              Positioned(
                right: 14,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF5B400),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: 5,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF0F172A),
                        size: 19,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardImage() {
    if (imageUrl.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        alignment: Alignment.centerRight,
        placeholder: (context, url) => Image.asset(
          fallbackAsset,
          fit: BoxFit.cover,
          alignment: Alignment.centerRight,
        ),
        errorWidget: (context, url, error) => Image.asset(
          fallbackAsset,
          fit: BoxFit.cover,
          alignment: Alignment.centerRight,
        ),
      );
    }
    return Image.asset(
      fallbackAsset,
      fit: BoxFit.cover,
      alignment: Alignment.centerRight,
    );
  }
}
