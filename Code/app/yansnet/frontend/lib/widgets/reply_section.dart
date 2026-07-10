import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/post.dart';
import '../services/api_service.dart';
import '../utils/constants.dart';
import '../screens/profile/profile_screen.dart';

class ReplySection extends StatefulWidget {
  final Comment parentComment;
  final String currentUserId;
  final Function(String)? onProfileTap;

  const ReplySection({
    super.key,
    required this.parentComment,
    required this.currentUserId,
    this.onProfileTap,
  });

  @override
  State<ReplySection> createState() => _ReplySectionState();
}

class _ReplySectionState extends State<ReplySection> {
  final _api = ApiService();
  final _replyCtrl = TextEditingController();
  bool _showReplyInput = false;
  bool _loadingReplies = false;
  List<Comment> _replies = [];

  @override
  void initState() {
    super.initState();
    if (widget.parentComment.replies != null) {
      _replies = widget.parentComment.replies!;
    }
  }

  Future<void> _loadReplies() async {
    if (_replies.isNotEmpty) return;
    setState(() => _loadingReplies = true);
    try {
      final data = await _api.getReplies(widget.parentComment.id);
      setState(() {
        _replies = data.map((j) => Comment.fromJson(j)).toList();
        _loadingReplies = false;
      });
    } catch (e) {
      setState(() => _loadingReplies = false);
    }
  }

  Future<void> _sendReply() async {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _showReplyInput = false);
    try {
      final newReply = await _api.addReply(widget.parentComment.id, text);
      setState(() {
        _replies.insert(0, Comment.fromJson(newReply));
        widget.parentComment.replyCount = _replies.length;
      });
      _replyCtrl.clear();
    } catch (e) {}
  }

  Future<void> _toggleLikeReply(Comment reply) async {
    final wasLiked = reply.userLiked;
    setState(() {
      reply.userLiked = !wasLiked;
      reply.likeCount += wasLiked ? -1 : 1;
    });
    try {
      if (!wasLiked) {
        await _api.likeComment(reply.id);
      } else {
        await _api.unlikeComment(reply.id);
      }
    } catch (e) {
      setState(() {
        reply.userLiked = wasLiked;
        reply.likeCount += wasLiked ? 1 : -1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Bouton pour afficher les réponses
        if (widget.parentComment.replyCount > 0)
          Padding(
            padding: const EdgeInsets.only(left: 40, top: 4),
            child: GestureDetector(
              onTap: () {
                if (_replies.isEmpty) {
                  _loadReplies();
                } else {
                  setState(() => _loadingReplies = !_loadingReplies);
                }
              },
              child: Text(
                _loadingReplies 
                    ? 'Chargement...' 
                    : (_replies.isNotEmpty 
                        ? 'Masquer les réponses' 
                        : 'Afficher les ${widget.parentComment.replyCount} réponses'),
                style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        // Liste des réponses
        if (_replies.isNotEmpty && !_loadingReplies)
          Padding(
            padding: const EdgeInsets.only(left: 40, top: 8),
            child: Column(
              children: _replies.map((reply) => _buildReplyTile(reply)).toList(),
            ),
          ),
        // Bouton "Répondre"
        Padding(
          padding: const EdgeInsets.only(left: 40, top: 8),
          child: GestureDetector(
            onTap: () => setState(() => _showReplyInput = !_showReplyInput),
            child: const Text(
              'Répondre',
              style: TextStyle(fontSize: 12, color: Color(0xFF9E1B22), fontWeight: FontWeight.w500),
            ),
          ),
        ),
        // Champ pour écrire une réponse
        if (_showReplyInput)
          Padding(
            padding: const EdgeInsets.only(left: 40, top: 8, right: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _replyCtrl,
                    autofocus: true,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Écrire une réponse...',
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF9E1B22),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 14),
                    onPressed: _sendReply,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildReplyTile(Comment reply) {
    final avatarUrl = reply.avatarUrl != null ? '${AppConstants.baseUrl}${reply.avatarUrl}' : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              widget.onProfileTap?.call(reply.userId);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ProfileScreen(userId: reply.userId)),
              );
            },
            child: CircleAvatar(
              radius: 14,
              backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
              backgroundColor: const Color(0xFFF39200),
              child: avatarUrl == null
                  ? Text(reply.fullName.isNotEmpty ? reply.fullName[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontSize: 10))
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () {
                    widget.onProfileTap?.call(reply.userId);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ProfileScreen(userId: reply.userId)),
                    );
                  },
                  child: Text(
                    reply.fullName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 2),
                Text(reply.content, style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      timeago.format(reply.createdAt, locale: 'fr'),
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () => _toggleLikeReply(reply),
                      child: Row(
                        children: [
                          Icon(
                            reply.userLiked ? Icons.favorite : Icons.favorite_border,
                            size: 12,
                            color: reply.userLiked ? const Color(0xFF9E1B22) : Colors.grey,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${reply.likeCount}',
                            style: TextStyle(
                              fontSize: 10,
                              color: reply.userLiked ? const Color(0xFF9E1B22) : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}