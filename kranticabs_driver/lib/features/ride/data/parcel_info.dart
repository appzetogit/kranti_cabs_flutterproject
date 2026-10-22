import '../../../core/utils/json_safe.dart';

/// One of the driver's two handover photos.
///
/// The server refuses to start a parcel trip without [ParcelInfo.pickupProof]
/// and refuses to complete one without [ParcelInfo.deliveryProof], so these
/// also decide which action button the driver is allowed to press.
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

/// Everything the sender declared about the parcel, plus the driver's own
/// handover photos.
///
/// Carried on both the incoming offer and the active ride, so a driver can see
/// what they are being asked to carry *before* accepting rather than finding
/// out at the pickup.
class ParcelInfo {
  /// The material, from the admin's goods-type catalog.
  final String category;

  /// Roughly how heavy, as the sender described it ('5 - 10 kg').
  final String weight;

  /// The sender's own words about the contents.
  final String description;

  /// Handling notes: fragile, keep upright, call before arriving.
  final String instructions;

  /// Photos the sender took at booking, at most two.
  final List<String> photos;

  final String senderName;
  final String senderMobile;
  final String receiverName;
  final String receiverMobile;

  final ParcelProof pickupProof;
  final ParcelProof deliveryProof;

  const ParcelInfo({
    this.category = '',
    this.weight = '',
    this.description = '',
    this.instructions = '',
    this.photos = const [],
    this.senderName = '',
    this.senderMobile = '',
    this.receiverName = '',
    this.receiverMobile = '',
    this.pickupProof = const ParcelProof(),
    this.deliveryProof = const ParcelProof(),
  });

  /// Whether there is anything worth rendering. An ordinary ride carries an
  /// empty parcel block rather than none at all, so screens check this instead
  /// of a null.
  bool get isEmpty =>
      category.isEmpty &&
      weight.isEmpty &&
      description.isEmpty &&
      instructions.isEmpty &&
      photos.isEmpty &&
      receiverName.isEmpty;

  bool get isNotEmpty => !isEmpty;

  /// The best single label for what is being carried: what the sender typed,
  /// falling back to the catalog material.
  String get title => description.isNotEmpty ? description : category;

  static const ParcelInfo none = ParcelInfo();

  factory ParcelInfo.fromJson(dynamic json) {
    final map = asMap(json);

    return ParcelInfo(
      category: asText(map['category']),
      weight: asText(map['weight']),
      description: asText(map['description']),
      instructions: asText(map['instructions']),
      photos: asList(map['photos'])
          .map((entry) => asText(entry))
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false),
      senderName: asText(map['senderName']),
      senderMobile: asText(map['senderMobile']),
      receiverName: asText(map['receiverName']),
      receiverMobile: asText(map['receiverMobile']),
      pickupProof: ParcelProof.fromJson(map['pickupProof']),
      deliveryProof: ParcelProof.fromJson(map['deliveryProof']),
    );
  }

  ParcelInfo copyWith({ParcelProof? pickupProof, ParcelProof? deliveryProof}) {
    return ParcelInfo(
      category: category,
      weight: weight,
      description: description,
      instructions: instructions,
      photos: photos,
      senderName: senderName,
      senderMobile: senderMobile,
      receiverName: receiverName,
      receiverMobile: receiverMobile,
      pickupProof: pickupProof ?? this.pickupProof,
      deliveryProof: deliveryProof ?? this.deliveryProof,
    );
  }
}
