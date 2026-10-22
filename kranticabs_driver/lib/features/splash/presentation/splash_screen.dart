import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/ride_offer_channel.dart';
import '../../../core/services/update_service.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/application/auth_state.dart';
import '../../auth/application/signup_providers.dart';
import '../../bus/application/bus_auth_providers.dart';
import '../../language/presentation/language_screen.dart';
import '../../profile/application/settings_providers.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    UpdateService.checkForUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveNextRoute());
  }

  Future<void> _resolveNextRoute() async {
    await Future.delayed(const Duration(milliseconds: 1000));

    // Keep native in sync with the saved language so the background ride-offer
    // voice speaks in the driver's chosen language on every launch.
    unawaited(RideOfferChannel.setLocale(ref.read(settingsProvider).languageCode));

    // First launch only: let the driver pick a language before anything else.
    // The language screen continues to the normal destination after selecting.
    final prefs = await SharedPreferences.getInstance();
    final languageChosen = prefs.getBool(kLanguageSelectedPrefKey) ?? false;
    if (!languageChosen) {
      if (!mounted) return;
      context.go('/language-selection');
      return;
    }

    // Bus partner session takes priority: its saved token is a bus_driver's, so
    // the taxi restore below must not consume it.
    final busProfile = await ref.read(busAuthProvider.notifier).restore();
    if (!mounted) return;
    if (busProfile != null) {
      context.go(busProfile.canOperate ? '/bus-home' : '/bus-pending');
      return;
    }

    await ref.read(authProvider.notifier).restoreSession();
    if (!mounted) return;
    final auth = ref.read(authProvider);
    if (auth.status == AuthStatus.authenticated) {
      final driver = auth.driver;
      if (driver != null && !driver.isApproved) {
        context.go('/verification-pending');
      } else {
        context.go('/home');
      }
    } else {
      // A signup the phone killed mid-way (often while the camera was open on
      // the documents step) resumes where it stopped, not at the phone number.
      // Login sits underneath, so Back still leads somewhere sensible for a
      // driver who would rather start over or sign in.
      final resumeRoute = await ref.read(signupProvider.notifier).restoreSaved();
      if (!mounted) return;
      context.go('/login');
      if (resumeRoute != null) context.push(resumeRoute);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(
        child: Image.asset(
          'assets/splash.webp',
          fit: BoxFit.cover,
          alignment: Alignment.center,
          errorBuilder: (context, error, stackTrace) => Image.asset(
            'assets/logo.webp',
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
