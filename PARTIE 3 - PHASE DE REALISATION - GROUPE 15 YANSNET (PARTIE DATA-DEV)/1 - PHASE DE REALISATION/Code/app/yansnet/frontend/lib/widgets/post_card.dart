// lib/widgets/post_card.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:share_plus/share_plus.dart';
import 'package:dio/dio.dart';
import '../models/post.dart';
import '../models/friend_action.dart';
import '../services/api_service.dart';
import '../utils/constants.dart';
import '../utils/media_utils.dart';
import 'comment_sheet.dart';
import 'media_gallery.dart';
import '../widgets/share_bottom_sheet.dart';
import '../widgets/mention_text.dart';

// =============================================================================
// PALETTE AMÉLIORÉE – Design moderne, cohérent et premium
// =============================================================================

class _Palette {
  static const primary = Color(0xFF9E1B22);
  static const primaryLight = Color(0xFFFDE8EA);
  static const primaryGradient = LinearGradient(
    colors: [Color(0xFF9E1B22), Color(0xFF7A1520)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const ink = Color(0xFF1A1A1E);
  static const inkSoft = Color(0xFF6B6B76);
  static const inkLight = Color(0xFF9E9EAB);
  static const surface = Colors.white;
  static const background = Color(0xFFF8F7F5);
  static const border = Color(0xFFEEEDEA);
  static const institutional = Color(0xFF006838);
  static const warning = Color(0xFFB8720E);
  static const success = Color(0xFF0A7E3C);

  static List<BoxShadow> cardShadow = [
    BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 4)),
    BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2)),
  ];
  static List<BoxShadow> elevatedShadow = [
    BoxShadow(color: primary.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 8)),
  ];
}

// =============================================================================
// POST CARD – DESIGN MODERNE ET PREMIUM
// =============================================================================

class PostCard extends StatefulWidget {
  final Post post;
  final String currentUserId;
  final bool isMod;
  final VoidCallback? onDelete;
  final Function(String)? onProfileTap;
  final Function(Post)? onShare;
  final VoidCallback? onRepost;

