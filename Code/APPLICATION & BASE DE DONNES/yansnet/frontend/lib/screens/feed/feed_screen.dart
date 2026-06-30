import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../models/post.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/post_card.dart';
import '../profile/profile_screen.dart';
import 'create_post_screen.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});
  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final _api = ApiService();
  final _scroll = ScrollController();
  List<Post> _posts = [];
  bool _loading = true;
  bool _loadingMore = false;
  int _page = 0;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadFeed();
    _scroll.addListener(_onScroll);
    timeago.setLocaleMessages('fr', timeago.FrMessages());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200 &&
        _hasMore &&
        !_loadingMore) {
      _loadMore();
    }
  }

  Future<void> _loadFeed({bool reset = false}) async {
    if (reset) {
      setState(() {
        _page = 0;
        _hasMore = true;
        _loading = true;
      });
    }
    try {
      final data = await _api.getFeed(page: reset ? 0 : _page);
      
      print('========== DÉBUT LOGS ==========');
      print('Nombre de posts reçus: ${data.length}');
      
      if (data.isNotEmpty) {
        print('--- PREMIER POST ---');
        print('id: ${data[0]['id']}');
        print('media_url: ${data[0]['media_url']}');
        print('media_gallery: ${data[0]['media_gallery']}');
        print('media_types: ${data[0]['media_types']}');
        print('media_type: ${data[0]['media_type']}');
      }
      
      final newPosts = data.map((j) => Post.fromJson(j)).toList();
      
      if (newPosts.isNotEmpty) {
        print('--- APRÈS PARSING ---');
        print('mediaGallery: ${newPosts[0].mediaGallery}');
        print('mediaTypes: ${newPosts[0].mediaTypes}');
      }
      print('========== FIN LOGS ==========');
      
      setState(() {
        if (reset) {
          _posts = newPosts;
        } else {
          _posts.addAll(newPosts);
        }
        _page = (reset ? 0 : _page) + 1;
        _hasMore = newPosts.length == 20;
        _loading = false;
      });
    } catch (e) {
      print('❌ Erreur _loadFeed: $e');
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur chargement: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final data = await _api.getFeed(page: _page);
      final newPosts = data.map((j) => Post.fromJson(j)).toList();
      setState(() {
        _posts.addAll(newPosts);
        _page++;
        _hasMore = newPosts.length == 20;
        _loadingMore = false;
      });
    } catch (_) {
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _deletePost(String postId) async {
    try {
      await _api.deletePost(postId);
      setState(() => _posts.removeWhere((p) => p.id == postId));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final me = auth.user;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: const Color(0xFF9E1B22),
        foregroundColor: Colors.white,
        title: const Text('YANSNET', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 3)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_box_outlined),
            onPressed: () async {
              final created = await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreatePostScreen()));
              if (created == true) _loadFeed(reset: true);
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF9E1B22)))
          : RefreshIndicator(
              color: const Color(0xFF9E1B22),
              onRefresh: () => _loadFeed(reset: true),
              child: _posts.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.newspaper, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('Aucune publication', style: TextStyle(color: Colors.grey, fontSize: 16)),
                          SizedBox(height: 8),
                          Text('Suis des étudiants pour voir leurs posts ici',
                              style: TextStyle(color: Colors.grey, fontSize: 13),
                              textAlign: TextAlign.center),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      itemCount: _posts.length + (_loadingMore ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i == _posts.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          );
                        }
                        return PostCard(
                          post: _posts[i],
                          currentUserId: me?.id ?? '',
                          isMod: auth.isModerator,
                          onDelete: () => _deletePost(_posts[i].id),
                          onProfileTap: (uid) => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => ProfileScreen(userId: uid)),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}