import '../../../../core/utils/json_safe.dart';

/// A photo the driver took to prove they handled the parcel.
///
/// Two of these exist per delivery — one at collection, one at hand-over — and
/// the server refuses to start or complete the trip until the matching one is
/// present.
class ParcelProof {
  final String url;
  final DateTime? at;

  const ParcelProof({this.url = '', this.at});

  bool get exists => url.isNotEmpty;

  factory ParcelProof.fromJson(dynamic json) {
    final map = asMap(json);
    return ParcelProof(
      url: asText(map['url']),
      at: DateTime.tryParse(asText(map['at']))?.toLocal(),
    );
  }
}

class ParcelModel {
  final String category;
  final String weight;
  final String description;
  final String senderName;
  final String senderMobile;
  final String receiverName;
  final String receiverMobile;
  final bool isOutstation;

  /// Photos of the parcel taken by the sender when booking, at most two.
  final List<String> photos;

  /// Handling notes from the sender ("fragile", "call before arriving").
  final String instructions;

  /// Driver's proof photos. Read-only from the sender's side — they are written
  /// by the driver app and arrive with the ride state.
  final ParcelProof pickupProof;
  final ParcelProof deliveryProof;

  const ParcelModel({
    this.category = '',
    this.weight = '',
    this.description = '',
    this.senderName = '',
    this.senderMobile = '',
    this.receiverName = '',
    this.receiverMobile = '',
    this.isOutstation = false,
    this.photos = const [],
    this.instructions = '',
    this.pickupProof = const ParcelProof(),
    this.deliveryProof = const ParcelProof(),
  });

  factory ParcelModel.fromJson(Map<String, dynamic> json) {
    return ParcelModel(
      category: asText(json['category']),
      weight: asText(json['weight']),
      description: asText(json['description']),
      senderName: asText(json['senderName']),
      senderMobile: asText(json['senderMobile']),
      receiverName: asText(json['receiverName']),
      receiverMobile: asText(json['receiverMobile']),
      isOutstation: json['isOutstation'] == true,
      photos: asList(json['photos'])
          .map((entry) => asText(entry))
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false),
      instructions: asText(json['instructions']),
      pickupProof: ParcelProof.fromJson(json['pickupProof']),
      deliveryProof: ParcelProof.fromJson(json['deliveryProof']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'category': category,
      'weight': weight,
      'description': description,
      'deliveryCategory': category,
      'deliveryScope': isOutstation ? 'outstation' : 'city',
      'isOutstation': isOutstation,
      'senderName': senderName,
      'senderMobile': senderMobile,
      'receiverName': receiverName,
      'receiverMobile': receiverMobile,
      'photos': photos,
      'instructions': instructions,
      // Proofs are deliberately not sent. They belong to the driver, and the
      // server ignores them on this route anyway.
    };
  }
}
