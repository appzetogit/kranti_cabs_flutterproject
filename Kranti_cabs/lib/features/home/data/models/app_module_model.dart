import '../../../../core/utils/image_utils.dart';

class AppModuleModel {
  final String id;
  final String name;
  final String transportType;
  final String serviceType;
  final int orderBy;
  final String shortDescription;
  final String description;
  final String mobileMenuIcon;
  final bool active;

  const AppModuleModel({
    required this.id,
    required this.name,
    required this.transportType,
    required this.serviceType,
    required this.orderBy,
    required this.shortDescription,
    required this.description,
    required this.mobileMenuIcon,
    required this.active,
  });

  factory AppModuleModel.fromJson(Map<String, dynamic> json) {
    return AppModuleModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      transportType: (json['transport_type'] ?? '').toString(),
      serviceType: (json['service_type'] ?? '').toString(),
      orderBy: int.tryParse('${json['order_by'] ?? 0}') ?? 0,
      shortDescription: (json['short_description'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      // Resolved here, once, rather than at each render site: the CMS sends a
      // server-relative path and every screen that shows a module needs the
      // absolute URL.
      mobileMenuIcon: resolveMediaUrl((json['mobile_menu_icon'] ?? '').toString()),
      active: (int.tryParse('${json['active'] ?? 0}') ?? 0) == 1,
    );
  }
}
