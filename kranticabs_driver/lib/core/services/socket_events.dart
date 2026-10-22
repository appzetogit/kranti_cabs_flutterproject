class SocketEvents {
  SocketEvents._();

  // Connection / generic
  static const String error = 'errorMessage';

  // Driver presence & live location
  static const String locationUpdate = 'locationUpdate';

  // Ride room
  static const String rideJoin = 'ride:join';
  static const String rideRejoinCurrent = 'ride:rejoin-current';
  static const String rideJoined = 'ride:joined';
  static const String rideState = 'ride:state';

  // Ride dispatch (server -> driver)
  static const String rideRequest = 'rideRequest';
  static const String rideRequestClosed = 'rideRequestClosed';
  static const String rideBiddingUpdated = 'rideBiddingUpdated';
  static const String rideBidSubmitted = 'rideBidSubmitted';
  static const String rideAccepted = 'rideAccepted';
  static const String rideAcceptFailed = 'rideAcceptFailed';
  static const String rideCancelled = 'rideCancelled';

  // Driver -> server dispatch responses
  static const String acceptRide = 'acceptRide';
  static const String rejectRide = 'rejectRide';
  static const String submitRideBid = 'submitRideBid';

  // Ride lifecycle
  static const String rideStatusUpdate = 'ride:status:update';
  static const String rideStatusUpdated = 'ride:status:updated';
  static const String rideDriverLocationUpdate = 'ride:driver-location:update';
  static const String rideDriverLocationUpdated = 'ride:driver-location:updated';
  static const String rideDriverRouteUpdated = 'ride:driver-route:updated';

  // Chat
  static const String rideMessageSend = 'ride:message:send';
  static const String rideMessageNew = 'ride:message:new';
  static const String chatJoin = 'chat:join';
  static const String chatSend = 'chat:send';
  static const String chatRead = 'chat:read';
}
