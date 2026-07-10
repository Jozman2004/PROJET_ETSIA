// lib/models/friend_action.dart

/// Modèle représentant une action sociale d'un ami (abonné) sur un post.
/// Type peut être 'like', 'repost' ou 'like_repost' (combinaison des deux).
class FriendAction {
  final String userId;
  final String fullName;
  final String? avatarUrl;
  final String type; // 'like', 'repost' ou 'like_repost'

  FriendAction({
    required this.userId,
    required this.fullName,
    this.avatarUrl,
    required this.type,
  });

  factory FriendAction.fromJson(Map<String, dynamic> json) {
    return FriendAction(
      userId: json['user_id']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? 'Utilisateur',
      avatarUrl: json['avatar_url']?.toString(),
      type: json['type']?.toString() ?? 'like',
    );
  }

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'full_name': fullName,
    'avatar_url': avatarUrl,
    'type': type,
  };
}