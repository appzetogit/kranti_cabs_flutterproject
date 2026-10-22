import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/utils/json_safe.dart';
import '../data/models/ride_bid_model.dart';
import '../data/models/ride_model.dart';
import 'ride_providers.dart';

/// Live state of one bidding ride: the band the rider set, and what drivers
/// have offered inside it.
class RideBidsState {
  final RideModel? ride;
  final List<RideBidModel> bids;

  /// The negotiation band. Kept beside [ride] because socket updates carry it
  /// on its own, without a full ride payload.
  final RideBiddingInfo bidding;

  final bool loading;

  /// Id of the bid currently being accepted, so only that row shows a spinner.
  final String? acceptingBidId;

  final bool raising;
  final String? error;

  const RideBidsState({
    this.ride,
    this.bids = const [],
    this.bidding = RideBiddingInfo.none,
    this.loading = true,
    this.acceptingBidId,
    this.raising = false,
    this.error,
  });

  /// Only pending bids can be acted on; the rest are history.
  List<RideBidModel> get pendingBids =>
      bids.where((bid) => bid.isPending).toList(growable: false);

  RideBidModel? get cheapest {
    final pending = pendingBids;
    return pending.isEmpty ? null : pending.first;
  }

  RideBidsState copyWith({
    RideModel? ride,
    List<RideBidModel>? bids,
    RideBiddingInfo? bidding,
    bool? loading,
    String? acceptingBidId,
    bool clearAccepting = false,
    bool? raising,
    String? error,
    bool clearError = false,
  }) {
    return RideBidsState(
      ride: ride ?? this.ride,
      bids: bids ?? this.bids,
      bidding: bidding ?? this.bidding,
      loading: loading ?? this.loading,
      acceptingBidId: clearAccepting ? null : (acceptingBidId ?? this.acceptingBidId),
      raising: raising ?? this.raising,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Drives the bids screen for one ride.
///
/// Bids arrive over the socket as drivers place them, but the socket is not
/// trusted as the only source: a rider who opens this screen after a
/// reconnection would otherwise see an empty list while bids already exist, so
/// the REST list is fetched once on open and the socket layers onto it.
class RideBidsController extends StateNotifier<RideBidsState> {
  final Ref ref;
  final String rideId;

  late final SocketService _socket;

  RideBidsController(this.ref, this.rideId) : super(const RideBidsState()) {
    _socket = ref.read(socketServiceProvider);
    _socket.on('rideBidUpdated', _onBidUpdated);
    _socket.on('rideBiddingUpdated', _onBiddingUpdated);
    load();
  }

  Future<void> load() async {
    try {
      final result = await ref.read(rideRepositoryProvider).getRideBids(rideId);
      if (!mounted) return;

      state = state.copyWith(
        ride: result.ride,
        bids: _sorted(result.bids),
        bidding: result.ride.bidding,
        loading: false,
        clearError: true,
      );
    } on ApiException catch (error) {
      if (mounted) state = state.copyWith(loading: false, error: error.message);
    } catch (error) {
      if (mounted) state = state.copyWith(loading: false, error: error.toString());
    }
  }

  /// A driver placed or changed a bid. The payload carries the whole band plus
  /// the one bid that moved, so both are folded in together.
  void _onBidUpdated(dynamic payload) {
    final map = asMap(payload);
    if (asText(map['rideId']) != rideId) return;

    final incoming = map['bid'] == null ? null : RideBidModel.fromJson(map['bid']);
    final next = List<RideBidModel>.from(state.bids);

    if (incoming != null) {
      // One bid per driver server-side, so a repeat replaces rather than adds.
      final existing = next.indexWhere((bid) => bid.driverId == incoming.driverId);
      if (existing >= 0) {
        next[existing] = incoming;
      } else {
        next.add(incoming);
      }
    }

    state = state.copyWith(bids: _sorted(next), bidding: RideBiddingInfo.fromJson(map));
  }

  /// The band itself changed — usually the rider raising their own ceiling.
  void _onBiddingUpdated(dynamic payload) {
    final map = asMap(payload);
    if (asText(map['rideId']) != rideId) return;

    state = state.copyWith(bidding: RideBiddingInfo.fromJson(map));
  }

  /// Cheapest first: the rider is choosing on price, and a driver who undercut
  /// the quote should not be buried under one who did not.
  List<RideBidModel> _sorted(List<RideBidModel> bids) {
    final next = List<RideBidModel>.from(bids)
      ..sort((left, right) => left.bidFare.compareTo(right.bidFare));
    return List<RideBidModel>.unmodifiable(next);
  }

  /// Raises the ceiling drivers may bid up to, by one step.
  Future<void> raiseCeiling() async {
    if (state.raising) return;
    state = state.copyWith(raising: true, clearError: true);

    try {
      final ride = await ref.read(rideRepositoryProvider).raiseFare(rideId);
      if (!mounted) return;
      state = state.copyWith(ride: ride, bidding: ride.bidding, raising: false);
    } on ApiException catch (error) {
      if (mounted) state = state.copyWith(raising: false, error: error.message);
    } catch (error) {
      if (mounted) state = state.copyWith(raising: false, error: error.toString());
    }
  }

  /// Awards the ride to one driver. Returns true once the ride is theirs.
  ///
  /// A failure here is usually a race — the driver took another trip, or went
  /// offline between placing the bid and this tap — so the list is reloaded
  /// rather than left showing an option that no longer exists.
  Future<bool> acceptBid(String bidId) async {
    if (state.acceptingBidId != null) return false;
    state = state.copyWith(acceptingBidId: bidId, clearError: true);

    try {
      final ride = await ref.read(rideRepositoryProvider).acceptBid(rideId: rideId, bidId: bidId);
      if (!mounted) return true;
      state = state.copyWith(ride: ride, bidding: ride.bidding, clearAccepting: true);
      return true;
    } on ApiException catch (error) {
      if (mounted) {
        state = state.copyWith(clearAccepting: true, error: error.message);
        await load();
      }
      return false;
    } catch (error) {
      if (mounted) {
        state = state.copyWith(clearAccepting: true, error: error.toString());
        await load();
      }
      return false;
    }
  }

  void clearError() => state = state.copyWith(clearError: true);

  @override
  void dispose() {
    _socket.off('rideBidUpdated', _onBidUpdated);
    _socket.off('rideBiddingUpdated', _onBiddingUpdated);
    super.dispose();
  }
}

final rideBidsControllerProvider =
    StateNotifierProvider.autoDispose.family<RideBidsController, RideBidsState, String>(
  (ref, rideId) => RideBidsController(ref, rideId),
);
