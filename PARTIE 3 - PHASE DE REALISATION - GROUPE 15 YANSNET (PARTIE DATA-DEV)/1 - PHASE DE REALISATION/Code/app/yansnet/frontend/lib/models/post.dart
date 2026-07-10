// lib/models/post.dart
import 'dart:convert';
import 'friend_action.dart'; // Assurez-vous que ce fichier existe

// ════════════════════════════════════════════════════════════════════
// MODÈLE LIKER (pour la bande horizontale des likes)
// ════════════════════════════════════════════════════════════════════

class Liker {
  final String userId;
  final String fullName;
  final String? avatarUrl;

  Liker({
    required this.userId,
    required this.fullName,
    this.avatarUrl,
  });

  factory Liker.fromJson(Map<String, dynamic> json) {
    return Liker(
      userId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? json['fullName']?.toString() ?? '',
      avatarUrl: json['avatar_url']?.toString() ?? json['avatarUrl']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'full_name': fullName,
    'avatar_url': avatarUrl,
  };
}

// ════════════════════════════════════════════════════════════════════
// MODÈLE POST (complet avec reposts, actions sociales, likers, etc.)
// ════════════════════════════════════════════════════════════════════

class Post {
  final String id;
  final String userId;
  final String username;
  final String fullName;
  final String? content;
  final String? mediaUrl;
  final String? mediaType;
  final String? avatarUrl;
  final List<String> tags;
  final bool isInstitutional;
  int likeCount;
  int commentCount;
  bool userLiked;
  final DateTime createdAt;
  final List<String>? mediaGallery;
  final List<String>? mediaTypes;

  // ✅ Republication (Repost)
  final int repostCount;
  final bool userReposted;
  final String? sharedPostId;
  final Post? sharedPost;

  // ✅ Actions sociales des amis (likes et reposts)
  final List<FriendAction> likedByFriends;
  final List<FriendAction> repostedByFriends;

  // ✅ Likers (pour la bande horizontale)
  final List<Liker>? likers;

  Post({
    required this.id,
    required this.userId,
    required this.username,
    required this.fullName,
    this.content,
    this.mediaUrl,
    this.mediaType,
    this.avatarUrl,
    required this.tags,
    required this.isInstitutional,
    required this.likeCount,
    required this.commentCount,
    required this.userLiked,
    required this.createdAt,
    this.mediaGallery,
    this.mediaTypes,
    this.repostCount = 0,
    this.userReposted = false,
    this.sharedPostId,
    this.sharedPost,
    this.likedByFriends = const [],
    this.repostedByFriends = const [],
    this.likers,
  });

  // ============================================================
  // FACTORY fromJson
  // ============================================================
  factory Post.fromJson(Map<String, dynamic> json) {
    // Parser les tags
    List<String> parsedTags = [];
    if (json['tags'] != null) {
      if (json['tags'] is List) {
        parsedTags = List<String>.from(json['tags']);
      } else if (json['tags'] is String) {
        parsedTags = (json['tags'] as String).split(',').map((t) => t.trim()).toList();
      }
    }

    // Parser la galerie média
    List<String>? gallery;
    List<String>? types;
    if (json['media_gallery'] != null) {
      if (json['media_gallery'] is String) {
        try {
          gallery = List<String>.from(jsonDecode(json['media_gallery']));
        } catch (_) {
          gallery = [];
        }
      } else if (json['media_gallery'] is List) {
        gallery = List<String>.from(json['media_gallery']);
      }
    }
    if (json['media_types'] != null && json['media_types'] is List) {
      types = List<String>.from(json['media_types']);
    } else if (gallery != null && gallery.isNotEmpty && json['media_type'] != null) {
      types = List.filled(gallery.length, json['media_type'].toString());
    }

    // Parser le post original (shared_post)
    Post? sharedPost;
    if (json['shared_post'] is Map<String, dynamic>) {
      sharedPost = Post.fromJson(json['shared_post']);
    }

    // Parser les actions des amis (likes et reposts)
    List<FriendAction> likedByFriends = [];
    List<FriendAction> repostedByFriends = [];
    if (json['liked_by_friends'] is List) {
      likedByFriends = (json['liked_by_friends'] as List)
          .map((e) => FriendAction.fromJson(e))
          .toList();
    }
    if (json['reposted_by_friends'] is List) {
      repostedByFriends = (json['reposted_by_friends'] as List)
          .map((e) => FriendAction.fromJson(e))
          .toList();
    }

    // Parser les likers
    List<Liker>? likers;
    if (json['likers'] is List) {
      likers = (json['likers'] as List).map((e) => Liker.fromJson(e)).toList();
    }

    return Post(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? '',
      content: json['content']?.toString(),
      mediaUrl: json['media_url']?.toString(),
      mediaType: json['media_type']?.toString(),
      avatarUrl: json['avatar_url']?.toString(),
      tags: parsedTags,
      isInstitutional: json['is_institutional'] == true,
      likeCount: _parseInt(json['like_count']),
      commentCount: _parseInt(json['comment_count']),
      userLiked: json['user_liked'] == true,
      createdAt: _parseDate(json['created_at']),
      mediaGallery: gallery,
      mediaTypes: types,
      repostCount: _parseInt(json['repost_count']),
      userReposted: json['user_reposted'] == true,
      sharedPostId: json['shared_post_id']?.toString(),
      sharedPost: sharedPost,
      likedByFriends: likedByFriends,
      repostedByFriends: repostedByFriends,
      likers: likers,
    );
  }

