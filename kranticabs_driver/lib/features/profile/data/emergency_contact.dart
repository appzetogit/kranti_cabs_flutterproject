class EmergencyContact {
  final String id;
  final String name;
  final String phone;
  final String source;

  const EmergencyContact({
    required this.id,
    required this.name,
    required this.phone,
    this.source = 'manual',
  });

  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      source: (json['source'] ?? 'manual').toString(),
    );
  }
}