  const PostCard({
    super.key,
    required this.post,
    required this.currentUserId,
    this.isMod = false,
    this.onDelete,
    this.onProfileTap,
    this.onShare,
    this.onRepost,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> with SingleTickerProviderStateMixin {
  late bool _liked;
  late int _likeCount;
  List<Liker> _likers = [];
  bool _loadingLikers = false;

  late bool _reposted;
  late int _repostCount;
  bool _isReposting = false;

  List<SocialAction> _socialActions = [];

  final _api = ApiService();

  late final AnimationController _heartController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..addStatusListener((status) {
      if (status == AnimationStatus.completed) _heartController.reset();
    });

  @override
  void initState() {
    super.initState();
    _liked = widget.post.userLiked;
    _likeCount = widget.post.likeCount;
    _reposted = widget.post.userReposted;
    _repostCount = widget.post.repostCount;

    if (widget.post.likers != null && widget.post.likers!.isNotEmpty) {
      _likers = widget.post.likers!;
    } else {
      _loadLikers();
    }

    _buildSocialActions();
  }

  @override
  void dispose() {
    _heartController.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------------
  // Chargement des likers
  // ----------------------------------------------------------------
  Future<void> _loadLikers() async {
    if (_loadingLikers) return;
    setState(() => _loadingLikers = true);
    try {
      final likers = await _api.getLikers(widget.post.id);
      if (mounted) setState(() {
        _likers = likers;
        _loadingLikers = false;
        _buildSocialActions();
      });
    } catch (_) {
      if (mounted) setState(() => _loadingLikers = false);
    }
  }

  // ----------------------------------------------------------------
  // Construction de la liste unifiée des actions sociales
  // ----------------------------------------------------------------
  void _buildSocialActions() {
    final friendActions = <FriendAction>[];
    friendActions.addAll(widget.post.likedByFriends);
    friendActions.addAll(widget.post.repostedByFriends);

    final Map<String, SocialAction> actionMap = {};

    void addAction(String userId, String fullName, String? avatarUrl, String type) {
      if (actionMap.containsKey(userId)) {
        final existing = actionMap[userId]!;
        if (type == 'like' && existing.type != 'like_repost') {
          actionMap[userId] = SocialAction(
            userId: userId,
            fullName: fullName,
            avatarUrl: avatarUrl,
            type: 'like_repost',
          );
        } else if (type == 'repost' && existing.type != 'like_repost') {
          actionMap[userId] = SocialAction(
            userId: userId,
            fullName: fullName,
            avatarUrl: avatarUrl,
            type: 'like_repost',
          );
        }
      } else {
        actionMap[userId] = SocialAction(
          userId: userId,
          fullName: fullName,
          avatarUrl: avatarUrl,
          type: type,
        );
      }
    }

    for (final action in friendActions) {
      addAction(action.userId, action.fullName, action.avatarUrl, action.type);
    }

    if (_liked) {
      addAction(widget.currentUserId, 'Vous', null, 'like');
    }
    if (_reposted) {
      addAction(widget.currentUserId, 'Vous', null, 'repost');
    }

    final actions = actionMap.values.toList();
    actions.sort((a, b) {
      if (a.userId == widget.currentUserId) return -1;
      if (b.userId == widget.currentUserId) return 1;
      return 0;
    });

    _socialActions = actions;
  }

  // ----------------------------------------------------------------
  // Like / Unlike
  // ----------------------------------------------------------------
  Future<void> _toggleLike() async {
    final wasLiked = _liked;
    setState(() {
      _liked = !_liked;
      _likeCount += _liked ? 1 : -1;
    });
    try {
      if (_liked) {
        await _api.likePost(widget.post.id);
        final me = Liker(
          userId: widget.currentUserId,
          fullName: 'Vous',
          avatarUrl: null,
        );
        setState(() {
          _likers = [me, ..._likers.where((l) => l.userId != widget.currentUserId).toList()];
          _buildSocialActions();
        });
      } else {
        await _api.unlikePost(widget.post.id);
        setState(() {
          _likers.removeWhere((l) => l.userId == widget.currentUserId);
          _buildSocialActions();
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _liked = wasLiked;
        _likeCount += wasLiked ? 1 : -1;
        _buildSocialActions();
      });
    }
  }

  void _handleDoubleTap() {
    if (!_liked) _toggleLike();
    _heartController.forward(from: 0);
  }

  // ----------------------------------------------------------------
  // Repost / Unrepost
  // ----------------------------------------------------------------
  Future<void> _toggleRepost() async {
    if (_isReposting) return;
    final wasReposted = _reposted;
    setState(() {
      _reposted = !_reposted;
      _repostCount += _reposted ? 1 : -1;
    });
    setState(() => _isReposting = true);
    try {
      if (_reposted) {
        await _api.repost(widget.post.id);
      } else {
        await _api.unrepost(widget.post.id);
      }
      widget.onRepost?.call();
      _buildSocialActions();
    } catch (e) {
      setState(() {
        _reposted = wasReposted;
        _repostCount += wasReposted ? 1 : -1;
        _buildSocialActions();
      });
      if (!mounted) return;
      if (e is DioException && e.response?.statusCode == 404) {
        _shareInternally();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('La republication sera disponible prochainement. Utilisez le partage pour l\'instant.'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de l\'opération : $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isReposting = false);
    }
  }

  // ----------------------------------------------------------------
  // Commentaires
  // ----------------------------------------------------------------
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

  // ----------------------------------------------------------------
  // Partage interne (via la bottom sheet de l'application)
  // ----------------------------------------------------------------
  void _shareInternally() {
    if (widget.onShare != null) {
      widget.onShare!(widget.post);
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ShareBottomSheet(
        post: widget.post,
        onShare: (List<String> selectedIds, String? comment) async {
          final messageText = '📤 PARTAGE:${widget.post.id}';
          for (var userId in selectedIds) {
            await _api.sendMessage(userId, messageText);
            if (comment != null && comment.isNotEmpty) {
              await _api.sendMessage(userId, comment);
            }
          }
          if (!mounted) return;
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Publication partagée avec succès'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      ),
    );
  }

  // ----------------------------------------------------------------
  // Partage externe (via share_plus)
  // ----------------------------------------------------------------
  Future<void> _shareExternally() async {
    final post = widget.post;
    final content = post.content ?? '';
    final author = post.fullName.isNotEmpty ? post.fullName : 'Un utilisateur';
    final postId = post.id;

    final String postLink = 'yansnet://post/$postId';

    final String shareText = '''
$content

📸 Partagé depuis YANSNET
Auteur : $author
🔗 Lien vers la publication : $postLink
    '''.trim();

    try {
      await Share.share(shareText);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors du partage : $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ----------------------------------------------------------------
  // Copier le lien dans le presse-papiers
  // ----------------------------------------------------------------
  void _copyPostLink() async {
    final postId = widget.post.id;
    final String postLink = 'yansnet://post/$postId';
    try {
      await Clipboard.setData(ClipboardData(text: postLink));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Lien copié dans le presse-papiers !'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de la copie : $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ----------------------------------------------------------------
  // Menu options
  // ----------------------------------------------------------------
  void _showOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: _Palette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 4),
              _OptionTile(
                icon: Icons.share_outlined,
                label: 'Partager via...',
                color: Colors.blue,
                onTap: () {
                  Navigator.pop(context);
                  _shareExternally();
                },
              ),
              _OptionTile(
                icon: Icons.link,
                label: 'Copier le lien',
                color: Colors.blue,
                onTap: () {
                  Navigator.pop(context);
                  _copyPostLink();
                },
              ),
              if (widget.post.userId == widget.currentUserId || widget.isMod)
                _OptionTile(
                  icon: Icons.delete_outline_rounded,
                  label: 'Supprimer',
                  color: _Palette.primary,
                  onTap: () {
                    Navigator.pop(context);
                    widget.onDelete?.call();
                  },
                ),
              _OptionTile(
                icon: Icons.flag_outlined,
                label: 'Signaler',
                color: _Palette.warning,
                onTap: () {
                  Navigator.pop(context);
                  _showReportDialog();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
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
          title: const Text(
            'Signaler ce post',
            style: TextStyle(fontWeight: FontWeight.w700, color: _Palette.ink),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: reasons
                .map((r) => RadioListTile<String>(
                      value: r,
                      groupValue: reason,
                      title: Text(r, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                      activeColor: _Palette.primary,
                      dense: true,
                      onChanged: (v) => setStateDialog(() => reason = v),
                    ))
                .toList(),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler', style: TextStyle(color: _Palette.inkSoft)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _Palette.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _Palette.primary.withOpacity(0.35),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              onPressed: reason == null
                  ? null
                  : () async {
                      Navigator.pop(context);
                      try {
                        await _api.reportPost(widget.post.id, reason!);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Signalement envoyé'),
                            backgroundColor: _Palette.institutional,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            margin: const EdgeInsets.all(16),
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

  // ================================================================
  // SHOW SOCIAL ACTIONS MODAL
  // ================================================================
  void _showSocialActionsModal() {
    if (_socialActions.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Interactions',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: _socialActions.length,
                    itemBuilder: (context, index) {
                      final action = _socialActions[index];
                      return _buildSocialActionItem(action);
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSocialActionItem(SocialAction action) {
    String actionText = '';
    if (action.type == 'like') actionText = 'a aimé ceci';
    else if (action.type == 'repost') actionText = 'a republié ceci';
    else if (action.type == 'like_repost') actionText = 'a aimé et republié ceci';

    IconData actionIcon;
    if (action.type == 'like') {
      actionIcon = Icons.favorite_rounded;
    } else if (action.type == 'repost') {
      actionIcon = Icons.repeat_rounded;
    } else {
      actionIcon = Icons.favorite_rounded;
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundImage: action.avatarUrl != null
            ? NetworkImage('${AppConstants.baseUrl}${action.avatarUrl}')
            : null,
        child: action.avatarUrl == null
            ? Text(
                action.fullName.isNotEmpty ? action.fullName[0].toUpperCase() : '?',
                style: const TextStyle(fontSize: 12),
              )
            : null,
      ),
      title: Text(
        action.fullName,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(actionText),
      trailing: Icon(
        actionIcon,
        color: _Palette.primary,
        size: 20,
      ),
      onTap: () {
        widget.onProfileTap?.call(action.userId);
      },
    );
  }

  // =========================================================================
  // BUILD – DESIGN MODERNE
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final hasGallery = post.mediaGallery != null && post.mediaGallery!.isNotEmpty;

    List<String> mediaTypes;
    if (hasGallery) {
      // ✅ On recalcule toujours les types à partir des URLs (plus fiable)
      mediaTypes = post.mediaGallery!.map((url) => MediaUtils.detectType(url)).toList();
    } else {
      mediaTypes = post.mediaTypes ?? [];
    }

    Widget? socialRow;
    if (_socialActions.isNotEmpty) {
      socialRow = GestureDetector(
        onTap: _showSocialActionsModal,
        child: _buildUnifiedSocialRow(),
      );
    }

    Widget? repostHeader;
    if (post.sharedPostId != null && post.sharedPost != null) {
      repostHeader = _buildRepostHeader(post.sharedPost!);
    }

    Widget content = _buildContent(post);
    if (post.sharedPost != null) {
      content = _buildContent(post.sharedPost!);
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: _Palette.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: _Palette.cardShadow,
        border: Border.all(color: _Palette.border, width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (socialRow != null) socialRow,
            if (repostHeader != null) repostHeader,
            _buildHeader(post),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: _handleDoubleTap,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  content,
                  _HeartBurst(controller: _heartController),
                ],
              ),
            ),
            _buildActions(post),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // WIDGET : Bande sociale unifiée (moderne et élégante)
  // =========================================================================
  Widget _buildUnifiedSocialRow() {
    final displayActions = _socialActions.take(4).toList();
    final extraCount = _socialActions.length - displayActions.length;

    final textBuffer = StringBuffer();
    for (int i = 0; i < displayActions.length; i++) {
      final action = displayActions[i];
      if (i > 0) {
        if (i == displayActions.length - 1 && extraCount == 0) {
          textBuffer.write(' et ');
        } else {
          textBuffer.write(', ');
        }
      }
      String actionText = '';
      if (action.type == 'like') actionText = 'a aimé ceci';
      else if (action.type == 'repost') actionText = 'a republié ceci';
      else if (action.type == 'like_repost') actionText = 'a aimé et republié ceci';
      textBuffer.write('${action.fullName} $actionText');
    }
    if (extraCount > 0) {
      textBuffer.write(' et ${extraCount} autre${extraCount > 1 ? 's' : ''}');
    }

    final avatarWidth = 22.0 * displayActions.length + 4;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          SizedBox(
            height: 32,
            width: avatarWidth,
            child: Stack(
              clipBehavior: Clip.none,
              children: displayActions.asMap().entries.map((entry) {
                final idx = entry.key;
                final action = entry.value;
                return Positioned(
                  left: idx * 20.0,
                  top: 2,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundImage: action.avatarUrl != null
                            ? NetworkImage('${AppConstants.baseUrl}${action.avatarUrl}')
                            : null,
                        child: action.avatarUrl == null
                            ? Text(
                                action.fullName.isNotEmpty ? action.fullName[0].toUpperCase() : '?',
                                style: const TextStyle(fontSize: 10),
                              )
                            : null,
                      ),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: _Palette.primaryLight,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: Icon(
                            action.type == 'like_repost' ? Icons.favorite_rounded :
                            action.type == 'like' ? Icons.favorite_border_rounded : Icons.repeat_rounded,
                            size: 10,
                            color: _Palette.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              textBuffer.toString(),
              style: const TextStyle(fontSize: 13, color: _Palette.inkSoft, fontWeight: FontWeight.w400),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(
            Icons.arrow_forward_ios,
            size: 14,
            color: _Palette.inkLight,
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // WIDGET : En-tête de republication
  // =========================================================================
  Widget _buildRepostHeader(Post originalPost) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Icon(Icons.repeat_rounded, size: 16, color: _Palette.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: widget.post.fullName,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: _Palette.ink,
                ),
                children: const [
                  TextSpan(
                    text: ' a republié ceci',
                    style: TextStyle(fontWeight: FontWeight.normal, color: _Palette.inkSoft),
                  ),
                ],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // WIDGET : Contenu du post
  // =========================================================================
  Widget _buildContent(Post post) {
    final hasGallery = post.mediaGallery != null && post.mediaGallery!.isNotEmpty;
    List<String> mediaTypes;
    if (hasGallery) {
      mediaTypes = post.mediaGallery!.map((url) => MediaUtils.detectType(url)).toList();
    } else {
      mediaTypes = post.mediaTypes ?? [];
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (post.content?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: MentionText(
              text: post.content!,
              style: const TextStyle(
                fontSize: 15,
                height: 1.6,
                color: _Palette.ink,
                fontWeight: FontWeight.w400,
              ),
              onMentionTap: (username) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('@$username'),
                    duration: const Duration(milliseconds: 500),
                  ),
                );
              },
            ),
          ),
        if (post.tags.isNotEmpty) _buildTags(post),
        if (hasGallery)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: MediaGallery(mediaUrls: post.mediaGallery!, mediaTypes: mediaTypes),
            ),
          )
        else if (post.mediaUrl != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                '${AppConstants.baseUrl}${post.mediaUrl}',
                width: double.infinity,
                height: 260,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, loadingProgress) => loadingProgress == null
                    ? child
                    : Container(
                        height: 260,
                        color: _Palette.background,
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2, color: _Palette.primary),
                        ),
                      ),
                errorBuilder: (_, __, ___) => Container(
                  height: 140,
                  color: _Palette.background,
                  child: const Icon(Icons.broken_image_outlined, color: _Palette.inkLight),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // En-tête (auteur)
  // ---------------------------------------------------------------------
  Widget _buildHeader(Post post) {
    final ringColor = post.isInstitutional
        ? _Palette.institutional.withOpacity(0.35)
        : _Palette.ink.withOpacity(0.08);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => widget.onProfileTap?.call(post.userId),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: ringColor, width: 1.5),
              ),
              child: CircleAvatar(
                radius: 22,
                backgroundColor: _Palette.primary.withOpacity(0.08),
                backgroundImage:
                    post.avatarUrl != null ? NetworkImage('${AppConstants.baseUrl}${post.avatarUrl}') : null,
                child: post.avatarUrl == null
                    ? Text(
                        post.fullName.isNotEmpty ? post.fullName[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: _Palette.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () => widget.onProfileTap?.call(post.userId),
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          post.fullName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: _Palette.ink,
                            height: 1.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (post.isInstitutional) ...[
                        const SizedBox(width: 6),
                        const _InstitutionalBadge(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${post.username} · ${timeago.format(post.createdAt, locale: 'fr')}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: _Palette.inkSoft,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _showOptions,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.more_horiz_rounded, size: 20, color: _Palette.inkSoft),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Tags
  // ---------------------------------------------------------------------
  Widget _buildTags(Post post) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: post.tags
            .map((tag) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _Palette.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '#${tag.replaceAll('^', '')}',
                    style: const TextStyle(
                      color: _Palette.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Actions (Like, Comment, Repost, Share)
  // ---------------------------------------------------------------------
  Widget _buildActions(Post post) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
      child: Row(
        children: [
          _LikeButton(liked: _liked, count: _likeCount, onTap: _toggleLike),
          const SizedBox(width: 4),
          _ActionButton(
            icon: Icons.chat_bubble_outline_rounded,
            label: '${post.commentCount}',
            onTap: _showCommentsSheet,
          ),
          const SizedBox(width: 4),
          _ActionButton(
            icon: Icons.repeat_rounded,
            label: '$_repostCount',
            onTap: _toggleRepost,
            color: _reposted ? _Palette.primary : null,
          ),
          const Spacer(),
          Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _shareInternally,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.share_outlined, size: 20, color: _Palette.inkSoft),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// MODÈLE INTERNE : SocialAction
// =============================================================================

class SocialAction {
  final String userId;
  final String fullName;
  final String? avatarUrl;
  final String type;

  SocialAction({
    required this.userId,
    required this.fullName,
    this.avatarUrl,
    required this.type,
  });
}

// =============================================================================
// SOUS-WIDGETS
// =============================================================================

class _InstitutionalBadge extends StatelessWidget {
  const _InstitutionalBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _Palette.institutional.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _Palette.institutional.withOpacity(0.2), width: 0.5),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded, size: 12, color: _Palette.institutional),
          SizedBox(width: 3),
          Text(
            'UCAC-ICAM',
            style: TextStyle(
              fontSize: 9,
              color: _Palette.institutional,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      onTap: onTap,
    );
  }
}

class _LikeButton extends StatefulWidget {
  const _LikeButton({required this.liked, required this.count, required this.onTap});

  final bool liked;
  final int count;
  final VoidCallback onTap;

  @override
  State<_LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<_LikeButton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  @override
  void didUpdateWidget(covariant _LikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.liked && !oldWidget.liked) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.liked ? _Palette.primary : _Palette.inkSoft;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final bump = 1 + (Curves.elasticOut.transform(_controller.value) * 0.35) * (1 - _controller.value);
                  return Transform.scale(scale: 1 + (bump - 1).clamp(0.0, 0.35), child: child);
                },
                child: Icon(
                  widget.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  size: 20,
                  color: color,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '${widget.count}',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? _Palette.inkSoft;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: iconColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeartBurst extends StatelessWidget {
  const _HeartBurst({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final t = controller.value;
          if (t == 0) return const SizedBox.shrink();

          final scale = Curves.elasticOut.transform((t / 0.55).clamp(0.0, 1.0));
          final opacity = t < 0.65 ? 1.0 : (1 - ((t - 0.65) / 0.35)).clamp(0.0, 1.0);

          return Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: scale,
              child: const Icon(
                Icons.favorite_rounded,
                size: 92,
                color: Colors.white,
                shadows: [
                  Shadow(color: Colors.black26, blurRadius: 18),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}