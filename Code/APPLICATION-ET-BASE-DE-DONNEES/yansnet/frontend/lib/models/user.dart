// lib/models/user.dart

class User {
  final String id;
  final String email;
  final String username;
  final String fullName;
  final String role;
  final String? bio;
  String? avatarUrl;  // ← mutable (plus de final)
  final String? promotion;
  final String? residence;
  final String? filiere;
  final int? postCount;
  int? followersCount;
  final int? followingCount;
  bool? isFollowing;

  User({
    required this.id,
    required this.email,
    required this.username,
    required this.fullName,
    required this.role,
    this.bio,
    this.avatarUrl,
    this.promotion,
    this.residence,
    this.filiere,
    this.postCount,
    this.followersCount,
    this.followingCount,
    this.isFollowing,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? '',
      role: json['role']?.toString() ?? 'student',
      bio: json['bio']?.toString(),
      avatarUrl: json['avatar_url']?.toString(),
      promotion: json['promotion']?.toString(),
      residence: json['residence']?.toString(),
      filiere: json['filiere']?.toString(),
      postCount: _parseInt(json['post_count']),
      followersCount: _parseInt(json['followers_count']),
      followingCount: _parseInt(json['following_count']),
      isFollowing: json['is_following'] == true,
    );
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'username': username,
    'full_name': fullName,
    'role': role,
    'bio': bio,
    'avatar_url': avatarUrl,
    'promotion': promotion,
    'residence': residence,
    'filiere': filiere,
  };

  User copyWith({
    String? fullName,
    String? username,
    String? bio,
    String? avatarUrl,
    String? promotion,
    String? residence,
    String? filiere,
    int? postCount,
    int? followersCount,
    int? followingCount,
    bool? isFollowing,
  }) {
    return User(
      id: id,
      email: email,
      username: username ?? this.username,
      fullName: fullName ?? this.fullName,
      role: role,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      promotion: promotion ?? this.promotion,
      residence: residence ?? this.residence,
      filiere: filiere ?? this.filiere,
      postCount: postCount ?? this.postCount,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount ?? this.followingCount,
      isFollowing: isFollowing ?? this.isFollowing,
    );
  }
}