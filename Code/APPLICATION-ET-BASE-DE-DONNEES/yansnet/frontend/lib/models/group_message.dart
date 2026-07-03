// lib/models/group_message.dart
class GroupMessage {
  final String id;
  final String groupId;
  final String senderId;
  final String? content;
  final bool isSystem;
  final bool isRead;
  final DateTime createdAt;
  final String? username;
  final String? avatarUrl;
  final String? fileUrl;
  final String? fileType;
  final String? fileName;
  final int? fileSize;
  final bool isPinned;                      // nouveau champ

  GroupMessage({
    required this.id,
    required this.groupId,
    required this.senderId,
    this.content,
    this.isSystem = false,
    this.isRead = false,
    required this.createdAt,
    this.username,
    this.avatarUrl,
    this.fileUrl,
    this.fileType,
    this.fileName,
    this.fileSize,
    this.isPinned = false,                  // valeur par défaut
  });

  factory GroupMessage.fromJson(Map<String, dynamic> json) {
    return GroupMessage(
      id: json['id'] ?? '',
      groupId: json['group_id'] ?? '',
      senderId: json['sender_id'] ?? '',
      content: json['content'],
      isSystem: json['is_system'] ?? false,
      isRead: json['is_read'] ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      username: json['username'],
      avatarUrl: json['avatar_url'],
      fileUrl: json['file_url'],
      fileType: json['file_type'],
      fileName: json['file_name'],
      fileSize: json['file_size'],
      isPinned: json['is_pinned'] ?? false,
    );
  }
}