import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:share_plus/share_plus.dart';
import '../models/post.dart';
import '../services/api_service.dart';
import '../utils/constants.dart';
import 'comment_sheet.dart';
import 'media_gallery.dart';

const Color _red = Color(0xFF9E1B22);
const Color _green = Color(0xFF006838);

class PostCard extends StatefulWidget {
  final Post post;
  final String currentUserId;
  final bool isMod;
  final VoidCallback? onDelete;
  final Function(String)? onProfileTap;

  const PostCard({
    super.key,
    required this.post,
    required this.currentUserId,
    this.isMod = false,
    this.onDelete,
    this.onProfileTap,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late bool _liked;
  late int _likeCount;
  int _lastTap = 0;
  final _api = ApiService();

  @override
  void initState() {
    super.initState();
    _liked = widget.post.userLiked;
    _likeCount = widget.post.likeCount;
  }

  Future<void> _toggleLike() async {
    final wasLiked = _liked;
    setState(() {
      _liked = !_liked;
      _likeCount += _liked ? 1 : -1;
    });
    try {
      if (_liked) {
        await _api.likePost(widget.post.id);
      } else {
        await _api.unlikePost(widget.post.id);
      }
    } catch (_) {
      setState(() {
        _liked = wasLiked;
        _likeCount += wasLiked ? 1 : -1;
      });
    }
  }

  void _doubleTap() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastTap < 350 && !_liked) _toggleLike();
    _lastTap = now;
  }

  void _showCommentsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: CommentSheet(
              postId: widget.post.id,
              currentUserId: widget.currentUserId,
              onProfileTap: widget.onProfileTap,
              onCommentCountChanged: (newCount) {
                setState(() {
                  widget.post.commentCount = newCount;
                });
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _sharePost() async {
    final shareText = '${widget.post.content ?? ''}\n📸 Partagé depuis YANSNET';
    await Share.share(shareText);
  }

  void _showOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
            if (widget.post.userId == widget.currentUserId || widget.isMod)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                title: const Text('Supprimer', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500)),
                onTap: () {
                  Navigator.pop(context);
                  widget.onDelete?.call();
                },
              ),
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: Colors.orange),
              title: const Text('Signaler', style: TextStyle(fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(context);
                _showReportDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showReportDialog() {
    String? reason;
    const reasons = ['Contenu inapproprié', 'Harcèlement', 'Spam', 'Fausses informations', 'Autre'];
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Signaler ce post', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: reasons.map((r) => RadioListTile<String>(
              value: r,
              groupValue: reason,
              title: Text(r, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              activeColor: _red,
              dense: true,
              onChanged: (v) => setStateDialog(() => reason = v),
            )).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context), 
              child: const Text('Annuler', style: TextStyle(color: Colors.grey))
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _red, 
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              onPressed: reason == null ? null : () async {
                Navigator.pop(context);
                try {
                  await _api.reportPost(widget.post.id, reason!);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Signalement envoyé'), 
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } catch (_) {}
              },
              child: const Text('Signaler'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final hasGallery = post.mediaGallery != null && post.mediaGallery!.isNotEmpty;
    
    List<String> mediaTypes = post.mediaTypes ?? [];
    if (mediaTypes.isEmpty && hasGallery) {
      mediaTypes = List.filled(post.mediaGallery!.length, 'photo');
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.withOpacity(0.15), width: 1),
      ),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ============================================================
          // EN-TÊTE
          // ============================================================
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => widget.onProfileTap?.call(post.userId),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFF39200).withOpacity(0.3), width: 1.5),
                    ),
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: const Color(0xFFF39200).withOpacity(0.1),
                      backgroundImage: post.avatarUrl != null 
                          ? NetworkImage('${AppConstants.baseUrl}${post.avatarUrl}') 
                          : null,
                      child: post.avatarUrl == null 
                          ? Text(
                              post.fullName.isNotEmpty ? post.fullName[0].toUpperCase() : '?',
                              style: const TextStyle(color: Color(0xFFF39200), fontWeight: FontWeight.bold),
                            ) 
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => widget.onProfileTap?.call(post.userId),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                post.fullName, 
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.black87),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (post.isInstitutional) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _green.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: _green.withOpacity(0.3), width: 0.5),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.verified_rounded, size: 11, color: _green),
                                    SizedBox(width: 3),
                                    Text(
                                      'UCAC-ICAM', 
                                      style: TextStyle(fontSize: 9, color: _green, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '@${post.username} · ${timeago.format(post.createdAt, locale: 'fr')}', 
                          style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w400),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.more_horiz_rounded, size: 20, color: Colors.grey[600]), 
                  onPressed: _showOptions,
                ),
              ],
            ),
          ),

          // ============================================================
          // CONTENU TEXTE
          // ============================================================
          if (post.content?.isNotEmpty == true)
            GestureDetector(
              onTap: _doubleTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  post.content!, 
                  style: const TextStyle(fontSize: 15, height: 1.5, color: Colors.black87),
                ),
              ),
            ),

          // ============================================================
          // TAGS
          // ============================================================
          if (post.tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: post.tags.map((tag) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _red.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '#${tag.replaceAll('^', '')}',
                    style: const TextStyle(color: _red, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                )).toList(),
              ),
            ),

          // ============================================================
          // GALERIE MÉDIA
          // ============================================================
          if (hasGallery)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: MediaGallery(
                  mediaUrls: post.mediaGallery!,
                  mediaTypes: mediaTypes,
                ),
              ),
            )
          else if (post.mediaUrl != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: GestureDetector(
                  onTap: _doubleTap,
                  child: Image.network(
                    '${AppConstants.baseUrl}${post.mediaUrl}',
                    width: double.infinity,
                    height: 260,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, child, loadingProgress) => loadingProgress == null ? child : Container(
                      height: 260,
                      color: Colors.grey[50],
                      child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: _red)),
                    ),
                    errorBuilder: (_, __, ___) => Container(
                      height: 140,
                      color: Colors.grey[100],
                      child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
                    ),
                  ),
                ),
              ),
            ),

          // ============================================================
          // ACTIONS
          // ============================================================
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Row(
              children: [
                _buildActionButton(
                  icon: _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: _liked ? _red : Colors.grey[600]!,
                  label: '$_likeCount',
                  onTap: _toggleLike,
                ),
                const SizedBox(width: 8),
                _buildActionButton(
                  icon: Icons.chat_bubble_outline_rounded,
                  color: Colors.grey[600]!,
                  label: '${post.commentCount}',
                  onTap: _showCommentsSheet,
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.share_outlined, size: 20, color: Colors.grey[600]),
                  onPressed: _sharePost,
                  splashRadius: 22,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper Widget pour harmoniser les boutons d'actions (Like / Comment)
  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}