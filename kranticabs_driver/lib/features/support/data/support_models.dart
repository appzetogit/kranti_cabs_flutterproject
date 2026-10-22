import '../../../core/utils/json_safe.dart';
class DriverNotification {
  final String id;
  final String title;
  final String body;
  final String image;
  final String sendTo;
  final String serviceLocationName;
  final DateTime? sentAt;
  final DateTime? createdAt;

  const DriverNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.image,
    required this.sendTo,
    required this.serviceLocationName,
    this.sentAt,
    this.createdAt,
  });

  factory DriverNotification.fromJson(Map<String, dynamic> json) {
    return DriverNotification(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      image: json['image']?.toString() ?? '',
      sendTo: json['sendTo']?.toString() ?? 'all',
      serviceLocationName: json['serviceLocationName']?.toString() ?? '',
      sentAt: DateTime.tryParse(json['sentAt']?.toString() ?? ''),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
    );
  }
}

class SupportTitle {
  final String id;
  final String title;
  final String userType;
  final String supportType;
  final bool active;

  const SupportTitle({
    required this.id,
    required this.title,
    required this.userType,
    required this.supportType,
    required this.active,
  });

  factory SupportTitle.fromJson(Map<String, dynamic> json) {
    return SupportTitle(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      userType: json['userType']?.toString() ?? '',
      supportType: json['supportType']?.toString() ?? 'general',
      active: json['active'] == true,
    );
  }
}

class SupportTicketMessage {
  final String id;
  final String senderRole;
  final String senderId;
  final String senderName;
  final String message;
  final DateTime? createdAt;

  const SupportTicketMessage({
    required this.id,
    required this.senderRole,
    required this.senderId,
    required this.senderName,
    required this.message,
    this.createdAt,
  });

  factory SupportTicketMessage.fromJson(Map<String, dynamic> json) {
    return SupportTicketMessage(
      id: json['id']?.toString() ?? '',
      senderRole: json['senderRole']?.toString() ?? '',
      senderId: json['senderId']?.toString() ?? '',
      senderName: json['senderName']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
    );
  }
}

class SupportTicket {
  final String id;
  final String ticketCode;
  final String? titleId;
  final String title;
  final String userType;
  final String supportType;
  final String requesterRole;
  final String requesterId;
  final String requesterName;
  final String requesterPhone;
  final String serviceLocation;
  final String status;
  final String? assignedAdminId;
  final String assignedAdminName;
  final List<SupportTicketMessage> messages;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastMessageAt;

  const SupportTicket({
    required this.id,
    required this.ticketCode,
    this.titleId,
    required this.title,
    required this.userType,
    required this.supportType,
    required this.requesterRole,
    required this.requesterId,
    required this.requesterName,
    required this.requesterPhone,
    required this.serviceLocation,
    required this.status,
    this.assignedAdminId,
    required this.assignedAdminName,
    required this.messages,
    this.createdAt,
    this.updatedAt,
    this.lastMessageAt,
  });

  factory SupportTicket.fromJson(Map<String, dynamic> json) {
    return SupportTicket(
      id: json['id']?.toString() ?? '',
      ticketCode: json['ticketCode']?.toString() ?? '',
      titleId: json['titleId']?.toString(),
      title: json['title']?.toString() ?? '',
      userType: json['userType']?.toString() ?? '',
      supportType: json['supportType']?.toString() ?? 'general',
      requesterRole: json['requesterRole']?.toString() ?? '',
      requesterId: json['requesterId']?.toString() ?? '',
      requesterName: json['requesterName']?.toString() ?? '',
      requesterPhone: json['requesterPhone']?.toString() ?? '',
      serviceLocation: json['serviceLocation']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      assignedAdminId: json['assignedAdminId']?.toString(),
      assignedAdminName: json['assignedAdminName']?.toString() ?? '',
      messages: asMapList(json['messages'])
          .map(SupportTicketMessage.fromJson)
          .toList(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      lastMessageAt: DateTime.tryParse(json['lastMessageAt']?.toString() ?? ''),
    );
  }
}
