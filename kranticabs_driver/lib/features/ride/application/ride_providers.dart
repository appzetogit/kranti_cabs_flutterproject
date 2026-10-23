import 'dart:async';
import 'dart:developer' as developer;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/services/app_launcher_service.dart';
import '../../../core/services/ride_offer_channel.dart';
import '../../../core/services/socket_events.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../profile/application/settings_providers.dart';
import '../data/parcel_info.dart';
import '../data/ride_model.dart';
import '../data/ride_repository.dart';
import 'ride_state.dart';

final rideRepositoryProvider = Provider<RideRepository>((ref) {
  return RideRepository(ref.watch(apiClientProvider));
});

class RideNotifier extends StateNotifier<RideFlowState> {
  final Ref ref;

  /// Safety-net poll for offers the realtime channels missed.
  ///
  /// The socket is still the primary path and the push is still the wake-up,
  /// but both can fail silently — a blocked websocket upgrade, a push that
  /// never lands — and when they do the driver simply never learns a ride was
  /// offered to them. One small request every few seconds while they are idle
  /// makes that unrecoverable case impossible.
  Timer? _offerPollTimer;

  static const Duration _offerPollInterval = Duration(seconds: 5);

  /// Fires when an in-app accept got no answer (socket dropped mid-accept), so
  /// the server is asked whether the ride is ours before Accept is offered
  /// again. Never resends the accept by itself: the server counts every
  /// attempt, and a retry loop looks like an auto clicker.
  Timer? _acceptTimeout;

  static const Duration _acceptAnswerWait = Duration(seconds: 12);

  /// Ordering signal for the rider app: every location send tags itself with
  /// this counter, and the rider keeps only the highest one seen, so a
  /// packet delayed by network jitter can never move the marker backward.
  ///
  /// Seeded from wall-clock time rather than starting at 0 so it stays
  /// correctly increasing even if the driver's app is killed and reopened
  /// mid-ride — a counter that restarted at 0 would make every location
  /// update after the restart look "older" than ones sent before it, and the
  /// rider would silently stop tracking until real time caught back up to
  /// wherever the old counter had reached.
  int _locationSequence = DateTime.now().millisecondsSinceEpoch;

  RideNotifier(this.ref) : super(const RideFlowState()) {
    _bindSocketListeners();
    _startOfferPolling();
  }

  void _startOfferPolling() {
    _offerPollTimer?.cancel();
    _offerPollTimer = Timer.periodic(_offerPollInterval, (_) {
      // `syncPendingOffers` already returns immediately when the driver is on a
      // trip or an offer is on screen, so this costs nothing in those states.
      unawaited(syncPendingOffers());
    });
  }

  @override
  void dispose() {
    _offerPollTimer?.cancel();
    _offerPollTimer = null;
    _acceptTimeout?.cancel();
    super.dispose();
  }

  Map<String, dynamic>? _asMap(dynamic data) =>
      data is Map ? Map<String, dynamic>.from(data) : null;

  void _startRingtone() {
    // Respect the driver's own Sound Alerts toggle — otherwise that setting
    // silently does nothing for the one alert that matters most.
    if (!ref.read(settingsProvider).soundAlerts) return;
    unawaited(ref.read(ringtoneServiceProvider).startRideRequestRingtone());
  }

  /// Tracks the last order announced so the socket and the 5s recovery poll
  /// never read the same offer out twice.
  String? _lastAnnouncedRideId;

  /// AI voice mode: reads the new order's amount, pickup and drop aloud in the
  /// driver's selected language, so drivers who can't read the screen still
  /// understand the offer. Gated on the driver's Voice Announce toggle.
  void _announceOffer(RideRequest request) {
    if (!ref.read(settingsProvider).voiceAnnounce) return;
    if (_lastAnnouncedRideId == request.rideId) return;
    _lastAnnouncedRideId = request.rideId;
    final localeCode = ref.read(settingsProvider).languageCode;
    final text = 'voice.new_order'.tr(namedArgs: {
      'amount': request.fare.toStringAsFixed(0),
      'pickup': request.pickupAddress,
      'drop': request.dropAddress,
    });
    unawaited(
      ref.read(voiceAnnounceServiceProvider).announce(text, localeCode: localeCode),
    );
  }

