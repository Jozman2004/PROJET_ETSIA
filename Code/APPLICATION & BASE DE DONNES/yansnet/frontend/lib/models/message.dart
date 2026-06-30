// ─────────────────────────────────────────────────────────────────────────────
// models.dart — modèles complets corrigés
// ─────────────────────────────────────────────────────────────────────────────

class Message {
  final String id;
  final String senderId;
  final String receiverId;
  final String? content;
  bool isRead;
  final bool isEdited;
  final bool isDeleted;
  final DateTime createdAt;
  final String? senderUsername;
  final String? fileUrl;
  final String? fileType;
  final String? fileName;
  final int? fileSize;

  Message({
    required this.id,
    required this.senderId,
    required this.receiverId,
    this.content,
    required this.isRead,
    required this.isEdited,
    required this.isDeleted,
    required this.createdAt,
    this.senderUsername,
    this.fileUrl,
    this.fileType,
    this.fileName,
    this.fileSize,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id:             json['id']?.toString() ?? '',
      senderId:       json['sender_id']  ?? json['senderId']  ?? '',
      receiverId:     json['receiver_id'] ?? json['receiverId'] ?? '',
      content:        json['content'],
      isRead:         json['is_read']  ?? json['isRead']  ?? false,
      isEdited:       json['is_edited'] ?? json['isEdited'] ?? false,
      isDeleted:      json['is_deleted'] ?? json['isDeleted'] ?? false,
      createdAt:      DateTime.tryParse(
                        json['created_at'] ?? json['createdAt'] ?? '',
                      ) ?? DateTime.now(),
      senderUsername: json['sender_username'] ?? json['senderUsername'],
      fileUrl:        json['file_url']  ?? json['fileUrl'],
      fileType:       json['file_type'] ?? json['fileType'],
      fileName:       json['file_name'] ?? json['fileName'],
      fileSize:       json['file_size'] != null
          ? int.tryParse(json['file_size'].toString())
          : (json['fileSize'] != null
              ? int.tryParse(json['fileSize'].toString())
              : null),
    );
  }

  Map<String, dynamic> toJson() => {
    'id':               id,
    'sender_id':        senderId,
    'receiver_id':      receiverId,
    'content':          content,
    'is_read':          isRead,
    'is_edited':        isEdited,
    'is_deleted':       isDeleted,
    'created_at':       createdAt.toIso8601String(),
    'sender_username':  senderUsername,
    'file_url':         fileUrl,
    'file_type':        fileType,
    'file_name':        fileName,
    'file_size':        fileSize,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// ✅ FIX MAJEUR : GroupMessage — ajout de tous les champs manquants
//    (fileType, fileName, fileSize, isSystem, isRead, avatarUrl)
// ─────────────────────────────────────────────────────────────────────────────

class GroupMessage {
  final String id;
  final String groupId;
  final String senderId;
  final String? content;       // nullable : un message peut n'avoir qu'un fichier
  final String? fileUrl;
  final String? fileType;      // 'image' | 'video' | 'audio' | 'document'
  final String? fileName;
  final int?    fileSize;
  final bool    isSystem;      // messages système (membre ajouté, etc.)
  final bool    isRead;
  final DateTime createdAt;
  final String? username;
  final String? avatarUrl;

  GroupMessage({
    required this.id,
    required this.groupId,
    required this.senderId,
    this.content,
    this.fileUrl,
    this.fileType,
    this.fileName,
    this.fileSize,
    this.isSystem = false,
    this.isRead   = false,
    required this.createdAt,
    this.username,
    this.avatarUrl,
  });

  factory GroupMessage.fromJson(Map<String, dynamic> json) {
    return GroupMessage(
      id:        json['id']?.toString() ?? '',
      groupId:   json['group_id']  ?? json['groupId']  ?? '',
      senderId:  json['sender_id'] ?? json['senderId'] ?? '',
      content:   json['content'],
      fileUrl:   json['file_url']  ?? json['fileUrl'],
      fileType:  json['file_type'] ?? json['fileType'],
      fileName:  json['file_name'] ?? json['fileName'],
      fileSize:  json['file_size'] != null
          ? int.tryParse(json['file_size'].toString())
          : (json['fileSize'] != null
              ? int.tryParse(json['fileSize'].toString())
              : null),
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

class Group {
  final String  id;
  final String  name;
  final String  createdBy;
  final String? role;           // 'admin' | 'member'
  final int     memberCount;
  final String? lastMessage;
  final String? lastFileType;
  final String? lastSenderUsername;
  final DateTime? lastMessageTime;
  final int     unreadCount;
  final DateTime createdAt;

  Group({
    required this.id,
    required this.name,
    required this.createdBy,
    this.role,
    this.memberCount = 0,
    this.lastMessage,
    this.lastFileType,
    this.lastSenderUsername,
    this.lastMessageTime,
    this.unreadCount = 0,
    required this.createdAt,
  });

  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id:                  json['id']?.toString() ?? '',
      name:                json['name'] ?? '',
      createdBy:           json['created_by']?.toString() ?? '',
      role:                json['role'],
      memberCount:         int.tryParse(json['member_count']?.toString() ?? '0') ?? 0,
      lastMessage:         json['last_message'],
      lastFileType:        json['last_file_type'],
      lastSenderUsername:  json['last_sender_username'],
      lastMessageTime:     json['last_message_time'] != null
          ? DateTime.tryParse(json['last_message_time'].toString())
          : null,
      unreadCount:         int.tryParse(json['unread_count']?.toString() ?? '0') ?? 0,
      createdAt:           DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id':                    id,
    'name':                  name,
    'created_by':            createdBy,
    'role':                  role,
    'member_count':          memberCount,
    'last_message':          lastMessage,
    'last_file_type':        lastFileType,
    'last_sender_username':  lastSenderUsername,
    'last_message_time':     lastMessageTime?.toIso8601String(),
    'unread_count':          unreadCount,
    'created_at':            createdAt.toIso8601String(),
  };
}

// ─────────────────────────────────────────────────────────────────────────────

class GroupMember {
  final String  id;
  final String  username;
  final String? fullName;
  final String? avatarUrl;
  final String  role;       // 'admin' | 'member'
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
      fullName:  json['full_name'],
      avatarUrl: json['avatar_url'],
      role:      json['role'] ?? 'member',
      joinedAt:  json['joined_at'] != null
          ? DateTime.tryParse(json['joined_at'].toString())
          : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class AppNotification {
  final String id;
  final String type;
  final String content;
  bool isRead;
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

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id:          json['id'] ?? '',
      type:        json['type'] ?? '',
      content:     json['content'] ?? '',
      isRead:      json['is_read'] ?? false,
      referenceId: json['reference_id'],
      createdAt:   DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id':           id,
    'type':         type,
    'content':      content,
    'is_read':      isRead,
    'reference_id': referenceId,
    'created_at':   createdAt.toIso8601String(),
  };

  String get icon {
    switch (type) {
      case 'like':             return '❤️';
      case 'comment':          return '💬';
      case 'new_follower':     return '👤';
      case 'warning':          return '⚠️';
      case 'moderation_alert': return '🚨';
      default:                 return '🔔';
    }
  }
}