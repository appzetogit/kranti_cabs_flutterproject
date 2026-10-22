class DocumentTemplate {
  final String key;
  final String name;
  final bool hasExpiryDate;
  final bool hasIdentifyNumber;
  final String imageType;
  final bool isRequired;

  const DocumentTemplate({
    required this.key,
    required this.name,
    required this.hasExpiryDate,
    required this.hasIdentifyNumber,
    required this.imageType,
    this.isRequired = true,
  });

  factory DocumentTemplate.fromJson(Map<String, dynamic> json) {
    return DocumentTemplate(
      key: (json['key'] ?? json['field_key'] ?? '').toString(),
      name: (json['label'] ?? json['name'] ?? json['template_name'] ?? '').toString(),
      hasExpiryDate: json['has_expiry_date'] == true,
      hasIdentifyNumber: json['has_identify_number'] == true,
      imageType: (json['image_type'] ?? 'single').toString(),
      isRequired: json['is_required'] != false,
    );
  }

  factory DocumentTemplate.fromField(Map<String, dynamic> group, Map<String, dynamic> field) {
    final side = (field['side'] ?? 'single').toString();
    return DocumentTemplate(
      key: (field['key'] ?? '').toString(),
      name: (field['label'] ?? group['name'] ?? '').toString(),
      hasExpiryDate: side != 'back' && group['has_expiry_date'] == true,
      hasIdentifyNumber: side != 'back' && group['has_identify_number'] == true,
      imageType: side,
      isRequired: field['is_required'] != false && group['is_required'] != false,
    );
  }
}

class ServiceLocationOption {
  final String id;
  final String name;

  const ServiceLocationOption({required this.id, required this.name});

  factory ServiceLocationOption.fromJson(Map<String, dynamic> json) {
    return ServiceLocationOption(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      name: (json['service_location_name'] ?? json['name'] ?? '').toString(),
    );
  }
}

class VehicleTypeOption {
  final String id;
  final String name;

  /// Generic family ('bike' | 'car' | 'auto') the tier belongs to — drives the
  /// icon shown in the picker.
  final String iconType;

  /// 'taxi' or 'delivery' - which side of the catalog this tier belongs to.
  ///
  /// The two sides hold near-identical names (there is a 'Kranti Scooty Parcel'
  /// filed under taxi and a 'Kranti Scooty Parcel' filed under delivery), and
  /// dispatch matches on the id, not the name. Registering on the wrong one
  /// leaves a driver invisible to every booking for that vehicle, so the picker
  /// filters on this rather than offering both.
  final String transportType;

  const VehicleTypeOption({
    required this.id,
    required this.name,
    required this.iconType,
    this.transportType = 'taxi',
  });

  factory VehicleTypeOption.fromJson(Map<String, dynamic> json) {
    final category = (json['category'] ?? '').toString().trim();
    final iconTypes = (json['icon_types'] ?? '').toString().trim();
    return VehicleTypeOption(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      iconType: (category.isNotEmpty ? category : iconTypes).toLowerCase(),
      transportType: (json['transport_type'] ?? json['transportType'] ?? 'taxi')
          .toString()
          .trim()
          .toLowerCase(),
    );
  }
}

class VehicleFieldTemplate {
  final String fieldKey;
  final String name;
  final String fieldType;
  final List<String> options;
  final bool isRequired;

  const VehicleFieldTemplate({
    required this.fieldKey,
    required this.name,
    required this.fieldType,
    required this.options,
    required this.isRequired,
  });

  factory VehicleFieldTemplate.fromJson(Map<String, dynamic> json) {
    return VehicleFieldTemplate(
      fieldKey: (json['field_key'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      fieldType: (json['field_type'] ?? 'text').toString(),
      options: (json['options'] as List? ?? []).map((e) => e.toString()).toList(),
      isRequired: json['is_required'] == true,
    );
  }
}
