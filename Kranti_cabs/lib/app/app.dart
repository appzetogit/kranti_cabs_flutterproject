import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../features/home/presentation/location_guard.dart';
import '../features/home/presentation/no_driver_watcher.dart';
import '../features/home/presentation/shared_location_handler.dart';
import '../features/profile/application/locale_provider.dart';
import '../l10n/app_localizations.dart';
import 'router.dart';

class _AppScrollBehavior extends ScrollBehavior {
  const _AppScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class TaxiUserApp extends ConsumerWidget {
  const TaxiUserApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watched, not read: choosing a language anywhere in the app rebuilds
    // every screen in that language without a restart.
    final locale = ref.watch(appLocaleProvider);

    return MaterialApp.router(
      title: 'Kranti Cabs',
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      scrollBehavior: const _AppScrollBehavior(),
      routerConfig: appRouter,
      builder: (context, child) => LocationGuard(
        child: SharedLocationHandler(
          child: NoDriverWatcher(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}