  // ============================================================
  // MÉTHODES UTILITAIRES
  // ============================================================
  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();
    return DateTime.tryParse(value.toString()) ?? DateTime.now();
  }

  // ============================================================
  // toJson
  // ============================================================
  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'username': username,
    'full_name': fullName,
    'content': content,
    'media_url': mediaUrl,
    'media_type': mediaType,
    'avatar_url': avatarUrl,
    'tags': tags,
    'is_institutional': isInstitutional,
    'like_count': likeCount,
    'comment_count': commentCount,
    'user_liked': userLiked,
    'created_at': createdAt.toIso8601String(),
    'media_gallery': mediaGallery != null ? jsonEncode(mediaGallery) : null,
    'media_types': mediaTypes,
    'repost_count': repostCount,
    'user_reposted': userReposted,
    'shared_post_id': sharedPostId,
    'shared_post': sharedPost?.toJson(),
    'liked_by_friends': likedByFriends.map((e) => e.toJson()).toList(),
    'reposted_by_friends': repostedByFriends.map((e) => e.toJson()).toList(),
    'likers': likers?.map((e) => e.toJson()).toList(),
  };

  // ============================================================
  // copyWith
  // ============================================================
  Post copyWith({
    int? likeCount,
    int? commentCount,
    bool? userLiked,
    List<String>? mediaGallery,
    List<String>? mediaTypes,
    int? repostCount,
    bool? userReposted,
    String? sharedPostId,
    Post? sharedPost,
    List<FriendAction>? likedByFriends,
    List<FriendAction>? repostedByFriends,
    List<Liker>? likers,
  }) {
    return Post(
      id: id,
      userId: userId,
      username: username,
      fullName: fullName,
      content: content,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      avatarUrl: avatarUrl,
      tags: tags,
      isInstitutional: isInstitutional,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      userLiked: userLiked ?? this.userLiked,
      createdAt: createdAt,
      mediaGallery: mediaGallery ?? this.mediaGallery,
      mediaTypes: mediaTypes ?? this.mediaTypes,
      repostCount: repostCount ?? this.repostCount,
      userReposted: userReposted ?? this.userReposted,
      sharedPostId: sharedPostId ?? this.sharedPostId,
      sharedPost: sharedPost ?? this.sharedPost,
      likedByFriends: likedByFriends ?? this.likedByFriends,
      repostedByFriends: repostedByFriends ?? this.repostedByFriends,
      likers: likers ?? this.likers,
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// MODÈLE COMMENT (inchangé, mais complet)
// ════════════════════════════════════════════════════════════════════

class Comment {
  final String id;
  final String userId;
  final String postId;
  final String content;
  final String username;
  final String fullName;
  final String? avatarUrl;
  final DateTime createdAt;
  final String? parentId;
  int likeCount;
  bool userLiked;
  int replyCount;
  List<Comment>? replies;
  bool showReplies;

  Comment({
    required this.id,
    required this.userId,
    required this.postId,
    required this.content,
    required this.username,
    required this.fullName,
    this.avatarUrl,
    required this.createdAt,
    this.parentId,
    this.likeCount = 0,
    this.userLiked = false,
    this.replyCount = 0,
    this.replies,
    this.showReplies = false,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      postId: json['post_id']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? '',
      avatarUrl: json['avatar_url']?.toString(),
      createdAt: _parseDate(json['created_at']),
      parentId: json['parent_id']?.toString(),
      likeCount: _parseInt(json['like_count']),
      userLiked: json['user_liked'] == true,
      replyCount: _parseInt(json['reply_count']),
    );
  }

  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();
    return DateTime.tryParse(value.toString()) ?? DateTime.now();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'post_id': postId,
    'content': content,
    'username': username,
    'full_name': fullName,
    'avatar_url': avatarUrl,
    'created_at': createdAt.toIso8601String(),
    'parent_id': parentId,
    'like_count': likeCount,
    'user_liked': userLiked,
    'reply_count': replyCount,
  };

  Comment copyWith({
    int? likeCount,
    bool? userLiked,
    int? replyCount,
    List<Comment>? replies,
    bool? showReplies,
  }) {
    return Comment(
      id: id,
      userId: userId,
      postId: postId,
      content: content,
      username: username,
      fullName: fullName,
      avatarUrl: avatarUrl,
      createdAt: createdAt,
      parentId: parentId,
      likeCount: likeCount ?? this.likeCount,
      userLiked: userLiked ?? this.userLiked,
      replyCount: replyCount ?? this.replyCount,
      replies: replies ?? this.replies,
      showReplies: showReplies ?? this.showReplies,
    );
  }
}