  /// Silences the offer ringtone. Called from every path that ends an offer —
  /// accept, reject, expiry, and server-side withdrawal — so the sound can
  /// never outlive the request card.
  ///
  /// Pass [rideId] when the offer is not (or no longer) in state, as it is when
  /// an accept comes back from the native card on a cold start.
  void _stopRingtone({String? rideId}) {
    unawaited(ref.read(ringtoneServiceProvider).stop());
    // The tray alert must go with it, otherwise a "New ride request" the driver
    // can no longer act on sits there until they swipe it away.
    final id = rideId ?? state.incomingRequest?.rideId;
    if (id != null && id.isNotEmpty) {
      unawaited(
        ref.read(notificationServiceProvider).cancelRideOfferNotification(id),
      );
      // The native full-screen card is posted from Kotlin and outlives Dart
      // state, so it has to be taken down explicitly as well.
      unawaited(RideOfferChannel.dismissOffer(id));
    }
  }

  /// Confirms each trip milestone to the driver as the server acknowledges it.
  void _announceStatus(String liveStatus) {
    switch (liveStatus) {
      case 'accepted':
        SnackbarUtils.success('Ride accepted — head to the pickup');
        break;
      case 'arriving':
        SnackbarUtils.success('Marked as arrived at pickup');
        break;
      case 'started':
        SnackbarUtils.success('Trip started');
        break;
      case 'arrived':
        SnackbarUtils.success('Arrived at the drop location');
        break;
      case 'completed':
        SnackbarUtils.success('Trip completed');
        break;
    }
  }

