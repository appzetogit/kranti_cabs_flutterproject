import 'app_constants.dart';

/// Endpoint paths only — host/base URL live in [AppConstants] (single source
/// of truth for environment config). Mirrors `Backend/src/modules/taxi/driver`
/// and `.../user/routes/rideRoutes.js` on the shared taxi backend.
class ApiConstants {
  ApiConstants._();

  static const String baseUrl = AppConstants.baseUrl;

  static const String socketUrl = AppConstants.socketUrl;

  // Auth
  static const String register = '/drivers/register';
  static const String login = '/drivers/login';
  static const String sendOtp = '/drivers/auth/send-otp';
  static const String verifyOtp = '/drivers/auth/verify-otp';
  static const String approvalStatus = '/drivers/approval-status';

  // Onboarding (new-driver signup)
  static const String onboardingSendOtp = '/drivers/onboarding/send-otp';
  static const String onboardingVerifyOtp = '/drivers/onboarding/verify-otp';
  static const String onboardingRole = '/drivers/onboarding/role';
  static const String onboardingRoleDetails = '/drivers/onboarding/role-details';
  static const String onboardingPersonal = '/drivers/onboarding/personal';
  static const String onboardingReferral = '/drivers/onboarding/referral';
  static const String onboardingVehicle = '/drivers/onboarding/vehicle';
  static const String onboardingVehicleVerifyRc = '/drivers/onboarding/vehicle/verify-rc';
  static const String onboardingDocuments = '/drivers/onboarding/documents';
  static const String onboardingComplete = '/drivers/onboarding/complete';
  static String onboardingSession(String registrationId) =>
      '/drivers/onboarding/session/$registrationId';
  static const String onboardingSignupOptions = '/drivers/onboarding/signup-options';
  static const String documentTemplates = '/drivers/document-templates';
  static const String vehicleFieldTemplates = '/drivers/vehicle-field-templates';
  // Public catalog — the same tiers riders book, so onboarding can bind a
  // driver to a real vehicle type instead of a generic 'bike'/'car' string.
  static const String vehicleTypes = '/users/vehicle-types';
  /// Slim marker-art feed used to draw the vehicle on the map.
  static const String vehicleMapIcons = '/users/vehicle-map-icons';
  static String onboardingVerifyLicense(String documentKey) =>
      '/drivers/onboarding/documents/$documentKey/verify-license';

  // Bus driver (operate) — assigned bus service's seats, manifest, manual
  // reservations, live trip and schedules. All require an approved bus_driver.
  static const String busSeats = '/drivers/bus/seats';
  static const String busBookings = '/drivers/bus/bookings';
  static const String busReservations = '/drivers/bus/reservations';
  static const String busLiveTrip = '/drivers/bus/live-trip';
  static const String busLiveTripStart = '/drivers/bus/live-trip/start';
  static const String busLiveTripLocation = '/drivers/bus/live-trip/location';
  static const String busLiveTripStatus = '/drivers/bus/live-trip/status';
  static const String busSchedules = '/drivers/bus/schedules';

  // Profile / session
  static const String me = '/drivers/me';
  /// Destination mode ("Go Home"): GET state, PUT { enabled, useHome?, lat?, lng?, label? }.
  static const String destinationMode = '/drivers/me/destination';
  /// PUT { lat, lng, address } - the driver's saved home.
  static const String homeLocation = '/drivers/me/home-location';
  /// Zone-targeted promo banners for the driver app (no token needed).
  static const String banners = '/drivers/banners';
  static const String deleteRequest = '/drivers/me/delete-request';
  static const String goOnline = '/drivers/online';
  static const String goOffline = '/drivers/offline';
  static const String vehicle = '/drivers/vehicle';
  static const String fcmToken = '/drivers/fcm-token';

  // Routing — shared with the rider app; the backend accepts both roles.
  static const String route = '/users/route';

  // Documents / KYC
  static String document(String documentKey) => '/drivers/documents/$documentKey';
  static String verifyLicense(String documentKey) => '/drivers/documents/$documentKey/verify-license';
  static String verifyPan(String documentKey) => '/drivers/documents/$documentKey/verify-pan';
  static String verifyGst(String documentKey) => '/drivers/documents/$documentKey/verify-gst';
  static String verifyRc(String documentKey) => '/drivers/documents/$documentKey/verify-rc';
  static String verifyBank(String documentKey) => '/drivers/documents/$documentKey/verify-bank';
  static const String bankDetailsVerify = '/drivers/me/bank-details/verify';
  static const String upiVerify = '/drivers/me/upi/verify';

  // Wallet / earnings
  static const String wallet = '/drivers/wallet';
  /// Aggregated ride demand around the driver, for the demand map.
  static const String driverHeatmap = '/drivers/heatmap';
  // Surge + demand on one grid, best places to go, airports. Read-only.
  static const String driverOpportunityMap = '/drivers/opportunity-map';
  static const String walletTopUp = '/drivers/wallet/top-up';
  static const String walletTopUpRazorpayOrder = '/drivers/wallet/top-up/razorpay/order';
  static const String walletTopUpRazorpayVerify = '/drivers/wallet/top-up/razorpay/verify';
  static const String walletWithdrawals = '/drivers/wallet/withdrawals';
  static const String incentives = '/drivers/incentives';
  static const String incentivesClaim = '/drivers/incentives/claim';
  static const String paymentsQr = '/drivers/payments/qr';
  static const String paymentsQrStatus = '/drivers/payments/qr/status';
  // Driver's own static payment UPI/QR (shown to riders at ride-end).
  static const String paymentUpi = '/drivers/me/payment-upi';

  // Daily subscription (flat-fee pass in place of per-trip commission)
  static const String subscriptionStatus = '/drivers/subscription';
  static const String subscriptionPurchase = '/drivers/subscription/purchase';
  static const String subscriptionHistory = '/drivers/subscription/history';

  // Rides
  static const String rides = '/rides';
  static const String activeRide = '/rides/active/me';
  static String rideById(String rideId) => '/rides/$rideId';
  static String rideStatus(String rideId) => '/rides/$rideId/status';
  /// Handover photo for a parcel delivery. The trip cannot start or complete
  /// until the matching one has been posted.
  static String parcelProof(String rideId) => '/rides/$rideId/parcel-proof';
  /// Offers already dispatched to this driver that the socket may have missed.
  /// Polled after reconnecting on the back of a `ride_request` push.
  static const String rideOffers = '/drivers/ride-offers';
  static const String scheduledRides = '/drivers/scheduled-rides';
  /// REST accept (the native offer card uses it too). Also takes an open
  /// scheduled ride from the Scheduled Rides list, in advance.
  static String acceptRideOffer(String rideId) => '/drivers/ride-offers/$rideId/accept';
  static String cancelScheduledRide(String rideId) => '/drivers/scheduled-rides/$rideId/cancel';

  // Safety
  static const String sos = '/drivers/sos';
  static const String emergencyContacts = '/drivers/emergency-contacts';
  static String emergencyContact(String contactId) => '/drivers/emergency-contacts/$contactId';

  // Notifications
  static const String notifications = '/drivers/notifications';

  // Support
  static const String supportTitles = '/support/titles';
  static const String supportTickets = '/support/tickets';
  static const String myTickets = '/support/tickets/my';
  static String supportTicket(String ticketCode) => '/support/tickets/$ticketCode';
  static String supportTicketReply(String ticketCode) => '/support/tickets/$ticketCode/reply';

  // Common
  static const String uploadImage = '/common/upload/image';
  static const String serviceLocations = '/drivers/service-locations';
}
