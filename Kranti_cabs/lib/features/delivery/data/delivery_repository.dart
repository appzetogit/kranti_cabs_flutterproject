import 'dart:convert';
import 'dart:io';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json_safe.dart';
import 'models/delivery_model.dart';
import 'models/goods_type_model.dart';
import 'models/parcel_model.dart';

/// Fare breakdown returned by `POST /deliveries/quote`.
class DeliveryQuote {
  final String vehicleTypeId;
  final String vehicleName;
  final double distanceKm;
  final double baseDistanceKm;
  final double subtotal;
  final double serviceTaxPercentage;
  final double serviceTaxAmount;
  final double total;

  const DeliveryQuote({
    required this.vehicleTypeId,
    required this.vehicleName,
    required this.distanceKm,
    required this.baseDistanceKm,
    required this.subtotal,
    required this.serviceTaxPercentage,
    required this.serviceTaxAmount,
    required this.total,
  });

  static double _d(dynamic v) => double.tryParse('${v ?? 0}') ?? 0;

  factory DeliveryQuote.fromJson(Map<String, dynamic> json) {
    return DeliveryQuote(
      vehicleTypeId: (json['vehicleTypeId'] ?? '').toString(),
      vehicleName: (json['vehicleName'] ?? '').toString(),
      distanceKm: _d(json['distanceKm']),
      baseDistanceKm: _d(json['baseDistanceKm']),
      subtotal: _d(json['subtotal']),
      serviceTaxPercentage: _d(json['serviceTaxPercentage']),
      serviceTaxAmount: _d(json['serviceTaxAmount']),
      total: _d(json['total']),
    );
  }
}

class DeliveryRepository {
  final ApiClient api;

  DeliveryRepository(this.api);

  Future<DeliveryModel> createDelivery({
    required List<double> pickup,
    required List<double> drop,
    required String pickupAddress,
    required String dropAddress,
    required double fare,
    required String vehicleTypeId,
    required ParcelModel parcel,
    String paymentMethod = 'cash',
  }) async {
    final data = await api.post(ApiConstants.deliveries, data: {
      'pickup': pickup,
      'drop': drop,
      'pickupAddress': pickupAddress,
      'dropAddress': dropAddress,
      'fare': fare,
      'vehicleTypeId': vehicleTypeId,
      'paymentMethod': paymentMethod,
      'parcel': parcel.toJson(),
    });
    return DeliveryModel.fromJson(Map<String, dynamic>.from(data));
  }

  /// Server-computed fare for a pickup/drop pair.
  ///
  /// Runs the same breakdown the booking uses, so the quoted price is exactly
  /// what gets charged — the app never recomputes pricing locally.
  Future<DeliveryQuote> getQuote({
    required String vehicleTypeId,
    required List<double> pickup,
    required List<double> drop,
    String? category,
  }) async {
    final data = await api.post('${ApiConstants.deliveries}/quote', data: {
      'vehicleTypeId': vehicleTypeId,
      'pickup': pickup,
      'drop': drop,
      if (category != null && category.isNotEmpty) 'parcel': {'category': category},
    });
    return DeliveryQuote.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<DeliveryModel?> getActiveDelivery() async {
    final data = await api.get('${ApiConstants.deliveries}/active/me');
    if (data == null) return null;
    return DeliveryModel.fromJson(Map<String, dynamic>.from(data));
  }

  Future<DeliveryModel> getDeliveryDetail(String deliveryId) async {
    final data = await api.get('${ApiConstants.deliveries}/$deliveryId');
    return DeliveryModel.fromJson(Map<String, dynamic>.from(data));
  }

  /// Parcel materials the admin has listed.
  ///
  /// Returns an empty list rather than throwing when the catalog has not been
  /// filled in yet - the details screen falls back to a free-text field, so a
  /// missing catalog delays no one.
  Future<List<GoodsTypeModel>> listGoodsTypes() async {
    final data = await api.get(ApiConstants.goodsTypes);
    return asResults(data)
        .map(GoodsTypeModel.fromJson)
        .where((type) => type.name.isNotEmpty)
        .toList(growable: false);
  }

  /// Uploads one parcel photo and returns its hosted URL.
  ///
  /// Sends a data URL because that is what `/common/upload/image` accepts, and
  /// it keeps this on the same JSON client as every other call rather than
  /// needing a multipart path of its own.
  Future<String> uploadParcelPhoto(File file) async {
    final bytes = await file.readAsBytes();
    final data = await api.post(
      ApiConstants.uploadImage,
      data: {
        'image': 'data:image/jpeg;base64,${base64Encode(bytes)}',
        'folder': 'parcels',
      },
    );
    final result = asMap(data);
    final url = asText(result['url']);
    return url.isNotEmpty ? url : asText(result['secureUrl']);
  }

  Future<List<DeliveryModel>> listMyDeliveries() async {
    final data = await api.get(ApiConstants.deliveries);
    final results = (data['results'] as List? ?? []);
    return results.map((e) => DeliveryModel.fromJson(Map<String, dynamic>.from(e))).toList();
  }
}