  void _bindSocketListeners() {
    final socket = ref.read(socketServiceProvider);

    socket.onReconnected = () {
      final ride = state.activeRide;
      if (ride != null) {
        // Room membership does not survive a transport drop, so without this
        // the driver stops receiving status and chat events for a live trip.
        socket.joinRide(ride.id);
        return;
      }
      unawaited(syncPendingOffers());
    };

    void handleRideRequest(dynamic data) {
      final map = _asMap(data);
      if (map == null) return;
      // A driver already on a trip should never be pulled into a second one.
      if (state.activeRide != null) return;
      try {
        final request = RideRequest.fromJson(map);
        // Already answered on the native card: a late re-send must not bring
        // the same offer back up.
        if (_answeredOfferIds.contains(request.rideId)) return;
        // Re-sends of the same offer (later dispatch waves) must not restart
        // the ringtone; the service already ignores that, and this keeps the
        // countdown from being reset underneath the driver.
        final isSameOffer = state.incomingRequest?.rideId == request.rideId;
        state = state.copyWith(
          incomingRequest: request,
          clearAcceptError: true,
        );
        if (!isSameOffer) {
          _startRingtone();
          _announceOffer(request);
          unawaited(AppLauncherService.bringToForeground());
        }
      } catch (error, stackTrace) {
        // A payload this build can't parse must not take the listener down,
        // but it has to leave a trace, or "I never got that ride" can't be
        // looked into.
        developer.log(
          'Dropped a ride request that could not be handled',
          name: 'ride',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    socket.on(SocketEvents.rideRequest, handleRideRequest);
    socket.on('new_ride_request', handleRideRequest);
    socket.on('ride_offer', handleRideRequest);
    socket.on('rideOffer', handleRideRequest);
    socket.on('ride:request', handleRideRequest);

    void handleRequestClosed(dynamic data) {
      final map = _asMap(data);
      final incoming = state.incomingRequest;
      if (incoming == null) return;
      final rideId = (map?['rideId'] ?? map?['_id'] ?? '').toString();
      if (rideId.isNotEmpty && rideId != incoming.rideId) return;
      _stopRingtone();
      state = state.copyWith(clearIncomingRequest: true);
    }

    socket.on(SocketEvents.rideRequestClosed, handleRequestClosed);

    // The server echoes the stored bid back. Until it arrives the driver is
    // still "bidding", which is what keeps a dropped emit visible as such.
    socket.on(SocketEvents.rideBidSubmitted, (data) {
      final map = data is Map
          ? Map<String, dynamic>.from(data)
          : const <String, dynamic>{};
      if (state.incomingRequest?.rideId != map['rideId']?.toString()) return;

      final bid = map['bid'] is Map
          ? Map<String, dynamic>.from(map['bid'] as Map)
          : null;
      state = state.copyWith(
        busy: false,
        submittedBidFare: (bid?['bidFare'] as num?) ?? 0,
      );
    });

    // The rider moved their ceiling. A driver mid-decision needs the new
    // number, because the old one may now be rejected as out of band.
    socket.on(SocketEvents.rideBiddingUpdated, (data) {
      final map = data is Map
          ? Map<String, dynamic>.from(data)
          : const <String, dynamic>{};
      final incoming = state.incomingRequest;
      if (incoming == null || incoming.rideId != map['rideId']?.toString())
        return;

      state = state.copyWith(
        incomingRequest: incoming.copyWithBidBand(
          floor: map['bidFloorFare'] as num?,
          ceiling: map['userMaxBidFare'] as num?,
          step: map['bidStepAmount'] as num?,
        ),
      );
    });
    socket.on('ride_request_closed', handleRequestClosed);
    socket.on('ride:request:closed', handleRequestClosed);

    socket.on(SocketEvents.rideAcceptFailed, (data) {
      final map = _asMap(data);
      _acceptTimeout?.cancel();
      _stopRingtone();
      state = state.copyWith(
        clearIncomingRequest: true,
        acceptError:
            map?['message']?.toString() ?? 'This ride is no longer available',
      );
    });

    socket.on(SocketEvents.rideAccepted, (data) {
      final rideId = _asMap(data)?['rideId']?.toString();
      _acceptTimeout?.cancel();
      _stopRingtone();
      _announceStatus('accepted');
      state = state.copyWith(
        clearIncomingRequest: true,
        clearAcceptError: true,
      );
      if (rideId == null || rideId.isEmpty) return;
      socket.joinRide(rideId);
      // `ride:state` normally lands right behind this with the full trip, but
      // fetching guarantees the active-ride screen has rider/address/OTP data
      // even if that event is missed (e.g. a reconnect mid-accept).
      unawaited(_hydrateActiveRide(rideId));
    });

    socket.on(SocketEvents.rideState, (data) {
      final map = _asMap(data);
      if (map == null) {
        // An unreadable payload means "no data in this emission", not "the trip
        // ended" — dropping the ride here wiped live trips off the driver's
        // screen. Real endings are handled by the cancelled/completed check.
        return;
      }
      final next = RideModel.fromJson(map);
      // Ignore state for a ride we already finished or never took.
      if (next.id.isEmpty) return;
      if (next.status == 'cancelled' || next.status == 'completed') {
        state = state.copyWith(clearActiveRide: true);
        return;
      }
      state = state.copyWith(
        activeRide: next.copyWith(
          messages: next.messages.isEmpty
              ? state.activeRide?.messages
              : next.messages,
        ),
      );
    });

    socket.on(SocketEvents.rideStatusUpdated, (data) {
      final map = _asMap(data);
      final ride = state.activeRide;
      if (map == null || ride == null) return;
      if ((map['rideId'] ?? '').toString() != ride.id) return;

      final nextLiveStatus = map['liveStatus']?.toString();
      // Confirmed by the server, not by the tap. A message shown optimistically
      // on tap tells the driver a transition succeeded even when it was
      // rejected — a wrong start code being the obvious case.
      if (nextLiveStatus != null && nextLiveStatus != ride.liveStatus) {
        _announceStatus(nextLiveStatus);
      }

      state = state.copyWith(
        activeRide: ride.copyWith(
          status: map['status']?.toString(),
          liveStatus: nextLiveStatus,
        ),
      );
    });

    socket.on(SocketEvents.rideCancelled, (data) {
      final map = _asMap(data);
      final ride = state.activeRide;
      if (ride == null) return;
      final rideId = (map?['rideId'] ?? '').toString();
      if (rideId.isNotEmpty && rideId != ride.id) return;
      state = state.copyWith(
        clearActiveRide: true,
        acceptError: map?['reason']?.toString(),
      );
    });

    socket.on(SocketEvents.rideMessageNew, (data) {
      final map = _asMap(data);
      final ride = state.activeRide;
      if (map == null || ride == null) return;
      final message = RideMessage.fromJson(map);
      state = state.copyWith(
        activeRide: ride.copyWith(messages: [...ride.messages, message]),
      );
    });

    // Rejected transitions (wrong pickup OTP, out-of-order status) come back as
    // a generic socket error; without this they would fail silently and the
    // driver would just see nothing happen.
    //
    // Accept refusals carry a `code`. A ride that is gone (taken, cancelled,
    // or never offered to / declined by this driver) closes the offer card so
    // it cannot be tapped again; the accept limit only asks the driver to wait.
    socket.on(SocketEvents.error, (data) {
      final map = _asMap(data);
      final message = map?['message']?.toString();
      final code = map?['code']?.toString();
      _acceptTimeout?.cancel();

      if (code == 'RIDE_UNAVAILABLE' || code == 'RIDE_NOT_OFFERED') {
        _stopRingtone();
        state = state.copyWith(
          busy: false,
          clearIncomingRequest: true,
          acceptError: (message != null && message.isNotEmpty)
              ? message
              : 'This ride is no longer available',
        );
        return;
      }
      if (code == 'RIDE_ACCEPT_RATE_LIMITED') {
        state = state.copyWith(busy: false);
        SnackbarUtils.error('Please wait a moment');
        return;
      }

      state = state.copyWith(busy: false);
      if (message != null && message.isNotEmpty) SnackbarUtils.error(message);
    });
  }

  /// Pulls offers the socket missed while it was down.
  ///
  /// The server marks a driver as notified at dispatch time and will not
  /// re-emit `rideRequest` on reconnect, so an offer dispatched into a dead
  /// socket is only recoverable through this REST path. Called on socket
  /// reconnect and whenever a `ride_request` push arrives.
  Future<void> syncPendingOffers() async {
    // An answer given on the native card may still be sitting in its queue, and
    // the server can keep listing that ride until the accept lands: collect it
    // first so the offer is not shown to the driver a second time.
    await consumeNativeOfferActions();

    // A driver mid-trip is not eligible for a new offer, and an offer already
    // on screen should not be replaced underneath the driver.
    if (state.activeRide != null || state.incomingRequest != null) return;

    try {
      final offers = (await ref.read(rideRepositoryProvider).getPendingOffers())
          .where((o) => !_answeredOfferIds.contains('${o['rideId'] ?? o['_id'] ?? ''}'))
          .toList();
      if (offers.isEmpty) return;
      // State can change while the request is in flight.
      if (state.activeRide != null || state.incomingRequest != null) {
        developer.log(
          '[RideOffer] recovered ${offers.length} offer(s) but one is already on '
          'screen or a trip is running - ignored',
        );
        return;
      }

      // Parsed separately from the state write so a malformed offer is reported
      // rather than silently swallowed by the catch below. A bad field here used
      // to look identical to "no offers", which is what made this invisible.
      final RideRequest request;
      try {
        request = RideRequest.fromJson(offers.first);
      } catch (error, stack) {
        developer.log(
          '[RideOffer] could not parse a recovered offer',
          error: error,
          stackTrace: stack,
        );
        return;
      }

      developer.log(
        '[RideOffer] recovered offer ${request.rideId}, showing the card',
      );
      state = state.copyWith(incomingRequest: request, clearAcceptError: true);
      // An offer recovered after a dropped socket still needs to be heard —
      // this is often the only alert, since the socket event was already lost.
      _startRingtone();
      _announceOffer(request);
      unawaited(AppLauncherService.bringToForeground());
    } catch (error, stack) {
      // Best-effort recovery: the socket remains the primary delivery path, and
      // a failure here must not tear down the ride flow. Logged rather than
      // swallowed, because a silent failure here is indistinguishable from
      // simply having no offers.
      developer.log(
        '[RideOffer] pending-offer sync failed',
        error: error,
        stackTrace: stack,
      );
    }
  }

  /// Re-validates a stuck incoming offer against the server.
  ///
  /// The ringtone and the incoming-request card are only ever cleared by a
  /// message arriving — accept/reject/expiry/`ride_request_closed` — so if
  /// that one message is lost (socket down at the wrong instant, a dropped
  /// push) nothing else was ever watching for it: the card and the ringtone
  /// would sit there indefinitely, surviving even a full app close and
  /// reopen. Foregrounding the app is the moment to ask the server directly
  /// instead of waiting on a message that already failed to arrive once.
  Future<void> reconcileIncomingRequestOnResume() async {
    final incoming = state.incomingRequest;
    if (incoming == null) return;

    try {
      final repository = ref.read(rideRepositoryProvider);
      final activeRide = await repository.getActiveRide();
      if (activeRide != null && activeRide.id == incoming.rideId) {
        // Accepted on another channel (e.g. the native card) and just not
        // adopted into state yet — not stale, let the normal accept path
        // pick it up.
        return;
      }

      final pendingOffers = await repository.getPendingOffers();
      final stillPending = pendingOffers.any(
        (offer) =>
            offer['rideId']?.toString() == incoming.rideId ||
            offer['_id']?.toString() == incoming.rideId,
      );
      if (stillPending) return;

      // State can change while both requests above are in flight — a real
      // accept/reject/close may have landed in the meantime and already
      // cleared (or replaced) the offer this check started on.
      if (state.incomingRequest?.rideId != incoming.rideId) return;

      // The server no longer has this offer for us — it expired, was taken,
      // or was cancelled while we were not listening. Whatever triggered
      // that already told the driver's phone nothing further, so no
      // additional message is coming.
      _stopRingtone(rideId: incoming.rideId);
      state = state.copyWith(clearIncomingRequest: true);
    } catch (error, stack) {
      // Best-effort: if the check itself fails, leave the existing state
      // alone rather than guess.
      developer.log(
        '[RideOffer] resume reconciliation failed',
        error: error,
        stackTrace: stack,
      );
    }
  }

  Future<void> _hydrateActiveRide(String rideId) async {
    try {
      final ride = await ref.read(rideRepositoryProvider).getActiveRide();
      if (ride == null || ride.id != rideId) return;
      if (state.activeRide?.id == rideId) return;
      state = state.copyWith(activeRide: ride);
    } catch (_) {
      // Socket `ride:state` remains the primary path; a failed top-up is not fatal.
    }
  }

  /// Offers the driver's price on a bidding ride.
  ///
  /// The rider chooses between bids, so this does not win the trip - it enters
  /// the running. The card switches to a waiting state on `rideBidSubmitted`
  /// rather than optimistically, so a rejected bid does not look accepted.
  void submitBid(num bidFare) {
    final req = state.incomingRequest;
    if (req == null) return;

    _stopRingtone();
    state = state.copyWith(busy: true, clearAcceptError: true);
    ref.read(socketServiceProvider).submitRideBid(req.rideId, bidFare);
  }

  void acceptIncoming() {
    final req = state.incomingRequest;
    if (req == null) return;
    _stopRingtone();
    state = state.copyWith(busy: true, clearAcceptError: true);
    ref.read(socketServiceProvider).acceptRide(req.rideId);

    _acceptTimeout?.cancel();
    _acceptTimeout = Timer(_acceptAnswerWait, () => unawaited(_resolveUnansweredAccept(req.rideId)));
  }

  /// No answer to an accept: it may still have won, so ask the server before
  /// letting the driver try again.
  Future<void> _resolveUnansweredAccept(String rideId) async {
    if (!state.busy || state.incomingRequest?.rideId != rideId) return;
    if (await _adoptRideIfAlreadyMine(rideId)) return;
    if (state.incomingRequest?.rideId != rideId) return;
    state = state.copyWith(busy: false);
    SnackbarUtils.error('Connection problem - tap Accept again if the offer is still open');
  }

  /// Ride ids currently being accepted, so a repeated drain of the native queue
  /// cannot emit the same accept twice.
  final Set<String> _acceptsInFlight = {};

  /// Offers the driver already accepted or declined on the native card, kept
  /// for this session so no later poll or socket re-send shows them again.
  final Set<String> _answeredOfferIds = {};

  /// Drains answers given on the native full-screen offer card.
  ///
  /// The card is answered with the app backgrounded or killed, so its answers
  /// are queued in Kotlin and collected here — on startup, on resume, and
  /// whenever native says it has queued something new.
  Future<void> consumeNativeOfferActions() async {
    final actions = await RideOfferChannel.consumePendingActions();

    for (final action in actions) {
      _answeredOfferIds.add(action.rideId);
      // Whatever is already on screen for this ride is now answered.
      if (state.incomingRequest?.rideId == action.rideId) {
        _stopRingtone(rideId: action.rideId);
        state = state.copyWith(clearIncomingRequest: true);
      }
      if (action.isAccept) {
        await acceptRideById(action.rideId);
      } else if (action.isReject) {
        rejectRideById(action.rideId);
      }
    }
  }

  /// Accepts an offer known only by its id — the case when the driver tapped
  /// Accept on the native card and there is no offer in state at all.
  Future<void> acceptRideById(String rideId) async {
    if (rideId.isEmpty) return;
    // Already on this trip: the accept landed on an earlier pass.
    if (state.activeRide?.id == rideId) return;
    if (!_acceptsInFlight.add(rideId)) return;

    try {
      _stopRingtone(rideId: rideId);

      // The native card already claimed this ride over REST the moment it was
      // tapped, so the usual case is that it is ours before Dart even wakes.
      // Checking first avoids re-accepting an accepted ride and being told,
      // correctly but confusingly, that it is no longer available.
      //
      // On a cold start (app swiped away, reopened by Accept) the session token
      // and socket are not up yet. The queued answer has already been consumed,
      // so giving up on the first miss lost the accept for good and the driver
      // landed on an empty home screen. Keep trying for a while instead.
      for (var attempt = 0; attempt < 25; attempt++) {
        if (await _adoptRideIfAlreadyMine(rideId)) return;

        final socket = ref.read(socketServiceProvider);
        if (socket.ensureConnected()) {
          await socket.waitUntilConnected();
          // The accept may have landed while the socket was coming up.
          if (await _adoptRideIfAlreadyMine(rideId)) return;

          state = state.copyWith(busy: true, clearAcceptError: true);
          socket.acceptRide(rideId);
          // `rideAccepted` drives navigation from here, exactly as it does for
          // an accept made inside the app.
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 800));
      }
    } finally {
      _acceptsInFlight.remove(rideId);
    }
  }

  /// Picks up a ride the native card already accepted.
  ///
  /// Returns true when this driver's active trip is [rideId] — the ride is then
  /// adopted into state and the trip screen opens, with no second accept sent.
  Future<bool> _adoptRideIfAlreadyMine(String rideId) async {
    try {
      final ride = await ref.read(rideRepositoryProvider).getActiveRide();
      if (ride == null || ride.id != rideId) return false;

      state = state.copyWith(
        activeRide: ride,
        clearIncomingRequest: true,
        clearAcceptError: true,
        busy: false,
      );
      // Room membership is what carries live status and chat for the trip.
      ref.read(socketServiceProvider).joinRide(rideId);
      return true;
    } catch (_) {
      // Unknown — fall through to the socket accept rather than assume either
      // way. A duplicate accept is answered harmlessly by the server.
      return false;
    }
  }

  /// Declines an offer answered on the native card.
  void rejectRideById(String rideId) {
    if (rideId.isEmpty) return;
    _stopRingtone(rideId: rideId);

    final socket = ref.read(socketServiceProvider);
    if (socket.ensureConnected()) {
      socket.rejectRide(rideId);
    }

    if (state.incomingRequest?.rideId == rideId) {
      state = state.copyWith(clearIncomingRequest: true);
    }
  }

  void rejectIncoming() {
    final req = state.incomingRequest;
    if (req == null) return;
    _stopRingtone();
    ref.read(socketServiceProvider).rejectRide(req.rideId);
    state = state.copyWith(clearIncomingRequest: true);
  }

  void clearIncoming() {
    _stopRingtone();
    state = state.copyWith(clearIncomingRequest: true, clearSubmittedBid: true);
  }

  void clearAcceptError() {
    state = state.copyWith(clearAcceptError: true);
  }

  void updateStatus(String nextStatus, {String? paymentMethod, String? otp, String? collectedVia}) {
    final ride = state.activeRide;
    if (ride == null) return;
    ref
        .read(socketServiceProvider)
        .updateRideStatus(
          ride.id,
          nextStatus,
          paymentMethod: paymentMethod,
          otp: otp,
          collectedVia: collectedVia,
        );
  }

  /// Folds the freshly saved handover photos into the active ride.
  ///
  /// The upload answers with both proofs, so the action button re-evaluates its
  /// gate immediately instead of waiting for the next `ride:state` broadcast.
  void applyParcelProof(ParcelInfo proofs) {
    final ride = state.activeRide;
    if (ride == null) return;

    state = state.copyWith(
      activeRide: ride.copyWith(
        parcel: ride.parcel.copyWith(
          pickupProof: proofs.pickupProof,
          deliveryProof: proofs.deliveryProof,
        ),
      ),
    );
  }

  void sendLocation(
    double lat,
    double lng, {
    double? heading,
    double? speed,
    double? accuracy,
    DateTime? timestamp,
  }) {
    final ride = state.activeRide;
    if (ride == null) return;
    _locationSequence += 1;
    ref
        .read(socketServiceProvider)
        .sendRideLocationUpdate(
          ride.id,
          lat,
          lng,
          heading: heading,
          speed: speed,
          accuracy: accuracy,
          timestampMs: (timestamp ?? DateTime.now()).millisecondsSinceEpoch,
          sequence: _locationSequence,
        );
  }

  void sendMessage(String text) {
    final ride = state.activeRide;
    if (ride == null || text.trim().isEmpty) return;
    ref.read(socketServiceProvider).sendRideMessage(ride.id, text.trim());
  }

  /// Sends a chat message carrying an image (e.g. a photo of where the driver
  /// is standing), with an optional text caption.
  void sendImageMessage(String imageUrl, {String text = ''}) {
    final ride = state.activeRide;
    if (ride == null || imageUrl.trim().isEmpty) return;
    ref.read(socketServiceProvider).sendRideMessage(ride.id, text.trim(), imageUrl: imageUrl.trim());
  }

  void completeTripLocally() {
    state = state.copyWith(clearActiveRide: true);
  }

  Future<void> resumeActiveRide() async {
    final ride = await ref.read(rideRepositoryProvider).getActiveRide();
    if (ride == null) return;
    state = state.copyWith(activeRide: ride);
    ref.read(socketServiceProvider).joinRide(ride.id);
  }
}

final rideProvider = StateNotifierProvider<RideNotifier, RideFlowState>((ref) {
  return RideNotifier(ref);
});
