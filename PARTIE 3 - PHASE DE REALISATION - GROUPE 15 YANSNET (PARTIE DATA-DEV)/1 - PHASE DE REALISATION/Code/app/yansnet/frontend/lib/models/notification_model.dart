// lib/models/notification_model.dart
class AppNotification {
  final String id;
  final String type;
  final String content;
  final bool isRead;
  final String? referenceId;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.type,
    required this.content,
    required this.isRead,
    this.referenceId,
    required this.createdAt,
  });

  String get icon {
    switch (type) {
      case 'like':
        return '❤️';
      case 'comment':
        return '💬';
      case 'new_follower':
        return '👤';
      case 'group_invite':
        return '👥';
      case 'report':
        return '⚠️';
      case 'moderation_alert':
        return '🛡️';
      case 'warning':
        return '⚠️';
      default:
        return '🔔';
    }
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'],
      type: json['type'],
      content: json['content'],
      isRead: json['is_read'] ?? false,
      referenceId: json['reference_id'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}