import '../features/kyc/presentation/verify_identity_screen.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/navigation/navigator_key.dart';
import '../features/auth/presentation/account_created_screen.dart';
import '../features/auth/presentation/location_permission_screen.dart';
import '../features/auth/presentation/notification_permission_screen.dart';
import '../features/auth/presentation/otp_screen.dart';
import '../features/auth/presentation/phone_entry_screen.dart';
import '../features/auth/presentation/profile_setup_screen.dart';
import '../features/delivery/presentation/delivery_history_screen.dart';
import '../features/delivery/presentation/delivery_address_screen.dart';
import '../features/delivery/presentation/delivery_category_vehicles_screen.dart';
import '../features/delivery/presentation/delivery_vehicle_screen.dart';
import '../features/delivery/presentation/delivery_vehicle_select_screen.dart';
import '../features/delivery/presentation/finding_captain_screen.dart';
import '../features/delivery/presentation/new_delivery_screen.dart';
import '../features/delivery/presentation/parcel_details_screen.dart';
import '../features/ride/presentation/ride_bids_screen.dart';
import '../features/home/presentation/all_services_screen.dart';
import '../features/home/presentation/confirm_booking_screen.dart';
import '../features/home/presentation/finding_driver_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/home/presentation/map_picker_screen.dart';
import '../features/home/presentation/no_driver_screen.dart';
import '../features/home/presentation/promo_screen.dart';
import '../features/home/presentation/ride_type_screen.dart';
import '../features/home/presentation/saved_places_screen.dart';
import '../features/home/presentation/search_destination_screen.dart';
import '../features/misc/presentation/force_logout_screen.dart';
import '../features/misc/presentation/force_update_screen.dart';
import '../features/misc/presentation/gps_disabled_screen.dart';
import '../features/misc/presentation/location_permission_denied_screen.dart';
import '../features/misc/presentation/maintenance_screen.dart';
import '../features/misc/presentation/no_internet_screen.dart';
import '../features/misc/presentation/server_error_screen.dart';
import '../features/misc/presentation/session_expired_screen.dart';
import '../features/notifications/presentation/notification_settings_screen.dart';
import '../features/notifications/presentation/notifications_screen.dart';
import '../features/onboarding/presentation/language_select_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/profile/presentation/delete_account_screen.dart';
import '../features/profile/presentation/edit_profile_screen.dart';
import '../features/profile/presentation/emergency_contacts_screen.dart';
import '../features/profile/presentation/language_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/profile/presentation/theme_screen.dart';
import '../features/rental/data/models/rental_vehicle_model.dart';
import '../features/rental/presentation/rental_booking_screen.dart';
import '../features/rental/presentation/rental_history_screen.dart';
import '../features/rental/presentation/rental_vehicles_screen.dart';
import '../features/rewards/presentation/rewards_screen.dart';
import '../features/ride/presentation/rating_review_screen.dart';
import '../features/ride/presentation/ride_chat_screen.dart';
import '../features/ride/presentation/ride_detail_screen.dart';
import '../features/ride/presentation/ride_history_screen.dart';
import '../features/ride/presentation/ride_tracking_screen.dart';
import '../features/settings/presentation/about_screen.dart';
import '../features/settings/presentation/security_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/settings/presentation/static_content_screen.dart';
import '../features/splash/presentation/splash_screen.dart';
import '../features/subscription/presentation/subscription_screen.dart';
import '../features/support/presentation/new_ticket_screen.dart';
import '../features/support/presentation/safety_center_screen.dart';
import '../features/support/presentation/sos_screen.dart';
import '../features/support/presentation/support_home_screen.dart';
import '../features/support/presentation/ticket_detail_screen.dart';
import '../features/wallet/presentation/wallet_screen.dart';

