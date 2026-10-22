import 'app_constants.dart';

/// Endpoint paths only — host/base URL live in [AppConstants] (single source
/// of truth for environment config).
class ApiConstants {
  ApiConstants._();

  static const String baseUrl = AppConstants.baseUrl;

  static const String socketUrl = AppConstants.socketUrl;

  // Auth
  static const String sendOtp = '/users/auth/send-otp';
  static const String verifyOtp = '/users/auth/verify-otp';
  static const String otpLogin = '/users/otp-login';
  static const String register = '/users/register';
  static const String signup = '/users/signup';
  static const String login = '/users/login';
  static const String fcmToken = '/users/fcm-token';

  // Profile
  static const String me = '/users/me';
  static const String profileImage = '/users/profile-image';
  static const String deleteRequest = '/users/me/delete-request';

  // Bootstrap / catalog
  static const String bootstrap = '/users/bootstrap';
  static const String appModules = '/users/app-modules';
  static const String settings = '/users/settings'; // + '/$category'
  static const String intercityPackages = '/users/intercity-packages';
  static const String goodsTypes = '/users/goods-types';
  static const String vehicleTypes = '/users/vehicle-types';
  /// Slim marker-art feed (id + icon_types + map_icon) used to draw vehicles
  /// on the map, instead of the ~7MB full catalog.
  static const String vehicleMapIcons = '/users/vehicle-map-icons';
  /// Admin-uploaded promo banners shown on the home screen.
  static const String banners = '/users/banners';
  static const String setPrices = '/users/set-prices';
  static const String tripCategory = '/users/trip-category';
  /// Road routes for the map, resolved server-side. Authenticated: each
  /// cache miss is a billed Directions call.
  static const String route = '/users/route';
  static const String zones = '/users/zones';
  static const String serviceLocations = '/users/service-locations';
  static const String serviceStores = '/users/service-stores';
  static const String rentalVehicles = '/users/rental-vehicles';

  // Notifications
  static const String notifications = '/users/notifications';

  // Wallet
  static const String wallet = '/users/wallet';
  static const String walletTopup = '/users/wallet/topup';
  static const String walletTransfer = '/users/wallet/transfer';
  static const String walletTransferDriver = '/users/wallet/transfer/driver';
  static const String walletRazorpayOrder = '/users/wallet/razorpay/order';
  static const String walletRazorpayVerify = '/users/wallet/razorpay/verify';
  static const String walletPhonepeOrder = '/users/wallet/phonepe/order';
  static const String walletPhonepeStatus = '/users/wallet/phonepe/status'; // + '/$merchantTransactionId'

  // Promo
  static const String promoValidate = '/promos/validate';
  static const String promoAvailable = '/promos/available';

  // Subscriptions
  static const String subscriptionPlans = '/users/subscriptions/plans';
  static const String mySubscriptions = '/users/subscriptions/me';
  static const String buySubscription = '/users/subscriptions/purchase';

  // Rides
  static const String rides = '/rides';

  /// Admin-managed reasons shown when the rider cancels a trip.
  static const String cancellationReasons = '/users/cancellation-reasons';
  static const String activeRide = '/rides/active/me';
  static const String availableDrivers = '/rides/available-drivers';
  static const String rideTipSettings = '/rides/app-settings/tip';

  // Rentals
  static const String rentalQuoteRequests = '/users/rental-quote-requests';
  static const String rentalBookings = '/users/rental-bookings';
  static const String activeRentalBooking = '/users/rental-bookings/active';
  static const String rentalAdvanceWallet = '/users/rental-advance/wallet';
  static const String rentalAdvanceRazorpayOrder = '/users/rental-advance/razorpay/order';
  static const String rentalAdvanceRazorpayVerify = '/users/rental-advance/razorpay/verify';
  static const String rentalAdvancePhonepeOrder = '/users/rental-advance/phonepe/order';
  static const String rentalAdvancePhonepeStatus = '/users/rental-advance/phonepe/status'; // + '/$merchantTransactionId'

  // Deliveries
  static const String deliveries = '/deliveries';

  // Bus
  static const String buses = '/users/buses'; // + '/routes', '/search', '/$id/seats'
  static const String busBookings = '/users/bus-bookings';
  static const String busBookingsOrder = '/users/bus-bookings/order';
  static const String busBookingsVerify = '/users/bus-bookings/verify';

  // Pooling
  static const String pooling = '/users/pooling'; // + '/search', '/routes/$id'
  static const String poolingBookings = '/users/pooling/bookings';
  static const String poolingBookingsOrder = '/users/pooling/bookings/order';
  static const String poolingBookingsVerify = '/users/pooling/bookings/verify';

  // Sos
  static const String sos = '/users/sos';
  static const String emergencyContacts = '/users/emergency-contacts';

  // Support
  static const String supportTitles = '/support/titles';
  static const String supportTickets = '/support/tickets';
  static const String myTickets = '/support/tickets/my';

  // Common
  static const String uploadImage = '/common/upload/image';
  static const String paymentGateway = '/common/payment-gateway';
  static const String referralsTranslation = '/common/referrals/translation';
  static const String referralsSettings = '/common/referrals/settings';
}
