import 'package:flutter/material.dart';

@immutable
class Comment {
  final String id;
  final String postId;
  final String userId;
  final String content;
  final DateTime createdAt;
  final String fullName;
  final String? avatarUrl;
  final String? username;           // Nom d'utilisateur pour les mentions
  final String? parentId;           // ID du commentaire parent (si réponse)
  int likeCount;
  bool isLiked;
  int replyCount;                   // Nombre total de réponses (directes)
  List<Comment>? replies;           // Liste des réponses (chargées à la demande)
  bool showReplies;                 // État d'affichage des réponses (UI)

  Comment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.content,
    required this.createdAt,
    required this.fullName,
    this.avatarUrl,
    this.username,
    this.parentId,
    this.likeCount = 0,
    this.isLiked = false,
    this.replyCount = 0,
    this.replies,
    this.showReplies = false,
  });

  // ─── Constructeur vide ────────────────────────────────────────
  Comment.empty()
      : id = '',
        postId = '',
        userId = '',
        content = '',
        createdAt = DateTime.now(),
        fullName = '',
        avatarUrl = null,
        username = null,
        parentId = null,
        likeCount = 0,
        isLiked = false,
        replyCount = 0,
        replies = null,
        showReplies = false;

  // ─── Factory ────────────────────────────────────────────────
  factory Comment.fromJson(Map<String, dynamic> json) {
    // Gestion des listes de réponses si présentes
    List<Comment>? replies;
    if (json['replies'] is List) {
      replies = (json['replies'] as List)
          .map((e) => Comment.fromJson(e))
          .toList();
    }

    return Comment(
      id: json['id']?.toString() ?? '',
      postId: json['post_id']?.toString() ?? json['postId']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      content: json['content'] ?? '',
      createdAt: _parseDate(json['created_at'] ?? json['createdAt']),
      fullName: json['full_name'] ?? json['fullName'] ?? 'Utilisateur',
      avatarUrl: json['avatar_url']?.toString() ?? json['avatarUrl']?.toString(),
      username: json['username']?.toString(),
      parentId: json['parent_id']?.toString() ?? json['parentId']?.toString(),
      likeCount: _parseInt(json['like_count'] ?? json['likeCount']),
      isLiked: json['is_liked'] ?? json['isLiked'] ?? false,
      replyCount: _parseInt(json['reply_count'] ?? json['replyCount']),
      replies: replies,
      showReplies: json['show_replies'] ?? json['showReplies'] ?? false,
    );
  }

  // ─── Utilitaires ─────────────────────────────────────────────
  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString()) ?? DateTime.now();
  }

  // ─── Accesseurs supplémentaires ──────────────────────────────
  bool get isReply => parentId != null && parentId!.isNotEmpty;

  String get displayName => username != null ? '@$username' : fullName;

  // ─── toJson ──────────────────────────────────────────────────
  Map<String, dynamic> toJson() => {
    'id': id,
    'post_id': postId,
    'user_id': userId,
    'content': content,
    'created_at': createdAt.toIso8601String(),
    'full_name': fullName,
    'avatar_url': avatarUrl,
    'username': username,
    'parent_id': parentId,
    'like_count': likeCount,
    'is_liked': isLiked,
    'reply_count': replyCount,
    'replies': replies?.map((c) => c.toJson()).toList(),
    'show_replies': showReplies,
  };

  // ─── copyWith ─────────────────────────────────────────────────
  Comment copyWith({
    String? id,
    String? postId,
    String? userId,
    String? content,
    DateTime? createdAt,
    String? fullName,
    String? avatarUrl,
    String? username,
    String? parentId,
    int? likeCount,
    bool? isLiked,
    int? replyCount,
    List<Comment>? replies,
    bool? showReplies,
  }) {
    return Comment(
      id: id ?? this.id,
      postId: postId ?? this.postId,
      userId: userId ?? this.userId,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      fullName: fullName ?? this.fullName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      username: username ?? this.username,
      parentId: parentId ?? this.parentId,
      likeCount: likeCount ?? this.likeCount,
      isLiked: isLiked ?? this.isLiked,
      replyCount: replyCount ?? this.replyCount,
      replies: replies ?? this.replies,
      showReplies: showReplies ?? this.showReplies,
    );
  }

  // ─── Méthodes de manipulation d'état (UI) ──────────────────
  void toggleShowReplies() {
    showReplies = !showReplies;
  }

  void addReply(Comment reply) {
    if (replies == null) replies = [];
    replies!.add(reply);
    replyCount = replies!.length;
    showReplies = true;
  }

  void removeReply(String replyId) {
    replies?.removeWhere((r) => r.id == replyId);
    replyCount = replies?.length ?? 0;
  }

  // ─── Debug ──────────────────────────────────────────────────
  @override
  String toString() {
    return 'Comment(id: $id, userId: $userId, fullName: $fullName, content: $content, createdAt: $createdAt, likeCount: $likeCount, isLiked: $isLiked, replyCount: $replyCount, isReply: $isReply)';
  }

  // ─── Égalité ──────────────────────────────────────────────────
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Comment && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}