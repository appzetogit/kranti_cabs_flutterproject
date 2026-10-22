import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/providers/core_providers.dart';

class DriverBanner {
  final String image, redirectUrl;
  const DriverBanner(this.image, this.redirectUrl);
}

/// Hidden with the × until the app restarts (in-memory only, on purpose).
final driverBannersHiddenProvider = StateProvider<bool>((ref) => false);

/// Zone-targeted banners for the driver's current location (two decimals,
/// ~1 km). On a failed refresh Riverpod keeps the previous banners, and with
/// none the strip simply isn't drawn - banners never show an error.
final driverBannersProvider = FutureProvider<List<DriverBanner>>((ref) async {
  Position? pos;
  try {
    pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
    ).timeout(const Duration(seconds: 8));
  } catch (_) {
    pos = await Geolocator.getLastKnownPosition().catchError((_) => null);
  }
  final data = await ref.watch(apiClientProvider).get(
    ApiConstants.banners,
    query: {
      if (pos != null) 'lat': pos.latitude.toStringAsFixed(2),
      if (pos != null) 'lng': pos.longitude.toStringAsFixed(2),
    },
  );
  final origin = AppConstants.mediaBaseUrl.replaceAll(RegExp(r'/+$'), '');
  return ((data as Map)['results'] as List? ?? const [])
      .whereType<Map>()
      .where((b) => b['active'] != false && '${b['image'] ?? ''}'.isNotEmpty)
      .map((b) {
    final image = '${b['image']}';
    return DriverBanner(
      image.startsWith('http') ? image : '$origin/${image.replaceFirst(RegExp(r'^/+'), '')}',
      '${b['redirect_url'] ?? ''}',
    );
  }).toList();
});

/// Slim rotating banner strip for the driver home screen.
class DriverBannerStrip extends ConsumerStatefulWidget {
  const DriverBannerStrip({super.key});

  @override
  ConsumerState<DriverBannerStrip> createState() => _DriverBannerStripState();
}

class _DriverBannerStripState extends ConsumerState<DriverBannerStrip> {
  final _page = PageController();
  Timer? _rotate, _refresh;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _rotate = Timer.periodic(const Duration(seconds: 4), (_) {
      final count = ref.read(driverBannersProvider).valueOrNull?.length ?? 0;
      if (count < 2 || !_page.hasClients) return;
      _page.animateToPage((_index + 1) % count,
          duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    });
    _refresh = Timer.periodic(const Duration(minutes: 10), (_) => ref.invalidate(driverBannersProvider));
  }

  @override
  void dispose() {
    _rotate?.cancel();
    _refresh?.cancel();
    _page.dispose();
    super.dispose();
  }

  Future<void> _open(String link) async {
    if (link.isEmpty) return;
    if (link.startsWith('/')) {
      context.push(link);
      return;
    }
    final uri = Uri.tryParse(link);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final banners = ref.watch(driverBannersProvider).valueOrNull ?? const [];
    if (banners.isEmpty || ref.watch(driverBannersHiddenProvider)) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 84,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: _page,
                itemCount: banners.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => _open(banners[i].redirectUrl),
                  child: Image.network(
                    banners[i].image,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF222222)),
                  ),
                ),
              ),
              if (banners.length > 1)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 5,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < banners.length; i++)
                        Container(
                          width: 5,
                          height: 5,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == _index ? Colors.white : Colors.white54,
                          ),
                        ),
                    ],
                  ),
                ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () => ref.read(driverBannersHiddenProvider.notifier).state = true,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
