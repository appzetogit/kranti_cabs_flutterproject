import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import 'models/support_ticket_model.dart';

class SupportRepository {
  final ApiClient api;

  SupportRepository(this.api);

  Future<List<SupportTitleModel>> getTitles() async {
    final data = await api.get(ApiConstants.supportTitles, query: {'userType': 'user'});
    final results = (data['results'] as List? ?? []);
    return results.map((e) => SupportTitleModel.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<List<SupportTicketModel>> getMyTickets() async {
    final data = await api.get(ApiConstants.myTickets);
    final results = (data['results'] as List? ?? []);
    return results.map((e) => SupportTicketModel.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<SupportTicketModel> getTicketDetail(String ticketCode) async {
    final data = await api.get('${ApiConstants.supportTickets}/$ticketCode');
    return SupportTicketModel.fromJson(Map<String, dynamic>.from(data));
  }

  Future<SupportTicketModel> createTicket({String? titleId, String? title, required String message}) async {
    final data = await api.post(ApiConstants.supportTickets, data: {
      if (titleId != null) 'titleId': titleId,
      if (title != null) 'title': title,
      'message': message,
    });
    return SupportTicketModel.fromJson(Map<String, dynamic>.from(data));
  }

  Future<SupportTicketModel> replyToTicket(String ticketCode, String message) async {
    final data = await api.post('${ApiConstants.supportTickets}/$ticketCode/reply', data: {'message': message});
    return SupportTicketModel.fromJson(Map<String, dynamic>.from(data));
  }

  /// [emergencyContacts] go with the alert so the safety team can call them
  /// straight away - each `{name, phone, relation}`.
  Future<void> triggerSos({
    String? rideId,
    required double lat,
    required double lng,
    String? notes,
    List<Map<String, String>> emergencyContacts = const [],
  }) {
    return api.post(ApiConstants.sos, data: {
      if (rideId != null) 'rideId': rideId,
      'serviceType': 'ride',
      'location': {'lat': lat, 'lng': lng},
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      if (emergencyContacts.isNotEmpty) 'emergencyContacts': emergencyContacts,
    });
  }

  /// The contacts saved on the rider's profile on the server.
  Future<List<Map<String, dynamic>>> getEmergencyContacts() async {
    final data = await api.get(ApiConstants.emergencyContacts);
    final list = (data is Map ? data['contacts'] : null) as List? ?? const [];
    return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Replaces the contacts saved on the server with [contacts].
  Future<void> saveEmergencyContacts(List<Map<String, String>> contacts) {
    return api.patch(ApiConstants.emergencyContacts, data: {'contacts': contacts});
  }
}