final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
    GoRoute(
      path: '/language',
      builder: (context, state) => LanguageSelectScreen(
        next: state.uri.queryParameters['next'] ?? '/onboarding',
      ),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),

    // Auth
    GoRoute(
      path: '/auth/phone',
      builder: (context, state) => const PhoneEntryScreen(),
    ),
    GoRoute(
      path: '/auth/otp',
      builder: (context, state) =>
          OtpScreen(phone: state.extra as String? ?? ''),
    ),
    GoRoute(
      path: '/auth/signup',
      builder: (context, state) =>
          ProfileSetupScreen(phone: state.extra as String? ?? ''),
    ),
    GoRoute(
      path: '/auth/location-permission',
      builder: (context, state) => const LocationPermissionScreen(),
    ),
    GoRoute(
      path: '/auth/notification-permission',
      builder: (context, state) => const NotificationPermissionScreen(),
    ),
    GoRoute(
      path: '/auth/account-created',
      builder: (context, state) => const AccountCreatedScreen(),
    ),

    // Home & booking
    GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
    GoRoute(
      path: '/home/all-services',
      builder: (context, state) => const AllServicesScreen(),
    ),
    GoRoute(
      path: '/search',
      redirect: (context, state) {
        final title =
            (state.extra as String?) ?? state.uri.queryParameters['title'];
        if (title != null && title.isNotEmpty) {
          return '/home/search?title=${Uri.encodeComponent(title)}';
        }
        return '/home/search';
      },
    ),
    GoRoute(
      path: '/outstation',
      redirect: (context, state) {
        final title =
            (state.extra as String?) ??
            state.uri.queryParameters['title'] ??
            'Kranti Outstation';
        // `outstation=1` is what switches the booking to the intercity tariff.
        // Without it this route opened the ordinary search screen and the trip
        // was priced, and filed, as a normal city ride.
        return '/home/search?outstation=1&title=${Uri.encodeComponent(title)}';
      },
    ),
    GoRoute(
      path: '/home/search',
      builder: (context, state) {
        final title =
            (state.extra as String?) ?? state.uri.queryParameters['title'];
        final isOutstation = state.uri.queryParameters['outstation'] == '1';
        return SearchDestinationScreen(
          title: title,
          isOutstation: isOutstation,
          moduleId: state.uri.queryParameters['moduleId'],
        );
      },
    ),
    GoRoute(
      path: '/home/map-picker',
      builder: (context, state) =>
          MapPickerScreen(type: state.uri.queryParameters['type'] ?? 'pickup'),
    ),
    GoRoute(
      path: '/saved-places',
      redirect: (context, state) => '/home/saved-places',
    ),
    GoRoute(
      path: '/profile/saved-places',
      redirect: (context, state) => '/home/saved-places',
    ),
    GoRoute(
      path: '/home/saved-places',
      builder: (context, state) => const SavedPlacesScreen(),
    ),
    GoRoute(
      path: '/home/ride-types',
      builder: (context, state) => const RideTypeScreen(),
    ),
    GoRoute(
      path: '/home/promo',
      builder: (context, state) => const PromoScreen(),
    ),
    GoRoute(
      path: '/home/confirm',
      builder: (context, state) => const ConfirmBookingScreen(),
    ),
    GoRoute(
      path: '/home/finding-driver',
      builder: (context, state) => const FindingDriverScreen(),
    ),
    GoRoute(
      path: '/home/no-driver',
      builder: (context, state) => const NoDriverScreen(),
    ),

    // Ride
    GoRoute(
      path: '/ride/tracking/:rideId',
      builder: (context, state) =>
          RideTrackingScreen(rideId: state.pathParameters['rideId']!),
    ),
    GoRoute(
      path: '/ride/:rideId/chat',
      builder: (context, state) =>
          RideChatScreen(rideId: state.pathParameters['rideId']!),
    ),
    GoRoute(
      path: '/ride/:rideId/rating',
      builder: (context, state) =>
          RatingReviewScreen(rideId: state.pathParameters['rideId']!),
    ),
    GoRoute(
      path: '/rides',
      builder: (context, state) => const RideHistoryScreen(),
    ),
    GoRoute(
      path: '/ride/history',
      builder: (context, state) => const RideHistoryScreen(),
    ),
    GoRoute(
      path: '/rides/:rideId',
      builder: (context, state) =>
          RideDetailScreen(rideId: state.pathParameters['rideId']!),
    ),
    GoRoute(
      path: '/ride/detail/:rideId',
      builder: (context, state) =>
          RideDetailScreen(rideId: state.pathParameters['rideId']!),
    ),

    // Wallet
    GoRoute(path: '/wallet', builder: (context, state) => const WalletScreen()),

    // Notifications
    GoRoute(
      path: '/notifications',
      builder: (context, state) => const NotificationsScreen(),
    ),
    GoRoute(
      path: '/notifications/settings',
      builder: (context, state) => const NotificationSettingsScreen(),
    ),

    // Profile
    GoRoute(
      path: '/profile',
      builder: (context, state) => const ProfileScreen(),
    ),
    GoRoute(
      path: '/profile/verify-identity',
      builder: (context, state) =>
          VerifyIdentityScreen(returnToBooking: state.extra == true),
    ),
    GoRoute(
      path: '/profile/edit',
      builder: (context, state) => const EditProfileScreen(),
    ),
    GoRoute(
      path: '/profile/emergency-contacts',
      builder: (context, state) => const EmergencyContactsScreen(),
    ),
    GoRoute(
      path: '/profile/language',
      builder: (context, state) => const LanguageScreen(),
    ),
    GoRoute(
      path: '/profile/theme',
      builder: (context, state) => const ThemeScreen(),
    ),
    GoRoute(
      path: '/profile/delete-account',
      builder: (context, state) => const DeleteAccountScreen(),
    ),

    // Support
    GoRoute(
      path: '/support',
      builder: (context, state) => const SupportHomeScreen(),
    ),
    GoRoute(
      path: '/support/safety-center',
      builder: (context, state) => const SafetyCenterScreen(),
    ),
    GoRoute(
      path: '/support/new-ticket',
      builder: (context, state) => const NewTicketScreen(),
    ),
    GoRoute(
      path: '/support/tickets/:ticketCode',
      builder: (context, state) =>
          TicketDetailScreen(ticketCode: state.pathParameters['ticketCode']!),
    ),
    GoRoute(
      path: '/support/sos',
      builder: (context, state) =>
          SosScreen(rideId: state.uri.queryParameters['rideId']),
    ),

    // Settings
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/settings/privacy',
      builder: (context, state) => const StaticContentScreen(
        title: 'Privacy policy',
        body: privacyPolicyBody,
      ),
    ),
    GoRoute(
      path: '/settings/terms',
      builder: (context, state) => const StaticContentScreen(
        title: 'Terms & conditions',
        body: termsBody,
      ),
    ),
    GoRoute(
      path: '/settings/security',
      builder: (context, state) => const SecurityScreen(),
    ),
    GoRoute(
      path: '/settings/about',
      builder: (context, state) => const AboutScreen(),
    ),

    // Rental
    GoRoute(
      path: '/rental',
      builder: (context, state) => const RentalVehiclesScreen(),
    ),
    GoRoute(
      path: '/rental/history',
      builder: (context, state) => const RentalHistoryScreen(),
    ),
    GoRoute(
      path: '/rental/:vehicleId/book',
      builder: (context, state) =>
          RentalBookingScreen(vehicle: state.extra as RentalVehicleModel),
    ),

    // Delivery
    GoRoute(
      path: '/delivery/new',
      builder: (context, state) => const NewDeliveryScreen(),
    ),
    // Multi-step parcel flow: category -> address & contacts -> parcel details
    // -> choose a priced vehicle -> dispatch search.
    GoRoute(
      path: '/delivery/vehicle',
      builder: (context, state) => DeliveryVehicleScreen(
        moduleId: state.uri.queryParameters['moduleId'],
      ),
    ),
    GoRoute(
      path: '/delivery/vehicle/:categoryId',
      builder: (context, state) => DeliveryCategoryVehiclesScreen(
        categoryId: state.pathParameters['categoryId']!,
      ),
    ),
    GoRoute(
      path: '/delivery/address',
      builder: (context, state) => const DeliveryAddressScreen(),
    ),
    GoRoute(
      path: '/delivery/details',
      builder: (context, state) => const ParcelDetailsScreen(),
    ),
    GoRoute(
      path: '/delivery/vehicle-select',
      builder: (context, state) => const DeliveryVehicleSelectScreen(),
    ),
    GoRoute(
      path: '/ride/bids/:rideId',
      builder: (context, state) =>
          RideBidsScreen(rideId: state.pathParameters['rideId'] ?? ''),
    ),
    GoRoute(
      path: '/delivery/finding/:rideId',
      builder: (context, state) =>
          FindingCaptainScreen(rideId: state.pathParameters['rideId']!),
    ),
    GoRoute(
      path: '/delivery/history',
      builder: (context, state) => const DeliveryHistoryScreen(),
    ),

    // Subscription & rewards
    GoRoute(
      path: '/subscription',
      builder: (context, state) => const SubscriptionScreen(),
    ),
    GoRoute(
      path: '/rewards',
      builder: (context, state) => const RewardsScreen(),
    ),

    // System / error screens
    GoRoute(
      path: '/system/force-update',
      builder: (context, state) => const ForceUpdateScreen(),
    ),
    GoRoute(
      path: '/system/maintenance',
      builder: (context, state) => const MaintenanceScreen(),
    ),
    GoRoute(
      path: '/system/no-internet',
      builder: (context, state) => const NoInternetScreen(),
    ),
    GoRoute(
      path: '/system/server-error',
      builder: (context, state) => const ServerErrorScreen(),
    ),
    GoRoute(
      path: '/system/gps-disabled',
      builder: (context, state) => const GpsDisabledScreen(),
    ),
    GoRoute(
      path: '/system/location-permission-denied',
      builder: (context, state) => const LocationPermissionDeniedScreen(),
    ),
    GoRoute(
      path: '/system/session-expired',
      builder: (context, state) => const SessionExpiredScreen(),
    ),
    GoRoute(
      path: '/system/force-logout',
      builder: (context, state) =>
          ForceLogoutScreen(reason: state.extra as String?),
    ),
  ],
  errorBuilder: (context, state) =>
      Scaffold(body: Center(child: Text('Page not found: ${state.uri}'))),
);
