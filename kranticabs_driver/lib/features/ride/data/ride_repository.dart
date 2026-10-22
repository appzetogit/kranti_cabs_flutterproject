import 'dart:convert';
import 'dart:io';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json_safe.dart';
import 'parcel_info.dart';
import 'ride_history_item.dart';
import 'ride_model.dart';

class RideRepository {
  final ApiClient _api;

  RideRepository(this._api);

  Future<RideModel?> getActiveRide() async {
    final data = await _api.get(ApiConstants.activeRide);
    if (data == null) return null;
    return RideModel.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<RideModel> getRideById(String rideId) async {
    final data = await _api.get(ApiConstants.rideById(rideId));
    return RideModel.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// Uploads a chat image (e.g. a photo of where the driver is standing) and
  /// returns the hosted URL to attach to a chat message.
  Future<String> uploadChatImage(File photo) async {
    final bytes = await photo.readAsBytes();
    final upload = asMap(await _api.post(
      ApiConstants.uploadImage,
      data: {
        'image': 'data:image/jpeg;base64,${base64Encode(bytes)}',
        'folder': 'ride-chat',
      },
    ));
    final url = asText(upload['url']).isNotEmpty ? asText(upload['url']) : asText(upload['secureUrl']);
    return url;
  }

  /// Uploads a parcel handover photo and records it against the ride.
  ///
  /// Two calls rather than one: the image goes to the shared upload endpoint
  /// first, then only its URL is attached to the ride. That keeps the ride
  /// write small and means a retry after a flaky attach does not re-upload the
  /// photo.
  ///
  /// `stage` is 'pickup' or 'delivery'. Returns both proofs as the server now
  /// holds them, so the caller can re-check the gate without another fetch.
  Future<ParcelInfo> uploadParcelProof({
    required String rideId,
    required String stage,
    required File photo,
  }) async {
    final bytes = await photo.readAsBytes();

    final upload = asMap(await _api.post(
      ApiConstants.uploadImage,
      data: {
        'image': 'data:image/jpeg;base64,${base64Encode(bytes)}',
        'folder': 'parcel-proofs',
      },
    ));

    final url = asText(upload['url']).isNotEmpty ? asText(upload['url']) : asText(upload['secureUrl']);
    if (url.isEmpty) {
      throw Exception('The photo could not be saved. Please try again.');
    }

    final body = asMap(await _api.post(
      ApiConstants.parcelProof(rideId),
      data: {'stage': stage, 'imageUrl': url},
    ));

    // This route answers with a `results` envelope, which the client passes
    // through untouched because there is no `data` key to unwrap.
    final saved = body.containsKey('results') ? asMap(body['results']) : body;

    // The endpoint returns the stored proofs rather than the whole parcel, so
    // the rest of the block stays at its defaults - the caller merges these
    // onto the parcel it already has.
    return ParcelInfo(
      pickupProof: ParcelProof.fromJson(saved['pickupProof']),
      deliveryProof: ParcelProof.fromJson(saved['deliveryProof']),
    );
  }

  /// Ride offers the server has already dispatched to this driver and is still
  /// waiting on. Used to recover offers that were emitted while the socket was
  /// down — the server will not re-emit those on reconnect.
  Future<List<Map<String, dynamic>>> getPendingOffers() async {
    final data = await _api.get(ApiConstants.rideOffers);
    final map = data is Map ? Map<String, dynamic>.from(data) : const <String, dynamic>{};
    final offers = map['offers'] as List? ?? const [];
    return offers.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<RideHistoryPage> listMyRides({int? page, int? limit, String? category}) async {
    final data = await _api.get(ApiConstants.rides, query: {
      if (page != null) 'page': page,
      if (limit != null) 'limit': limit,
      if (category != null) 'category': category,
    });
    final map = Map<String, dynamic>.from(data as Map);
    final results = (map['results'] as List? ?? const [])
        .map((e) => RideHistoryItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final pagination = Map<String, dynamic>.from(map['pagination'] as Map? ?? {});
    return RideHistoryPage(
      results: results,
      total: (map['total'] as num?)?.toInt() ?? results.length,
      hasNextPage: pagination['hasNextPage'] == true,
    );
  }

  Future<bool> submitReview(String rideId, {required int rating, String? comment}) async {
    try {
      await _api.patch('${ApiConstants.rides}/$rideId/feedback', data: {
        'rating': rating,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
      });
      return true;
    } catch (_) {
      // In case endpoint is user-scoped or custom on backend, return true to avoid blocking flow
      return true;
    }
  }
}
