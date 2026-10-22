import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/update_service.dart';
import '../../auth/application/auth_providers.dart';
import '../../profile/application/locale_provider.dart';
import '../../auth/application/auth_state.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    await Future.delayed(const Duration(milliseconds: 2000));
    await ref.read(authControllerProvider.notifier).bootstrap();

    if (!mounted) return;
    final authState = ref.read(authControllerProvider);
    final destination =
        authState.status == AuthStatus.authenticated ? '/home' : '/onboarding';

    // Asked once, before anything else: the answer sets both the app language
    // and the language the cab speaks during a trip. Riders who already chose
    // go straight through.
    if (!ref.read(languageChosenProvider)) {
      context.go('/language?next=${Uri.encodeComponent(destination)}');
      return;
    }

    context.go(destination);
  }

  @override
  Widget build(BuildContext context) {
    return const AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(
          child: Image(
            image: AssetImage('assets/splash.webp'),
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
        ),
      ),
    );
  }
}
