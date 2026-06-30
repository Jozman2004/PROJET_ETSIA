// lib/models/group_detail.dart
class GroupDetail {
  final String id;
  final String name;
  final String? description;           // <- ajout
  final String createdBy;
  final String creatorUsername;
  final String myRole;
  final DateTime createdAt;
  final List<GroupMember> members;

  GroupDetail({
    required this.id,
    required this.name,
    this.description,
    required this.createdBy,
    required this.creatorUsername,
    required this.myRole,
    required this.createdAt,
    required this.members,
  });

  bool get isAdmin => myRole == 'admin';

  factory GroupDetail.fromJson(Map<String, dynamic> json) {
    return GroupDetail(
      id: json['id'],
      name: json['name'],
      description: json['description'],   // <- ajout
      createdBy: json['created_by'] ?? '',
      creatorUsername: json['creator_username'] ?? '',
      myRole: json['my_role'] ?? 'member',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      members: (json['members'] as List?)
              ?.map((m) => GroupMember.fromJson(m))
              .toList() ??
          [],
    );
  }
}

class GroupMember {
  final String id;
  final String username;
  final String? fullName;
  final String? avatarUrl;
  final String role;
  final DateTime joinedAt;

  GroupMember({
    required this.id,
    required this.username,
    this.fullName,
    this.avatarUrl,
    required this.role,
    required this.joinedAt,
  });

  String get displayName => (fullName?.isNotEmpty == true) ? fullName! : username;

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      id: json['id'],
      username: json['username'],
      fullName: json['full_name'],
      avatarUrl: json['avatar_url'],
      role: json['role'] ?? 'member',
      joinedAt: json['joined_at'] != null
          ? DateTime.parse(json['joined_at'])
          : DateTime.now(),
    );
  }
}

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

  String get displayName => (fullName?.isNotEmpty == true) ? fullName! : username;

  factory UserSearchResult.fromJson(Map<String, dynamic> json) {
    return UserSearchResult(
      id: json['id'],
      username: json['username'],
      fullName: json['full_name'],
      avatarUrl: json['avatar_url'],
    );
  }
}