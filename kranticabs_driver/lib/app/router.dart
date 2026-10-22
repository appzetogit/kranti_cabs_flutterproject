import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/navigation/navigator_key.dart';
import '../features/heatmap/presentation/demand_map_screen.dart';
import '../features/auth/presentation/documents_upload_screen.dart';
import '../features/auth/presentation/location_permission_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/notification_permission_screen.dart';
import '../features/auth/presentation/otp_screen.dart';
import '../features/auth/presentation/profile_setup_screen.dart';
import '../features/auth/presentation/signup_otp_screen.dart';
import '../features/auth/presentation/signup_phone_screen.dart';
import '../features/auth/presentation/vehicle_info_screen.dart';
import '../features/auth/presentation/verification_approved_screen.dart';
import '../features/auth/presentation/verification_pending_screen.dart';
import '../features/auth/presentation/welcome_screen.dart';
import '../features/bus/presentation/bus_add_booking_screen.dart';
import '../features/bus/presentation/bus_login_otp_screen.dart';
import '../features/bus/presentation/bus_login_screen.dart';
import '../features/bus/presentation/bus_main_shell.dart';
import '../features/bus/presentation/bus_pending_screen.dart';
import '../features/bus/presentation/bus_register_bus_screen.dart';
import '../features/bus/presentation/bus_register_otp_screen.dart';
import '../features/bus/presentation/bus_register_personal_screen.dart';
import '../features/bus/presentation/bus_register_phone_screen.dart';
import '../features/dashboard/presentation/main_shell.dart';
import '../features/earnings/presentation/bank_account_screen.dart';
import '../features/earnings/presentation/earnings_screen.dart';
import '../features/earnings/presentation/incentives_screen.dart';
import '../features/earnings/presentation/transactions_screen.dart';
import '../features/earnings/presentation/wallet_screen.dart';
import '../features/earnings/presentation/withdraw_screen.dart';
import '../features/profile/presentation/delete_account_screen.dart';
import '../features/language/presentation/language_screen.dart';
import '../features/profile/presentation/documents_screen.dart';
import '../features/profile/presentation/payment_upi_screen.dart';
import '../features/profile/presentation/edit_profile_screen.dart';
// NOTE: the old placeholder profile/language_screen.dart was replaced by the
// real easy_localization screen imported above.
import '../features/profile/presentation/logout_screen.dart';
import '../features/profile/presentation/notification_settings_screen.dart';
import '../features/profile/presentation/preferences_screen.dart';
import '../features/profile/presentation/privacy_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/profile/presentation/safety_center_screen.dart';
import '../features/profile/presentation/settings_screen.dart';
import '../features/profile/presentation/vehicle_details_screen.dart';
import '../features/ride/data/ride_history_item.dart';
import '../features/ride/data/ride_model.dart';
import '../features/ride/presentation/active_ride_screen.dart';
import '../features/ride/presentation/invoice_screen.dart';
import '../features/ride/presentation/ride_chat_screen.dart';
import '../features/ride/presentation/ride_history_screen.dart';
import '../features/ride/presentation/ride_request_screen.dart';
import '../features/ride/presentation/trip_complete_screen.dart';
import '../features/ride/presentation/trip_detail_screen.dart';
import '../features/splash/presentation/splash_screen.dart';
import '../features/support/data/support_models.dart';
import '../features/support/presentation/chat_support_screen.dart';
import '../features/support/presentation/faq_screen.dart';
import '../features/support/presentation/help_center_screen.dart';
import '../features/support/presentation/notification_detail_screen.dart';
import '../features/support/presentation/notifications_screen.dart';
import '../features/support/presentation/raise_ticket_screen.dart';
import '../features/support/presentation/report_issue_screen.dart';
import '../features/system/presentation/force_update_screen.dart';
import '../features/system/presentation/gps_disabled_screen.dart';
import '../features/system/presentation/maintenance_screen.dart';
import '../features/system/presentation/no_internet_screen.dart';
import '../features/system/presentation/session_expired_screen.dart';
import '../features/subscription/presentation/daily_subscription_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/language-selection', builder: (context, state) => const LanguageScreen(initial: true)),
      GoRoute(path: '/language', builder: (context, state) => const LanguageScreen()),
      GoRoute(path: '/onboarding', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/welcome', builder: (context, state) => const WelcomeScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/otp',
        builder: (context, state) => OtpScreen(phone: state.extra as String),
      ),
      GoRoute(
        path: '/signup',
        // `extra` carries the number the driver already typed on the login
        // screen, when they turned out not to have an account yet.
        builder: (context, state) => SignupPhoneScreen(initialPhone: state.extra as String?),
      ),
      GoRoute(path: '/signup-otp', builder: (context, state) => const SignupOtpScreen()),
      GoRoute(path: '/signup-profile', builder: (context, state) => const ProfileSetupScreen()),
      GoRoute(path: '/location-permission', builder: (context, state) => const LocationPermissionScreen()),
      GoRoute(path: '/notification-permission', builder: (context, state) => const NotificationPermissionScreen()),
      GoRoute(path: '/vehicle-info', builder: (context, state) => const VehicleInfoScreen()),
      GoRoute(path: '/documents-upload', builder: (context, state) => const DocumentsUploadScreen()),
      GoRoute(path: '/payment-upi', builder: (context, state) => const PaymentUpiScreen()),
      GoRoute(path: '/verification-pending', builder: (context, state) => const VerificationPendingScreen()),
      GoRoute(path: '/verification-approved', builder: (context, state) => const VerificationApprovedScreen()),
      GoRoute(path: '/home', builder: (context, state) => const MainShell()),

      // Bus partner (bus_driver) — registration, login and operate dashboard.
      GoRoute(
        path: '/bus-login',
        builder: (context, state) => BusLoginScreen(initialPhone: state.extra as String?),
      ),
      GoRoute(
        path: '/bus-login-otp',
        builder: (context, state) {
          final e = state.extra is Map ? Map<String, dynamic>.from(state.extra as Map) : const {};
          return BusLoginOtpScreen(
            phone: (e['phone'] ?? '').toString(),
            debugOtp: e['debugOtp']?.toString(),
          );
        },
      ),
      GoRoute(
        path: '/bus-register',
        builder: (context, state) => BusRegisterPhoneScreen(initialPhone: state.extra as String?),
      ),
      GoRoute(
        path: '/bus-register-otp',
        builder: (context, state) {
          final e = state.extra is Map ? Map<String, dynamic>.from(state.extra as Map) : const {};
          return BusRegisterOtpScreen(
            phone: (e['phone'] ?? '').toString(),
            debugOtp: e['debugOtp']?.toString(),
          );
        },
      ),
      GoRoute(path: '/bus-register-personal', builder: (context, state) => const BusRegisterPersonalScreen()),
      GoRoute(path: '/bus-register-bus', builder: (context, state) => const BusRegisterBusScreen()),
      GoRoute(path: '/bus-pending', builder: (context, state) => const BusPendingScreen()),
      GoRoute(path: '/bus-home', builder: (context, state) => const BusMainShell()),
      GoRoute(
        path: '/bus-add-booking',
        builder: (context, state) {
          final e = state.extra is Map ? Map<String, dynamic>.from(state.extra as Map) : const {};
          return BusAddBookingScreen(
            scheduleId: (e['scheduleId'] ?? '').toString(),
            date: (e['date'] ?? '').toString(),
          );
        },
      ),
      GoRoute(path: '/ride-request', builder: (context, state) => const RideRequestScreen()),
      GoRoute(path: '/active-ride', builder: (context, state) => const ActiveRideScreen()),
      GoRoute(path: '/ride-chat', builder: (context, state) => const RideChatScreen()),
      GoRoute(
        path: '/trip-complete',
        builder: (context, state) => TripCompleteScreen(ride: state.extra is RideModel ? state.extra as RideModel : null),
      ),
      GoRoute(path: '/earnings', builder: (context, state) => const EarningsScreen()),
      GoRoute(path: '/demand-map', builder: (context, state) => const DemandMapScreen()),
      GoRoute(path: '/wallet', builder: (context, state) => const WalletScreen()),
      GoRoute(path: '/subscription', builder: (context, state) => const DailySubscriptionScreen()),
      GoRoute(path: '/transactions', builder: (context, state) => const TransactionsScreen()),
      GoRoute(path: '/withdraw', builder: (context, state) => const WithdrawScreen()),
      GoRoute(path: '/incentives', builder: (context, state) => const IncentivesScreen()),
      GoRoute(path: '/bank-account', builder: (context, state) => const BankAccountScreen()),
      GoRoute(path: '/ride-history', builder: (context, state) => const RideHistoryScreen()),
      GoRoute(
        path: '/trip-detail',
        builder: (context, state) => TripDetailScreen(ride: state.extra as RideHistoryItem),
      ),
      GoRoute(
        path: '/invoice',
        builder: (context, state) => InvoiceScreen(ride: state.extra as RideHistoryItem),
      ),
      GoRoute(path: '/notifications', builder: (context, state) => const NotificationsScreen()),
      GoRoute(
        path: '/notification-detail',
        builder: (context, state) => NotificationDetailScreen(notification: state.extra as DriverNotification),
      ),
      GoRoute(path: '/help-center', builder: (context, state) => const HelpCenterScreen()),
      GoRoute(path: '/faq', builder: (context, state) => const FaqScreen()),
      GoRoute(path: '/raise-ticket', builder: (context, state) => const RaiseTicketScreen()),
      GoRoute(
        path: '/report-issue',
        builder: (context, state) => ReportIssueScreen(tripId: state.extra as String?),
      ),
      GoRoute(
        path: '/chat-support',
        builder: (context, state) => ChatSupportScreen(ticketCode: state.extra as String?),
      ),
      GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
      GoRoute(path: '/edit-profile', builder: (context, state) => const EditProfileScreen()),
      GoRoute(path: '/vehicle-details', builder: (context, state) => const VehicleDetailsScreen()),
      GoRoute(path: '/documents', builder: (context, state) => const DocumentsScreen()),
      GoRoute(path: '/preferences', builder: (context, state) => const PreferencesScreen()),
      GoRoute(path: '/safety-center', builder: (context, state) => const SafetyCenterScreen()),
      GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
      GoRoute(path: '/notification-settings', builder: (context, state) => const NotificationSettingsScreen()),
      GoRoute(path: '/privacy', builder: (context, state) => const PrivacyScreen()),
      GoRoute(path: '/logout', builder: (context, state) => const LogoutScreen()),
      GoRoute(path: '/delete-account', builder: (context, state) => const DeleteAccountScreen()),
      GoRoute(path: '/no-internet', builder: (context, state) => const NoInternetScreen()),
      GoRoute(path: '/gps-disabled', builder: (context, state) => const GpsDisabledScreen()),
      GoRoute(path: '/maintenance', builder: (context, state) => const MaintenanceScreen()),
      GoRoute(path: '/force-update', builder: (context, state) => const ForceUpdateScreen()),
      GoRoute(path: '/session-expired', builder: (context, state) => const SessionExpiredScreen()),
    ],
  );
});
