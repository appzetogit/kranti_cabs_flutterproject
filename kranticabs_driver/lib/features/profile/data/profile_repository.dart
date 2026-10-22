import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import 'emergency_contact.dart';

class ProfileRepository {
  final ApiClient _api;

  ProfileRepository(this._api);

  Future<void> updateProfile({String? name, String? email, String? profileImage}) {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (email != null) data['email'] = email;
    if (profileImage != null) data['profileImage'] = profileImage;
    return _api.patch(ApiConstants.me, data: data);
  }

  Future<Map<String, dynamic>> updateVehicle({
    String? vehicleTypeId,
    String? vehicleNumber,
    String? vehicleColor,
    String? vehicleMake,
    String? vehicleModel,
    String? vehicleImage,
  }) async {
    final data = <String, dynamic>{
      if (vehicleTypeId != null) 'vehicleTypeId': vehicleTypeId,
      if (vehicleNumber != null) 'vehicleNumber': vehicleNumber,
      if (vehicleColor != null) 'vehicleColor': vehicleColor,
      if (vehicleMake != null) 'vehicleMake': vehicleMake,
      if (vehicleModel != null) 'vehicleModel': vehicleModel,
      if (vehicleImage != null) 'vehicleImage': vehicleImage,
    };
    final result = await _api.patch(ApiConstants.vehicle, data: data);
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> uploadDocument(String documentKey, Map<String, dynamic> document) {
    return _api.patch(ApiConstants.document(documentKey), data: {'document': document});
  }

  /// Driver's own static payment UPI/QR shown to riders at ride-end.
  Future<Map<String, dynamic>> getPaymentUpi() async {
    final data = await _api.get(ApiConstants.paymentUpi);
    return Map<String, dynamic>.from(data as Map);
  }

  /// [qrImage] is an optional `data:image/...;base64,...` data URL; pass null to
  /// keep the existing image. Returns the saved {upiId, qrCodeImage, verificationStatus}.
  Future<Map<String, dynamic>> savePaymentUpi({required String upiId, String? qrImage}) async {
    final data = await _api.patch(ApiConstants.paymentUpi, data: {
      'upiId': upiId,
      if (qrImage != null) 'qrImage': qrImage,
    });
    return Map<String, dynamic>.from(data as Map);
  }

  List<EmergencyContact> _parseContacts(dynamic data) {
    final map = Map<String, dynamic>.from(data as Map);
    final results = (map['results'] as List?) ?? const [];
    return results
        .map((e) => EmergencyContact.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<EmergencyContact>> getEmergencyContacts() async {
    final data = await _api.get(ApiConstants.emergencyContacts);
    return _parseContacts(data);
  }

  Future<List<EmergencyContact>> addEmergencyContact({required String name, required String phone}) async {
    final data = await _api.post(ApiConstants.emergencyContacts, data: {'name': name, 'phone': phone});
    return _parseContacts(data);
  }

  Future<List<EmergencyContact>> deleteEmergencyContact(String contactId) async {
    final data = await _api.delete(ApiConstants.emergencyContact(contactId));
    return _parseContacts(data);
  }

  Future<void> triggerSos({required double lat, required double lng, String? rideId, String? notes}) {
    return _api.post(ApiConstants.sos, data: {
      'location': [lng, lat],
      if (rideId != null) 'rideId': rideId,
      if (notes != null) 'notes': notes,
    });
  }

  Future<void> requestAccountDeletion(String reason) {
    return _api.post(ApiConstants.deleteRequest, data: {'reason': reason});
  }
}
