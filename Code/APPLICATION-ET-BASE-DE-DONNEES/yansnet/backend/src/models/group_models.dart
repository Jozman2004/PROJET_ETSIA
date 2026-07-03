// ─────────────────────────────────────────────────────────────────────────────
// models/group_message.dart
// ─────────────────────────────────────────────────────────────────────────────

class GroupMessage {
  final String id;
  final String groupId;
  final String? senderId;
  final String? content;
  final String? fileUrl;
  final String? fileType;
  final String? fileName;
  final int? fileSize;
  final bool isSystem;
  bool isRead;
  final DateTime createdAt;
  final String? username;
  final String? avatarUrl;

  GroupMessage({
    required this.id,
    required this.groupId,
    this.senderId,
    this.content,
    this.fileUrl,
    this.fileType,
    this.fileName,
    this.fileSize,
    this.isSystem = false,
    this.isRead = false,
    required this.createdAt,
    this.username,
    this.avatarUrl,
  });

  factory GroupMessage.fromJson(Map<String, dynamic> json) {
    return GroupMessage(
      id:        json['id']?.toString() ?? '',
      groupId:   json['group_id']?.toString() ?? json['groupId']?.toString() ?? '',
      senderId:  json['sender_id']?.toString() ?? json['senderId']?.toString(),
      content:   json['content'],
      fileUrl:   json['file_url']  ?? json['fileUrl'],
      fileType:  json['file_type'] ?? json['fileType'],
      fileName:  json['file_name'] ?? json['fileName'],
      fileSize:  json['file_size'] != null
          ? int.tryParse(json['file_size'].toString())
          : (json['fileSize'] != null ? int.tryParse(json['fileSize'].toString()) : null),
      isSystem:  json['is_system'] ?? json['isSystem'] ?? false,
      isRead:    json['is_read']   ?? json['isRead']   ?? false,
      createdAt: DateTime.tryParse(
            json['created_at'] ?? json['createdAt'] ?? '',
          ) ?? DateTime.now(),
      username:  json['username'],
      avatarUrl: json['avatar_url'] ?? json['avatarUrl'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id':         id,
    'group_id':   groupId,
    'sender_id':  senderId,
    'content':    content,
    'file_url':   fileUrl,
    'file_type':  fileType,
    'file_name':  fileName,
    'file_size':  fileSize,
    'is_system':  isSystem,
    'is_read':    isRead,
    'created_at': createdAt.toIso8601String(),
    'username':   username,
    'avatar_url': avatarUrl,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// models/group_detail.dart
// ─────────────────────────────────────────────────────────────────────────────

class GroupMember {
  final String id;
  final String username;
  final String? fullName;
  final String? avatarUrl;
  final String role; // 'admin' | 'member'
  final DateTime? joinedAt;

  GroupMember({
    required this.id,
    required this.username,
    this.fullName,
    this.avatarUrl,
    required this.role,
    this.joinedAt,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      id:        json['id']?.toString() ?? '',
      username:  json['username'] ?? '',
      fullName:  json['full_name'] ?? json['fullName'],
      avatarUrl: json['avatar_url'] ?? json['avatarUrl'],
      role:      json['role'] ?? 'member',
      joinedAt:  DateTime.tryParse(json['joined_at'] ?? json['joinedAt'] ?? ''),
    );
  }
}

class GroupDetail {
  final String id;
  final String name;
  final String createdBy;
  final String? creatorUsername;
  final String myRole; // 'admin' | 'member'
  final DateTime createdAt;
  final List<GroupMember> members;

  GroupDetail({
    required this.id,
    required this.name,
    required this.createdBy,
    this.creatorUsername,
    required this.myRole,
    required this.createdAt,
    required this.members,
  });

  factory GroupDetail.fromJson(Map<String, dynamic> json) {
    return GroupDetail(
      id:              json['id']?.toString() ?? '',
      name:            json['name'] ?? '',
      createdBy:       json['created_by']?.toString() ?? '',
      creatorUsername: json['creator_username'],
      myRole:          json['my_role'] ?? 'member',
      createdAt:       DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      members: (json['members'] as List<dynamic>? ?? [])
          .map((m) => GroupMember.fromJson(m))
          .toList(),
    );
  }

  bool get isAdmin => myRole == 'admin';
}

// ─────────────────────────────────────────────────────────────────────────────
// models/group_summary.dart  (liste des groupes)
// ─────────────────────────────────────────────────────────────────────────────

class GroupSummary {
  final String id;
  final String name;
  final String createdBy;
  final String role;
  final int memberCount;
  final String? lastMessage;
  final String? lastFileType;
  final String? lastSenderUsername;
  final DateTime? lastMessageTime;
  final int unreadCount;

  GroupSummary({
    required this.id,
    required this.name,
    required this.createdBy,
    required this.role,
    required this.memberCount,
    this.lastMessage,
    this.lastFileType,
    this.lastSenderUsername,
    this.lastMessageTime,
    this.unreadCount = 0,
  });

  factory GroupSummary.fromJson(Map<String, dynamic> json) {
    return GroupSummary(
      id:                  json['id']?.toString() ?? '',
      name:                json['name'] ?? '',
      createdBy:           json['created_by']?.toString() ?? '',
      role:                json['role'] ?? 'member',
      memberCount:         int.tryParse(json['member_count']?.toString() ?? '0') ?? 0,
      lastMessage:         json['last_message'],
      lastFileType:        json['last_file_type'],
      lastSenderUsername:  json['last_sender_username'],
      lastMessageTime:     DateTime.tryParse(json['last_message_time'] ?? ''),
      unreadCount:         int.tryParse(json['unread_count']?.toString() ?? '0') ?? 0,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// models/user_search_result.dart
// ─────────────────────────────────────────────────────────────────────────────

class UserSearchResult {
  final String id;
  final String username;
  final String? fullName;
  final String? avatarUrl;

  UserSearchResult({
    required this.id,
    required this.username,
    this.fullName,
    this.avatarUrl,
  });

  factory UserSearchResult.fromJson(Map<String, dynamic> json) {
    return UserSearchResult(
      id:        json['id']?.toString() ?? '',
      username:  json['username'] ?? '',
      fullName:  json['full_name'] ?? json['fullName'],
      avatarUrl: json['avatar_url'] ?? json['avatarUrl'],
    );
  }

  String get displayName => fullName?.isNotEmpty == true ? fullName! : username;
}
