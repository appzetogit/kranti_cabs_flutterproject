import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json_safe.dart';
import 'support_models.dart';

class SupportRepository {
  final ApiClient _api;

  SupportRepository(this._api);

  Future<List<DriverNotification>> getNotifications() async {
    final data = await _api.get(ApiConstants.notifications);
    return asResults(data).map(DriverNotification.fromJson).toList();
  }

  Future<List<SupportTitle>> getSupportTitles() async {
    final data = await _api.get(ApiConstants.supportTitles);
    return asResults(data).map(SupportTitle.fromJson).toList();
  }

  Future<SupportTicket> createTicket({String? titleId, String? title, required String message}) async {
    final data = await _api.post(ApiConstants.supportTickets, data: {
      if (titleId != null) 'titleId': titleId,
      if (title != null) 'title': title,
      'message': message,
    });
    return SupportTicket.fromJson(asMap(data));
  }

  Future<List<SupportTicket>> listMyTickets({String? status, int page = 1, int limit = 20}) async {
    final data = await _api.get(ApiConstants.myTickets, query: {
      if (status != null) 'status': status,
      'page': page,
      'limit': limit,
    });
    return asResults(data).map(SupportTicket.fromJson).toList();
  }

  Future<SupportTicket> getTicket(String ticketCode) async {
    final data = await _api.get(ApiConstants.supportTicket(ticketCode));
    return SupportTicket.fromJson(asMap(data));
  }

  Future<SupportTicket> replyTicket(String ticketCode, String message) async {
    final data = await _api.post(ApiConstants.supportTicketReply(ticketCode), data: {'message': message});
    return SupportTicket.fromJson(asMap(data));
  }
}
