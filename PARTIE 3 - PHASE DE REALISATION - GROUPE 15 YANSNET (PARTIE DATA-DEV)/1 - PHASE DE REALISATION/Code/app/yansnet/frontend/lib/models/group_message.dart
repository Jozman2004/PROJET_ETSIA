// lib/models/group_message.dart
import 'dart:convert';

class GroupMessage {
  final String id;
  final String groupId;
  final String senderId;
  final String? content;
  final String? fileUrl;
  final String? fileType;
  final String? fileName;
  final int? fileSize;
  final String? username;
  final String? avatarUrl;
  final bool isSystem;
  final bool isRead;
  final DateTime createdAt;
  final bool isPinned;
  final String? replyToId;
  final bool isEdited;
  final String? editHistory;

  GroupMessage({
    required this.id,
    required this.groupId,
    required this.senderId,
    this.content,
    this.fileUrl,
    this.fileType,
    this.fileName,
    this.fileSize,
    this.username,
    this.avatarUrl,
    this.isSystem = false,
    this.isRead = false,
    required this.createdAt,
    this.isPinned = false,
    this.replyToId,
    this.isEdited = false,
    this.editHistory,
  });

  factory GroupMessage.fromJson(Map<String, dynamic> json) {
    return GroupMessage(
      id: json['id'] ?? '',
      groupId: json['group_id'] ?? '',
      senderId: json['sender_id'] ?? '',
      content: json['content'] ?? json['text'],
      fileUrl: json['file_url'],        // ✅ clé exacte
      fileType: json['file_type'],      // ✅
      fileName: json['file_name'],      // ✅
      fileSize: json['file_size'],      // ✅
      username: json['username'],
      avatarUrl: json['avatar_url'],
      isSystem: json['is_system'] ?? false,
      isRead: json['is_read'] ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      isPinned: json['is_pinned'] ?? false,
      replyToId: json['reply_to_id'],
      isEdited: json['is_edited'] ?? false,
      editHistory: json['edit_history'] is String
          ? json['edit_history']
          : json['edit_history'] != null ? jsonEncode(json['edit_history']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'group_id': groupId,
      'sender_id': senderId,
      'content': content,
      'file_url': fileUrl,
      'file_type': fileType,
      'file_name': fileName,
      'file_size': fileSize,
      'username': username,
      'avatar_url': avatarUrl,
      'is_system': isSystem,
      'is_read': isRead,
      'created_at': createdAt.toIso8601String(),
      'is_pinned': isPinned,
      'reply_to_id': replyToId,
      'is_edited': isEdited,
      'edit_history': editHistory,
    };
  }
}