// lib/screens/posts/post_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../models/post.dart';
import '../../services/api_service.dart';
import '../../utils/constants.dart';
import '../../widgets/media_gallery.dart';
import '../../widgets/mention_text.dart';
import '../profile/profile_screen.dart';

class PostDetailScreen extends StatefulWidget {
  final String postId;

  const PostDetailScreen({super.key, required this.postId});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final ApiService _api = ApiService();
  Post? _post;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPost();
  }

  Future<void> _loadPost() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.getPost(widget.postId);
      setState(() {
        _post = Post.fromJson(data);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Impossible de charger la publication : $e';
        _loading = false;
      });
    }
  }

  Future<void> _toggleLike() async {
    if (_post == null) return;
    final wasLiked = _post!.userLiked;
    setState(() {
      _post!.userLiked = !wasLiked;
      _post!.likeCount += wasLiked ? -1 : 1;
    });
    try {
      if (!wasLiked) {
        await _api.likePost(_post!.id);
      } else {
        await _api.unlikePost(_post!.id);
      }
    } catch (_) {
      setState(() {
        _post!.userLiked = wasLiked;
        _post!.likeCount += wasLiked ? 1 : -1;
      });
    }
  }

  void _openComments() {
    // TODO: Implémenter l'ouverture de CommentSheet
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ouvrir les commentaires')),
    );
  }

  void _goToProfile(String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(userId: userId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Publication'),
        backgroundColor: const Color(0xFF9E1B22),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF9E1B22)));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadPost,
              child: const Text('Réessayer'),
            ),
          ],
        ),
      );
    }
    if (_post == null) {
      return const Center(child: Text('Publication introuvable'));
    }

    final post = _post!;
    final hasGallery = post.mediaGallery != null && post.mediaGallery!.isNotEmpty;
    final mediaTypes = post.mediaTypes ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête : auteur
          Row(
            children: [
              GestureDetector(
                onTap: () => _goToProfile(post.userId),
                child: CircleAvatar(
                  radius: 24,
                  backgroundImage: post.avatarUrl != null
                      ? NetworkImage('${AppConstants.baseUrl}${post.avatarUrl}')
                      : null,
                  backgroundColor: const Color(0xFF9E1B22),
                  child: post.avatarUrl == null
                      ? Text(
                          post.fullName.isNotEmpty ? post.fullName[0].toUpperCase() : '?',
                          style: const TextStyle(color: Colors.white, fontSize: 18),
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => _goToProfile(post.userId),
                      child: Text(
                        post.fullName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    Text(
                      '@${post.username} · ${timeago.format(post.createdAt, locale: 'fr')}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (post.isInstitutional)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF006838).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'UCAC-ICAM',
                    style: TextStyle(fontSize: 10, color: Color(0xFF006838)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Contenu
          if (post.content?.isNotEmpty == true)
            MentionText(
              text: post.content!,
              style: const TextStyle(fontSize: 16, height: 1.5),
              onMentionTap: (username) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Mention @$username')),
                );
              },
            ),
          const SizedBox(height: 8),

          // Tags
          if (post.tags.isNotEmpty)
            Wrap(
              spacing: 6,
              children: post.tags.map((tag) {
                return Chip(
                  label: Text('#$tag'),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  backgroundColor: const Color(0xFF9E1B22).withOpacity(0.1),
                  labelStyle: const TextStyle(fontSize: 12, color: Color(0xFF9E1B22)),
                );
              }).toList(),
            ),
          const SizedBox(height: 12),

          // Médias
          if (hasGallery)
            MediaGallery(
              mediaUrls: post.mediaGallery!,
              mediaTypes: mediaTypes.isNotEmpty ? mediaTypes : List.filled(post.mediaGallery!.length, 'photo'),
            )
          else if (post.mediaUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                '${AppConstants.baseUrl}${post.mediaUrl}',
                width: double.infinity,
                height: 300,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.broken_image, size: 50, color: Colors.grey),
              ),
            ),
          const SizedBox(height: 16),

          // Statistiques
          Row(
            children: [
              Icon(Icons.favorite, size: 18, color: Colors.red),
              const SizedBox(width: 4),
              Text('${post.likeCount}'),
              const SizedBox(width: 16),
              Icon(Icons.comment, size: 18, color: Colors.grey),
              const SizedBox(width: 4),
              Text('${post.commentCount}'),
              const Spacer(),
              if (post.repostCount > 0) ...[
                Icon(Icons.repeat, size: 18, color: Colors.green),
                const SizedBox(width: 4),
                Text('${post.repostCount}'),
              ],
            ],
          ),
          const Divider(),

          // Actions
          Row(
            children: [
              _actionButton(
                icon: post.userLiked ? Icons.favorite : Icons.favorite_border,
                label: 'Aimer',
                color: post.userLiked ? Colors.red : Colors.grey,
                onTap: _toggleLike,
              ),
              _actionButton(
                icon: Icons.comment,
                label: 'Commenter',
                color: Colors.grey,
                onTap: _openComments,
              ),
              _actionButton(
                icon: Icons.share,
                label: 'Partager',
                color: Colors.grey,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Partage en cours...')),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}