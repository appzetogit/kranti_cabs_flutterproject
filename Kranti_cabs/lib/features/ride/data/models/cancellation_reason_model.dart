/// A reason the rider can pick when cancelling, managed from the admin panel.
class CancellationReasonModel {
  final String id;
  final String title;

  /// True for catch-all entries like "Other", where the label alone says
  /// nothing useful and the rider is asked to type what happened.
  final bool requiresNote;

  const CancellationReasonModel({
    required this.id,
    required this.title,
    this.requiresNote = false,
  });

  factory CancellationReasonModel.fromJson(Map<String, dynamic> json) {
    return CancellationReasonModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      requiresNote: json['requiresNote'] == true,
    );
  }
}
