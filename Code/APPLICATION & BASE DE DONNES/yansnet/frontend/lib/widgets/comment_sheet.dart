import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/post.dart';
import '../services/api_service.dart';
import '../utils/constants.dart';
import '../screens/profile/profile_screen.dart';

class CommentSheet extends StatefulWidget {
  final String postId;
  final String currentUserId;
  final Function(String)? onProfileTap;
  final Function(int)? onCommentCountChanged;

  const CommentSheet({
    super.key,
    required this.postId,
    required this.currentUserId,
    this.onProfileTap,
    this.onCommentCountChanged,
  });

  @override
  State<CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<CommentSheet> {
  final _api = ApiService();
  final _commentCtrl = TextEditingController();
  List<Comment> _comments = [];
  bool _loading = true;
  String? _replyingToId;
  String? _replyingToName;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  Future<void> _loadComments() async {
    setState(() => _loading = true);
    try {
      final data = await _api.getComments(widget.postId);
      setState(() {
        _comments = data.map((j) => Comment.fromJson(j)).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadReplies(Comment comment) async {
    if (comment.replies != null && comment.replies!.isNotEmpty) return;
    try {
      final data = await _api.getReplies(comment.id);
      setState(() {
        comment.replies = data.map((j) => Comment.fromJson(j)).toList();
        comment.showReplies = true;
      });
    } catch (e) {}
  }

  Future<void> _sendComment({String? parentId}) async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _replyingToId = null;
      _replyingToName = null;
    });
    try {
      final newComment = await _api.addComment(widget.postId, text, parentId: parentId);
      if (parentId == null) {
        setState(() {
          _comments.insert(0, Comment.fromJson(newComment));
        });
        widget.onCommentCountChanged?.call(_comments.length);
      } else {
        await _loadComments();
      }
      _commentCtrl.clear();
    } catch (e) {}
  }

  Future<void> _toggleLikeComment(Comment comment) async {
    final wasLiked = comment.userLiked;
    setState(() {
      comment.userLiked = !wasLiked;
      comment.likeCount += wasLiked ? -1 : 1;
    });
    try {
      if (!wasLiked) {
        await _api.likeComment(comment.id);
      } else {
        await _api.unlikeComment(comment.id);
      }
    } catch (e) {
      setState(() {
        comment.userLiked = wasLiked;
        comment.likeCount += wasLiked ? 1 : -1;
      });
    }
  }

  void _replyTo(Comment comment) {
    setState(() {
      _replyingToId = comment.id;
      _replyingToName = comment.fullName;
    });
    FocusScope.of(context).requestFocus(FocusNode());
  }

  void _cancelReply() {
    setState(() {
      _replyingToId = null;
      _replyingToName = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
          ),
          child: Row(
            children: [
              const Text('Commentaires', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
        ),
        if (_replyingToId != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.grey[100],
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Réponse à @$_replyingToName',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: _cancelReply,
                ),
              ],
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF9E1B22)))
              : _comments.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey),
                          SizedBox(height: 12),
                          Text('Aucun commentaire', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _comments.length,
                      itemBuilder: (_, i) => _buildCommentTile(_comments[i]),
                    ),
        ),
        _buildInputBar(),
      ],
    );
  }

  Widget _buildCommentTile(Comment comment) {
    final avatarUrl = comment.avatarUrl != null ? '${AppConstants.baseUrl}${comment.avatarUrl}' : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () {
                Navigator.pop(context);
                widget.onProfileTap?.call(comment.userId);
                Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: comment.userId)));
              },
              child: CircleAvatar(
                radius: 18,
                backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                backgroundColor: const Color(0xFFF39200),
                child: avatarUrl == null ? Text(comment.fullName.isNotEmpty ? comment.fullName[0].toUpperCase() : '?') : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      widget.onProfileTap?.call(comment.userId);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: comment.userId)));
                    },
                    child: Text(comment.fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                  const SizedBox(height: 2),
                  Text(comment.content, style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(timeago.format(comment.createdAt, locale: 'fr'), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () => _toggleLikeComment(comment),
                        child: Row(
                          children: [
                            Icon(comment.userLiked ? Icons.favorite : Icons.favorite_border, size: 14, color: comment.userLiked ? const Color(0xFF9E1B22) : Colors.grey),
                            const SizedBox(width: 2),
                            Text('${comment.likeCount}', style: TextStyle(fontSize: 11, color: comment.userLiked ? const Color(0xFF9E1B22) : Colors.grey)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () => _replyTo(comment),
                        child: const Text('Répondre', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (comment.replies != null && comment.replies!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 40, top: 8),
            child: Column(
              children: [
                ...comment.replies!.map((reply) => _buildReplyTile(reply)),
                GestureDetector(
                  onTap: () => setState(() => comment.showReplies = false),
                  child: const Text('Masquer les réponses', style: TextStyle(fontSize: 11, color: Colors.grey)),
                ),
              ],
            ),
          )
        else if (comment.replyCount > 0)
          Padding(
            padding: const EdgeInsets.only(left: 40, top: 4),
            child: GestureDetector(
              onTap: () => _loadReplies(comment),
              child: Text('Afficher les ${comment.replyCount} réponses', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ),
          ),
        const Divider(height: 16, thickness: 0.5),
      ],
    );
  }

  Widget _buildReplyTile(Comment reply) {
    final avatarUrl = reply.avatarUrl != null ? '${AppConstants.baseUrl}${reply.avatarUrl}' : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              Navigator.pop(context);
              widget.onProfileTap?.call(reply.userId);
              Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: reply.userId)));
            },
            child: CircleAvatar(
              radius: 14,
              backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
              backgroundColor: const Color(0xFFF39200),
              child: avatarUrl == null ? Text(reply.fullName.isNotEmpty ? reply.fullName[0].toUpperCase() : '?') : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    widget.onProfileTap?.call(reply.userId);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: reply.userId)));
                  },
                  child: Text(reply.fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                const SizedBox(height: 2),
                Text(reply.content, style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(timeago.format(reply.createdAt, locale: 'fr'), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () => _toggleLikeComment(reply),
                      child: Row(
                        children: [
                          Icon(reply.userLiked ? Icons.favorite : Icons.favorite_border, size: 12, color: reply.userLiked ? const Color(0xFF9E1B22) : Colors.grey),
                          const SizedBox(width: 2),
                          Text('${reply.likeCount}', style: TextStyle(fontSize: 10, color: reply.userLiked ? const Color(0xFF9E1B22) : Colors.grey)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () => _replyTo(reply),
                      child: const Text('Répondre', style: TextStyle(fontSize: 10, color: Colors.grey)),
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

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commentCtrl,
              autofocus: false,
              maxLines: null,
              decoration: InputDecoration(
                hintText: _replyingToId != null ? 'Écrire une réponse...' : 'Écrire un commentaire...',
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: const Color(0xFF9E1B22),
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white, size: 18),
              onPressed: () => _sendComment(parentId: _replyingToId),
            ),
          ),
        ],
      ),
    );
  }
}