import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/post.dart';
import '../models/comment.dart' as CommentModel;
import '../models/user.dart';
import '../services/api_service.dart';
import '../utils/constants.dart';
import '../screens/profile/profile_screen.dart';
import '../widgets/mention_text.dart';
import '../utils/mention_utils.dart';

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
  final ApiService _api = ApiService();
  final TextEditingController _commentCtrl = TextEditingController();
  final FocusNode _commentFocus = FocusNode();

  List<CommentModel.Comment> _comments = [];
  bool _loading = true;
  String? _replyingToId;
  String? _replyingToName;
  int _totalComments = 0;
  bool _sending = false; // ✅ AJOUT : indicateur d'envoi

  // ─── Variables pour les mentions ────────────────────────────
  List<User> _allUsers = [];
  List<User> _filteredUsers = [];
  OverlayEntry? _suggestionsOverlay;
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _loadComments();
    _loadUsersForMentions();
    _commentCtrl.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _commentCtrl.removeListener(_onTextChanged);
    _commentCtrl.dispose();
    _commentFocus.dispose();
    _removeSuggestionsOverlay();
    super.dispose();
  }

  // ─── Chargement des utilisateurs pour les mentions ──────────
  Future<void> _loadUsersForMentions() async {
    try {
      final data = await _api.getAllMembers();
      setState(() {
        _allUsers = data.map((j) => User.fromJson(j)).toList();
      });
    } catch (e) {
      debugPrint('❌ Erreur chargement utilisateurs : $e');
    }
  }

  // ─── Construction de l'arbre des commentaires ──────────────
  List<CommentModel.Comment> _buildTree(List<CommentModel.Comment> all) {
    final Map<String, CommentModel.Comment> map = {};
    final List<CommentModel.Comment> roots = [];

    for (var c in all) {
      map[c.id] = c;
      c.replies = [];
      c.showReplies = false;
    }

    for (var c in all) {
      final parentId = c.parentId;
      if (parentId != null && parentId.isNotEmpty && map.containsKey(parentId)) {
        map[parentId]!.replies!.add(c);
      } else {
        roots.add(c);
      }
    }

    roots.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    for (var c in map.values) {
      if (c.replies != null && c.replies!.isNotEmpty) {
        c.replies!.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        c.replyCount = c.replies!.length;
      }
    }

    return roots;
  }

  // ─── Chargement des commentaires ────────────────────────────
  Future<void> _loadComments() async {
    setState(() => _loading = true);
    try {
      final data = await _api.getComments(widget.postId);
      final all = data.map((j) {
        try {
          return CommentModel.Comment.fromJson(j);
        } catch (e) {
          print('❌ Erreur parsing: $e');
          return null;
        }
      }).whereType<CommentModel.Comment>().toList();

      _totalComments = all.length;
      final tree = _buildTree(all);
      setState(() {
        _comments = tree;
        _loading = false;
      });
      widget.onCommentCountChanged?.call(_totalComments);
    } catch (e) {
      print('❌ Erreur chargement: $e');
      setState(() => _loading = false);
    }
  }

  // ─── Charger les réponses ──────────────────────────────────
  Future<void> _loadReplies(CommentModel.Comment comment) async {
    if (comment.replies != null && comment.replies!.isNotEmpty) return;
    try {
      final data = await _api.getReplies(comment.id);
      final replies = data.map((j) => CommentModel.Comment.fromJson(j)).toList();
      setState(() {
        comment.replies = replies;
        comment.replyCount = replies.length;
        comment.showReplies = true;
        _rebuildSubtree(comment);
        _totalComments = _countAllComments();
        widget.onCommentCountChanged?.call(_totalComments);
      });
    } catch (e) {
      print('❌ Erreur chargement réponses: $e');
    }
  }

  void _rebuildSubtree(CommentModel.Comment parent) {
    if (parent.replies == null || parent.replies!.isEmpty) return;

    final Map<String, CommentModel.Comment> map = {};
    final List<CommentModel.Comment> all = [];

    void collect(CommentModel.Comment c) {
      all.add(c);
      if (c.replies != null) {
        for (var child in c.replies!) {
          collect(child);
        }
      }
    }
    collect(parent);

    for (var c in all) {
      map[c.id] = c;
      c.replies = [];
      c.showReplies = false;
    }

    for (var c in all) {
      final parentId = c.parentId;
      if (parentId != null && parentId.isNotEmpty && map.containsKey(parentId)) {
        map[parentId]!.replies!.add(c);
      }
    }

    for (var c in map.values) {
      if (c.replies != null && c.replies!.isNotEmpty) {
        c.replies!.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        c.replyCount = c.replies!.length;
        c.showReplies = c.replies!.length <= 3;
      }
    }
  }

  int _countAllComments() {
    int count = _comments.length;
    for (var c in _comments) {
      count += _countReplies(c);
    }
    return count;
  }

  int _countReplies(CommentModel.Comment c) {
    int count = c.replies?.length ?? 0;
    if (c.replies != null) {
      for (var r in c.replies!) {
        count += _countReplies(r);
      }
    }
    return count;
  }

  // ─── Envoyer un commentaire (avec détection harcèlement) ────
  Future<void> _sendComment({String? parentId}) async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    // Extraire les mentions
    final List<String> mentions = MentionUtils.extractMentions(text);

    setState(() => _sending = true);

    // 1️⃣ Détection de harcèlement (appel au serveur Data)
    try {
      final harcResult = await _api.detectHarcelement(text);
      if (harcResult['est_harcelant'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Ce commentaire est inapproprié et a été refusé.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
        setState(() => _sending = false);
        return;
      }
    } catch (e) {
      print('❌ Erreur détection harcèlement: $e');
      // On continue quand même (on pourrait bloquer si on veut être strict)
    }

    // 2️⃣ Envoi du commentaire
    try {
      await _api.addComment(widget.postId, text, parentId: parentId, mentions: mentions);
      await _loadComments();
      _commentCtrl.clear();
      setState(() {
        _replyingToId = null;
        _replyingToName = null;
        _sending = false;
      });
    } catch (e) {
      print('❌ Erreur envoi: $e');
      setState(() => _sending = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─── Like / Unlike ──────────────────────────────────────────
  Future<void> _toggleLikeComment(CommentModel.Comment comment) async {
    final wasLiked = comment.isLiked;
    setState(() {
      comment.isLiked = !wasLiked;
      comment.likeCount += wasLiked ? -1 : 1;
    });
    try {
      if (!wasLiked) await _api.likeComment(comment.id);
      else await _api.unlikeComment(comment.id);
    } catch (e) {
      setState(() {
        comment.isLiked = wasLiked;
        comment.likeCount += wasLiked ? 1 : -1;
      });
    }
  }

  void _replyTo(CommentModel.Comment comment) {
    setState(() {
      _replyingToId = comment.id;
      _replyingToName = comment.fullName;
    });
    _commentFocus.requestFocus();
  }

  void _cancelReply() {
    setState(() {
      _replyingToId = null;
      _replyingToName = null;
    });
  }

  // ════════════════════════════════════════════════════════════════
  // GESTION DES MENTIONS (autocomplétion)
  // ════════════════════════════════════════════════════════════════
  void _onTextChanged() {
    final text = _commentCtrl.text;
    final cursorPos = _commentCtrl.selection.baseOffset;
    if (cursorPos < 0) {
      _removeSuggestionsOverlay();
      return;
    }

    int atPos = -1;
    for (int i = cursorPos - 1; i >= 0; i--) {
      if (text[i] == '@') {
        atPos = i;
        break;
      }
      if (text[i] == ' ' || text[i] == '\n') break;
    }

    if (atPos != -1) {
      final query = text.substring(atPos + 1, cursorPos).toLowerCase();
      _filteredUsers = _allUsers.where((u) =>
          u.username.toLowerCase().startsWith(query) ||
          u.fullName.toLowerCase().startsWith(query)
      ).toList().take(5).toList();

      if (_filteredUsers.isNotEmpty) {
        _showSuggestions = true;
        _updateSuggestionsOverlay();
        return;
      }
    }

    _showSuggestions = false;
    _removeSuggestionsOverlay();
  }

  void _updateSuggestionsOverlay() {
    _removeSuggestionsOverlay();
    if (!_showSuggestions || _filteredUsers.isEmpty) return;

    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final Offset offset = renderBox.localToGlobal(Offset.zero);
    final Size size = renderBox.size;

    _suggestionsOverlay = OverlayEntry(
      builder: (context) => Positioned(
        width: size.width,
        top: offset.dy + size.height + 2,
        left: offset.dx,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _filteredUsers.length,
              itemBuilder: (ctx, i) {
                final user = _filteredUsers[i];
                return ListTile(
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundImage: user.avatarUrl != null
                        ? NetworkImage('${AppConstants.baseUrl}${user.avatarUrl}')
                        : null,
                    child: user.avatarUrl == null
                        ? Text(user.fullName[0].toUpperCase())
                        : null,
                  ),
                  title: Text(user.fullName),
                  subtitle: Text('@${user.username}'),
                  onTap: () {
                    _insertMention(user);
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_suggestionsOverlay!);
  }

  void _removeSuggestionsOverlay() {
    _suggestionsOverlay?.remove();
    _suggestionsOverlay = null;
  }

  void _insertMention(User user) {
    final text = _commentCtrl.text;
    final cursorPos = _commentCtrl.selection.baseOffset;

    int atPos = -1;
    for (int i = cursorPos - 1; i >= 0; i--) {
      if (text[i] == '@') {
        atPos = i;
        break;
      }
      if (text[i] == ' ' || text[i] == '\n') break;
    }
    if (atPos == -1) {
      _removeSuggestionsOverlay();
      return;
    }

    final before = text.substring(0, atPos);
    final after = text.substring(cursorPos);
    final String newText = '$before@${user.username} $after';
    final int newCursorPos = atPos + user.username.length + 2;

    _commentCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursorPos),
    );

    _showSuggestions = false;
    _removeSuggestionsOverlay();

    // Mettre à jour l'UI
    setState(() {});
  }

  // ════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════
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
                      itemBuilder: (_, i) => _buildCommentNode(_comments[i], 0),
                    ),
        ),
        _buildInputBar(),
      ],
    );
  }

  Widget _buildCommentNode(CommentModel.Comment comment, int depth) {
    final String? avatarUrl = comment.avatarUrl != null ? '${AppConstants.baseUrl}${comment.avatarUrl}' : null;
    final bool isRoot = depth == 0;
    final double leftPadding = isRoot ? 0.0 : (depth * 16.0 + 32.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: leftPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  widget.onProfileTap?.call(comment.userId);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: comment.userId)));
                },
                child: CircleAvatar(
                  radius: isRoot ? 18 : 14,
                  backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                  backgroundColor: const Color(0xFFF39200),
                  child: avatarUrl == null
                      ? Text(
                          comment.fullName.isNotEmpty ? comment.fullName[0].toUpperCase() : '?',
                          style: TextStyle(fontSize: isRoot ? 14 : 11, color: Colors.white),
                        )
                      : null,
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
                      child: Text(
                        comment.fullName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: isRoot ? 13 : 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    MentionText(
                      text: comment.content,
                      style: TextStyle(fontSize: isRoot ? 14 : 13),
                      onMentionTap: (username) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('@$username'), duration: const Duration(milliseconds: 500)),
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          timeago.format(comment.createdAt, locale: 'fr'),
                          style: TextStyle(fontSize: isRoot ? 10 : 9, color: Colors.grey),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () => _toggleLikeComment(comment),
                          child: Row(
                            children: [
                              Icon(
                                comment.isLiked ? Icons.favorite : Icons.favorite_border,
                                size: isRoot ? 14 : 12,
                                color: comment.isLiked ? const Color(0xFF9E1B22) : Colors.grey,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                '${comment.likeCount}',
                                style: TextStyle(
                                  fontSize: isRoot ? 11 : 10,
                                  color: comment.isLiked ? const Color(0xFF9E1B22) : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () => _replyTo(comment),
                          child: Text(
                            'Répondre',
                            style: TextStyle(fontSize: isRoot ? 11 : 10, color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Réponses
        if (comment.replies != null && comment.replies!.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(left: leftPadding + 16),
            child: Column(
              children: [
                if (comment.showReplies == true)
                  ...comment.replies!.map((reply) => _buildCommentNode(reply, depth + 1)),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      comment.showReplies = !comment.showReplies!;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      comment.showReplies!
                          ? 'Masquer les réponses'
                          : 'Afficher les ${comment.replies!.length} réponses',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                ),
              ],
            ),
          )
        else if (comment.replyCount > 0 && (comment.replies == null || comment.replies!.isEmpty))
          Padding(
            padding: EdgeInsets.only(left: leftPadding + 16, top: 4),
            child: GestureDetector(
              onTap: () => _loadReplies(comment),
              child: Text(
                'Afficher les ${comment.replyCount} réponses',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
          ),
        const Divider(height: 16, thickness: 0.5),
      ],
    );
  }

  // ─── Barre de saisie avec indicateur d'envoi ──────────────
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
              focusNode: _commentFocus,
              maxLines: 4,
              minLines: 1,
              decoration: InputDecoration(
                hintText: _replyingToId != null ? 'Écrire une réponse...' : 'Écrire un commentaire...',
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                suffixIcon: const Icon(Icons.alternate_email, color: Colors.grey, size: 20),
              ),
              onSubmitted: (_) => _sendComment(parentId: _replyingToId),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: const Color(0xFF9E1B22),
            child: IconButton(
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send, color: Colors.white, size: 18),
              onPressed: _sending ? null : () => _sendComment(parentId: _replyingToId),
            ),
          ),
        ],
      ),
    );
  }
}