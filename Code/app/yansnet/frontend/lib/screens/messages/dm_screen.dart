// lib/screens/messages/dm_screen.dart
import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cross_file/cross_file.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../../models/message.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/socket_service.dart';
import '../../utils/constants.dart';
import '../../utils/message_utils.dart';
import '../../utils/media_utils.dart';
import 'dm_info_screen.dart';
import '../../widgets/shared_post_card.dart';
import '../posts/post_detail_screen.dart';
import '../../widgets/media_preview_screen.dart'; // 👈 NOUVEAU

const _kBrand = Color(0xFF9E1B22);
const _kBrandDark = Color(0xFF7A1219);

// ─── Structure pour l’épinglage ──────────────────────────────
class _PinnedInfo {
  final String id;
  final String content;
  final String sender;
  _PinnedInfo({required this.id, required this.content, required this.sender});
  Map<String, dynamic> toJson() => {'id': id, 'content': content, 'sender': sender};
  factory _PinnedInfo.fromJson(Map<String, dynamic> j) => _PinnedInfo(
        id: (j['id'] ?? '').toString(),
        content: (j['content'] ?? '').toString(),
        sender: (j['sender'] ?? '').toString(),
      );
}

// ─── Animation ─────────────────────────────────────────────────
class _FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int index;
  const _FadeSlideIn({super.key, required this.child, required this.index});

  @override
  State<_FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<_FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final Animation<double> _fade = CurvedAnimation(parent: _c, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.10),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    final delay = Duration(milliseconds: widget.index.clamp(0, 8) * 45);
    Future.delayed(delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

// ─── Glissement pour répondre ──────────────────────────────────
class _SwipeToReply extends StatefulWidget {
  final Widget child;
  final bool isMe;
  final VoidCallback onReply;
  const _SwipeToReply({required this.child, required this.isMe, required this.onReply});

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> {
  double _dx = 0;
  bool _triggered = false;
  static const double _maxDrag = 64;

  void _onUpdate(DragUpdateDetails d) {
    setState(() {
      _dx += d.delta.dx;
      _dx = _dx.clamp(-_maxDrag, _maxDrag);
      if (!_triggered && _dx.abs() > _maxDrag * 0.75) {
        _triggered = true;
        HapticFeedback.mediumImpact();
      }
    });
  }

  void _onEnd(DragEndDetails d) {
    if (_dx.abs() > _maxDrag * 0.6) widget.onReply();
    setState(() {
      _dx = 0;
      _triggered = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: (_dx.abs() / _maxDrag).clamp(0, 1),
            child: const Icon(Icons.reply_rounded, color: _kBrand, size: 22),
          ),
          AnimatedContainer(
            duration: _dx == 0 ? const Duration(milliseconds: 220) : Duration.zero,
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(_dx, 0, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

// ─── Shimmer ──────────────────────────────────────────────────
class _ShimmerBlock extends StatefulWidget {
  final double width;
  final double height;
  final bool isMe;
  const _ShimmerBlock({required this.width, required this.height, required this.isMe});

  @override
  State<_ShimmerBlock> createState() => _ShimmerBlockState();
}

class _ShimmerBlockState extends State<_ShimmerBlock> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: (widget.isMe ? _kBrand : Colors.grey).withOpacity(0.08 + _c.value * 0.10),
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    );
  }
}

// ─── LECTEUR VIDÉO POUR MESSAGE ──────────────────────────────
class _VideoMessagePlayer extends StatefulWidget {
  final String fileUrl;
  final bool isMe;
  const _VideoMessagePlayer({required this.fileUrl, required this.isMe});

  @override
  State<_VideoMessagePlayer> createState() => _VideoMessagePlayerState();
}

class _VideoMessagePlayerState extends State<_VideoMessagePlayer> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      final fullUrl = widget.fileUrl.startsWith('http')
          ? widget.fileUrl
          : '${AppConstants.baseUrl}${widget.fileUrl}';
      _controller = VideoPlayerController.networkUrl(Uri.parse(fullUrl));
      await _controller!.initialize();
      setState(() {
        _initialized = true;
        _isPlaying = false;
      });
    } catch (e) {
      print('❌ Erreur init vidéo message: $e');
      setState(() => _initialized = true);
    }
  }

  void _togglePlay() {
    if (_controller == null) return;
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
        _isPlaying = false;
      } else {
        _controller!.play();
        _isPlaying = true;
      }
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return Container(
        width: 200,
        height: 150,
        color: Colors.grey[900],
        child: const Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    if (_controller == null) {
      return Container(
        width: 200,
        height: 150,
        color: Colors.grey[900],
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.white70),
              Text('Vidéo indisponible', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: _togglePlay,
      child: Container(
        width: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: Colors.black,
        ),
        child: AspectRatio(
          aspectRatio: _controller!.value.aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(_controller!),
              if (!_controller!.value.isPlaying)
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow, color: Colors.white, size: 28),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── SCREEN PRINCIPAL ──────────────────────────────────────────

class DmScreen extends StatefulWidget {
  final String receiverId;
  final String receiverName;
  final bool isGroup;
  final String? groupRole;

  const DmScreen({
    super.key,
    required this.receiverId,
    required this.receiverName,
    this.isGroup = false,
    this.groupRole,
  });

  @override
  State<DmScreen> createState() => _DmScreenState();
}

class _DmScreenState extends State<DmScreen> {
  final ApiService _api = ApiService();
  final SocketService _socket = SocketService();
  final TextEditingController _ctrl = TextEditingController();

  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();

  List<Message> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _isDeleting = false;
  String _meId = '';
  bool _isBlocked = false;
  bool _loadingBlockStatus = true;
  String _myGlobalRole = '';

  Message? _replyingTo;
  _PinnedInfo? _pinnedInfo;
  String? _highlightedMessageId;

  final Map<String, Future<Map<String, dynamic>>> _postFutures = {};
  final Set<String> _animatedIds = {};

  late StreamSubscription _messageSubscription;
  late StreamSubscription _groupMessageSubscription;
  late VoidCallback _reconnectCallback;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _meId = auth.user?.id ?? '';
    _myGlobalRole = auth.user?.role ?? '';

    _loadConversation();
    _loadBlockStatus();
    _loadPinnedMessage();

    _messageSubscription = _socket.onNewMessageStream.listen(_handleNewMessage);
    _groupMessageSubscription = _socket.onNewGroupMessageStream.listen(_handleNewMessage);

    _reconnectCallback = () {
      print('🔄 [dm_screen] Reconnexion détectée');
      _loadConversation();
    };
    _socket.addReconnectListener(_reconnectCallback);

    _socket.onMessageDeleted((data) {
      if (!mounted) return;
      final messageId = data['messageId']?.toString();
      if (messageId != null) {
        setState(() => _messages.removeWhere((m) => m.id == messageId));
      }
    });
    _socket.onGroupMessageDeleted((data) {
      if (!mounted) return;
      final messageId = data['messageId']?.toString();
      if (messageId != null && data['groupId']?.toString() == widget.receiverId) {
        setState(() => _messages.removeWhere((m) => m.id == messageId));
      }
    });
    // Ajout des écouteurs pour modification et suppression pour moi
    _socket.onMessageEdited((data) {
      if (!mounted) return;
      final edited = Message.fromJson(data);
      final index = _messages.indexWhere((m) => m.id == edited.id);
      if (index != -1) setState(() => _messages[index] = edited);
    });
    _socket.onMessageDeletedForMe((data) {
      if (!mounted) return;
      final messageId = data['messageId']?.toString();
      if (messageId != null) setState(() => _messages.removeWhere((m) => m.id == messageId));
    });
  }

  @override
  void didUpdateWidget(DmScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.receiverId != widget.receiverId) {
      setState(() {
        _pinnedInfo = null;
        _animatedIds.clear();
        _postFutures.clear();
      });
      _loadBlockStatus();
      _loadConversation();
      _loadPinnedMessage();
    }
  }

  @override
  void dispose() {
    _messageSubscription.cancel();
    _groupMessageSubscription.cancel();
    _socket.removeReconnectListener(_reconnectCallback);
    _socket.removeListener('message_deleted');
    _socket.removeListener('group_message_deleted');
    _socket.removeListener('message_edited');
    _socket.removeListener('message_deleted_for_me');
    _ctrl.dispose();
    super.dispose();
  }

  void _handleNewMessage(Map<String, dynamic> data) {
    final senderId = data['senderId']?.toString() ?? data['sender_id']?.toString() ?? '';
    final receiverId = data['receiverId']?.toString() ?? data['receiver_id']?.toString() ?? '';

    bool isForMe = false;
    if (widget.isGroup) {
      final groupId = data['groupId']?.toString() ?? data['group_id']?.toString() ?? '';
      if (groupId == widget.receiverId) isForMe = true;
    } else {
      if (senderId == widget.receiverId || receiverId == widget.receiverId) isForMe = true;
    }
    if (!isForMe || !mounted) return;

    final incoming = Message.fromJson({
      ...data,
      'sender_id': senderId,
      'receiver_id': receiverId,
    });
    if (_messages.any((m) => m.id == incoming.id)) return;

    setState(() => _messages.add(incoming));
    _scrollToBottom();

    if (!widget.isGroup && incoming.senderId != _meId) {
      _api.markAsRead(incoming.id);
      _socket.markRead(incoming.id);
    }
  }

  Future<void> _loadBlockStatus() async {
    if (widget.isGroup) {
      setState(() => _loadingBlockStatus = false);
      return;
    }
    try {
      final blocked = await _api.isUserBlocked(widget.receiverId);
      if (mounted) setState(() {
        _isBlocked = blocked;
        _loadingBlockStatus = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loadingBlockStatus = false);
    }
  }

  Future<void> _loadConversation() async {
    try {
      List<dynamic> data;
      if (widget.isGroup) {
        data = await _api.getGroupMessages(widget.receiverId);
      } else {
        data = await _api.getConversation(widget.receiverId);
      }
      setState(() {
        _messages = data.map((j) => Message.fromJson(j)).toList();
        _loading = false;
      });
      _scrollToBottom();

      if (!widget.isGroup) {
        for (final m in _messages.where((m) => !m.isRead && m.senderId == widget.receiverId)) {
          _api.markAsRead(m.id);
        }
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (_itemScrollController.isAttached && _messages.isNotEmpty) {
          _itemScrollController.scrollTo(
            index: _messages.length - 1,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
          );
        }
      });
    });
  }

  String get _pinStorageKey => 'pinned_message_${widget.receiverId}';

  Future<void> _loadPinnedMessage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pinStorageKey);
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (mounted) setState(() => _pinnedInfo = _PinnedInfo.fromJson(data));
    } catch (_) {}
  }

  Future<void> _savePinnedMessage(Message? msg) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (msg == null) {
        await prefs.remove(_pinStorageKey);
        return;
      }
      final cleanContent = _getCleanContent(msg);
      final info = _PinnedInfo(
        id: msg.id,
        content: cleanContent.isNotEmpty ? cleanContent : (msg.fileName ?? 'Fichier'),
        sender: msg.senderUsername ?? (msg.senderId == _meId ? 'Vous' : widget.receiverName),
      );
      await prefs.setString(_pinStorageKey, jsonEncode(info.toJson()));
    } catch (_) {}
  }

  void _replyTo(Message msg) {
    HapticFeedback.selectionClick();
    setState(() => _replyingTo = msg);
    FocusScope.of(context).requestFocus(FocusNode());
  }

  void _cancelReply() => setState(() => _replyingTo = null);

  String _getCleanContent(Message msg) {
    if (msg.content == null) return '';
    final lines = msg.content!.split('\n');
    final cleaned = lines.where((line) => !line.trimLeft().startsWith('> ')).toList();
    return cleaned.join('\n').trim();
  }

  (String quoteBlock, String? replyToId) _buildQuoteBlock(Message? replyingTo) {
    if (replyingTo == null) return ('', null);
    final parent = replyingTo;
    final parentClean = _getCleanContent(parent);
    final parentSender = parent.senderUsername ?? 'Membre';
    List<String> quoteLines = [
      '> $parentSender: ${parentClean.isNotEmpty ? parentClean : 'Fichier'}'
    ];
    if (parent.replyToId != null && parent.replyToId!.isNotEmpty) {
      final grandParent = _messages.firstWhere(
        (m) => m.id == parent.replyToId,
        orElse: () => Message(
          id: '',
          senderId: '',
          receiverId: '',
          content: '',
          isRead: false,
          isEdited: false,
          isDeleted: false,
          createdAt: DateTime.now(),
        ),
      );
      if (grandParent.id.isNotEmpty) {
        final grandParentClean = _getCleanContent(grandParent);
        final grandParentSender = grandParent.senderUsername ?? 'Membre';
        quoteLines.add('> $grandParentSender: ${grandParentClean.isNotEmpty ? grandParentClean : 'Fichier'}');
      }
    }
    final quoteBlock = quoteLines.join('\n');
    return (quoteBlock, parent.id);
  }

  Future<void> _deleteMessage(Message msg) async {
    if (_isDeleting) return;
    final bool canDelete = msg.senderId == _meId ||
        _myGlobalRole == 'admin' ||
        (widget.isGroup && widget.groupRole == 'admin');

    if (!canDelete) {
      _showError('Vous ne pouvez pas supprimer ce message.');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer le message ?'),
        content: Text('Voulez-vous vraiment supprimer ce message ${msg.content != null ? ' : "${msg.content!.substring(0, msg.content!.length > 30 ? 30 : msg.content!.length)}..."' : ''} ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isDeleting = true);
    try {
      if (widget.isGroup) {
        await _api.deleteGroupMessage(widget.receiverId, msg.id);
      } else {
        await _api.deleteMessage(msg.id);
      }
      setState(() {
        _messages.removeWhere((m) => m.id == msg.id);
        _isDeleting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message supprimé'), backgroundColor: Colors.green),
      );
    } catch (e) {
      setState(() => _isDeleting = false);
      _showError('Erreur lors de la suppression : $e');
    }
  }

  Future<void> _deleteForMe(Message msg) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer le message ?'),
        content: const Text('Ce message sera supprimé uniquement pour vous.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('Supprimer pour moi'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _isDeleting = true);
    try {
      if (widget.isGroup) {
        await _api.deleteGroupMessageForMe(widget.receiverId, msg.id);
      } else {
        await _api.deleteMessageForMe(msg.id);
      }
      setState(() {
        _messages.removeWhere((m) => m.id == msg.id);
        _isDeleting = false;
      });
    } catch (e) {
      setState(() => _isDeleting = false);
      _showError('Erreur: $e');
    }
  }

  Future<void> _editMessage(Message msg) async {
    final controller = TextEditingController(text: _getCleanContent(msg));
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Modifier le message'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Nouveau contenu...', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _kBrand),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (result == true && controller.text.trim().isNotEmpty) {
      setState(() => _isDeleting = true);
      try {
        final updated = await _api.editMessage(msg.id, controller.text.trim());
        final index = _messages.indexWhere((m) => m.id == msg.id);
        if (index != -1) {
          setState(() {
            _messages[index] = Message.fromJson({
              ..._messages[index].toJson(),
              'content': updated['content'],
              'is_edited': true,
            });
            _isDeleting = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Message modifié'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        setState(() => _isDeleting = false);
        _showError('Erreur modification: $e');
      }
    }
  }

  void _showMessageOptions(int index) {
    if (index < 0 || index >= _messages.length) return;
    final msg = _messages[index];
    final isCurrentlyPinned = (_pinnedInfo?.id == msg.id);
    final bool canDelete = msg.senderId == _meId ||
        _myGlobalRole == 'admin' ||
        (widget.isGroup && widget.groupRole == 'admin');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 10),
            _optionTile(
              icon: Icons.reply_rounded,
              color: _kBrand,
              label: 'Répondre',
              onTap: () { Navigator.pop(ctx); _replyTo(msg); },
            ),
            if (msg.senderId == _meId && !msg.isDeleted)
              _optionTile(
                icon: Icons.edit_rounded,
                color: Colors.blue,
                label: 'Modifier',
                onTap: () { Navigator.pop(ctx); _editMessage(msg); },
              ),
            _optionTile(
              icon: isCurrentlyPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
              color: Colors.amber[800]!,
              label: isCurrentlyPinned ? 'Désépingler' : 'Épingler',
              onTap: () async {
                Navigator.pop(ctx);
                if (isCurrentlyPinned) {
                  setState(() => _pinnedInfo = null);
                  await _savePinnedMessage(null);
                } else {
                  await _savePinnedMessage(msg);
                  setState(() => _pinnedInfo = _PinnedInfo(
                        id: msg.id,
                        content: _getCleanContent(msg).isNotEmpty ? _getCleanContent(msg) : (msg.fileName ?? 'Fichier'),
                        sender: msg.senderUsername ?? (msg.senderId == _meId ? 'Vous' : widget.receiverName),
                      ));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Message épinglé'), behavior: SnackBarBehavior.floating),
                  );
                }
              },
            ),
            _optionTile(
              icon: Icons.delete_outline_rounded,
              color: Colors.orange,
              label: 'Supprimer pour moi',
              onTap: () { Navigator.pop(ctx); _deleteForMe(msg); },
            ),
            if (canDelete)
              _optionTile(
                icon: Icons.delete_forever_rounded,
                color: Colors.red,
                label: 'Supprimer pour tout le monde',
                onTap: () { Navigator.pop(ctx); _deleteMessage(msg); },
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _optionTile({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      onTap: onTap,
    );
  }

  void _scrollToMessage(String messageId) {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index == -1) {
      _showError('Message introuvable (il est peut-être trop ancien)');
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _highlightedMessageId = messageId);
    if (_itemScrollController.isAttached) {
      _itemScrollController.scrollTo(
        index: index,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
        alignment: 0.35,
      );
    }
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted && _highlightedMessageId == messageId) setState(() => _highlightedMessageId = null);
    });
  }

  Widget _buildQuoteWidget(Message msg) {
    final content = msg.content ?? '';
    final lines = content.split('\n').where((line) => line.trimLeft().startsWith('> ')).toList();
    if (lines.isEmpty) return const SizedBox.shrink();

    final children = <Widget>[];
    final List<String?> targetIds = [];
    if (msg.replyToId != null && msg.replyToId!.isNotEmpty) targetIds.add(msg.replyToId);

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final targetId = (i < targetIds.length) ? targetIds[i] : null;
      final canNavigate = targetId != null && targetId.isNotEmpty;
      final regex = RegExp(r'^> @?([^:]+):\s*(.*)');
      final match = regex.firstMatch(line);
      if (match != null) {
        final author = match.group(1)?.trim() ?? '';
        final contentPart = match.group(2)?.trim() ?? '';
        children.add(
          GestureDetector(
            onTap: canNavigate ? () => _scrollToMessage(targetId) : null,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (author.isNotEmpty)
                    Text(author, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _kBrand)),
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          contentPart,
                          style: TextStyle(
                            fontSize: 12,
                            color: canNavigate ? Colors.blue[700] : Colors.black54,
                            decoration: canNavigate ? TextDecoration.underline : null,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (canNavigate) Icon(Icons.arrow_forward_ios_rounded, size: 10, color: Colors.blue[300]),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }
    if (children.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
        border: const Border(left: BorderSide(color: _kBrand, width: 3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _buildReplyBar() {
    return Container(
      key: const ValueKey('reply_bar'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: const Border(top: BorderSide(color: Color(0xFFE5E5E5))),
      ),
      child: Row(
        children: [
          Container(width: 3, height: 34, decoration: BoxDecoration(color: _kBrand, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Réponse à ${_replyingTo!.senderUsername ?? 'Membre'}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _kBrand)),
                const SizedBox(height: 2),
                Text(_replyingTo!.content ?? 'Fichier joint', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Colors.black54)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: Colors.grey[600]),
            onPressed: _cancelReply,
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    if (_isBlocked && !widget.isGroup) {
      _showError('Vous ne pouvez pas envoyer de message car vous avez bloqué cet utilisateur (ou il vous a bloqué).');
      return;
    }
    _ctrl.clear();

    String finalContent = text;
    String? replyToId;
    if (_replyingTo != null) {
      final (quoteBlock, replyId) = _buildQuoteBlock(_replyingTo);
      replyToId = replyId;
      if (quoteBlock.isNotEmpty) finalContent = '$quoteBlock\n\n$text';
    }

    final tempId = 'temp-${DateTime.now().millisecondsSinceEpoch}';
    final temp = Message(
      id: tempId,
      senderId: _meId,
      receiverId: widget.receiverId,
      content: finalContent,
      isRead: false,
      isEdited: false,
      isDeleted: false,
      createdAt: DateTime.now(),
      replyToId: replyToId,
    );
    setState(() {
      _messages.add(temp);
      _sending = true;
      _replyingTo = null;
    });
    _scrollToBottom();

    try {
      Map<String, dynamic> res;
      if (widget.isGroup) {
        res = await _api.sendGroupMessage(widget.receiverId, finalContent);
      } else {
        res = await _api.sendMessage(widget.receiverId, finalContent);
      }

      final realMsg = Message.fromJson({
        ...res,
        'sender_id': _meId,
        'receiver_id': widget.receiverId,
        'replyToId': replyToId,
        'reply_to_id': replyToId,
      });

      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == tempId);
          if (idx != -1) _messages[idx] = realMsg;
          else _messages.add(realMsg);
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        if (e is DioException && e.response?.statusCode == 403) {
          final msg = e.response?.data?['error'] ?? 'Vous ne pouvez pas envoyer de message à cet utilisateur.';
          _showError(msg);
          await _loadBlockStatus();
          setState(() => _messages.removeWhere((m) => m.id == tempId));
        } else {
          setState(() => _messages.removeWhere((m) => m.id == tempId));
          _ctrl.text = text;
          _showError('Erreur envoi: $e');
        }
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ─── Envoi d'un seul fichier (utilisé par le preview) ──────
  Future<void> _sendFile(
    XFile file, {
    required String originalName,
    String? caption,
    String? fileType,
  }) async {
    setState(() => _sending = true);
    final tempId = 'temp-file-${DateTime.now().millisecondsSinceEpoch}';

    String finalContent = caption ?? '';
    String? replyToId;
    if (_replyingTo != null) {
      final (quoteBlock, replyId) = _buildQuoteBlock(_replyingTo);
      replyToId = replyId;
      if (quoteBlock.isNotEmpty) finalContent = '$quoteBlock\n\n${caption ?? ''}';
      _cancelReply();
    }

    final temp = Message(
      id: tempId,
      senderId: _meId,
      receiverId: widget.receiverId,
      content: finalContent.isNotEmpty ? finalContent : null,
      isRead: false,
      isEdited: false,
      isDeleted: false,
      createdAt: DateTime.now(),
      fileUrl: 'placeholder',
      fileName: originalName,
      fileType: fileType ?? 'document',
      replyToId: replyToId,
    );

    setState(() => _messages.add(temp));
    _scrollToBottom();

    try {
      Map<String, dynamic> res;
      if (widget.isGroup) {
        res = await _api.sendGroupMessageWithFile(
          widget.receiverId,
          file.path,
          content: finalContent.isNotEmpty ? finalContent : null,
          originalName: originalName,
        );
      } else {
        res = await _api.sendMessageWithFile(
          widget.receiverId,
          file.path,
          content: finalContent.isNotEmpty ? finalContent : null,
          originalName: originalName,
        );
      }

      final mergedData = {
        ...res,
        'sender_id': _meId,
        'receiver_id': widget.receiverId,
        'file_name': res['file_name'] ?? res['fileName'] ?? originalName,
        'file_url': res['file_url'] ?? res['fileUrl'] ?? '',
        'file_type': res['file_type'] ?? res['fileType'] ?? fileType,
        'replyToId': replyToId,
        'reply_to_id': replyToId,
        'content': res['content'] ?? finalContent,
      };
      final realMsg = Message.fromJson(mergedData);

      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == tempId);
          if (idx != -1) _messages[idx] = realMsg;
          else _messages.add(realMsg);
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == tempId);
          if (idx != -1) {
            _messages[idx] = Message(
              id: tempId,
              senderId: _meId,
              receiverId: widget.receiverId,
              content: finalContent.isNotEmpty ? finalContent : null,
              isRead: false,
              isEdited: false,
              isDeleted: false,
              createdAt: DateTime.now(),
              fileUrl: null,
              fileName: originalName,
              fileType: fileType ?? 'document',
              replyToId: replyToId,
            );
          }
        });
        _showError('Erreur envoi: $e');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openFile(String? fileUrl, String? fileName) async {
    if (fileUrl == null || fileUrl.isEmpty || fileUrl == 'placeholder') {
      _showError('Fichier non disponible');
      return;
    }
    final fullUrl = '${AppConstants.baseUrl}$fileUrl';
    final uri = Uri.parse(fullUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      _showError('Impossible d\'ouvrir ce fichier: $e');
    }
  }

  // ════════════════════════════════════════════════════════════
  // NOUVEAU : MENU D'ATTACHEMENT AVEC MULTI-SÉLECTION
  // ════════════════════════════════════════════════════════════
  void _showAttachMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _attachOption(Icons.photo_library_rounded, _kBrand, 'Galerie', () {
                  Navigator.pop(context);
                  _pickMultipleMedia();
                }),
                _attachOption(Icons.camera_alt_rounded, Colors.green, 'Appareil photo', () {
                  Navigator.pop(context);
                  _pickCamera();
                }),
                _attachOption(Icons.insert_drive_file_rounded, Colors.orange, 'Document', () {
                  Navigator.pop(context);
                  _pickDocument();
                }),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _attachOption(IconData icon, Color color, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color, color.withOpacity(0.75)]),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ─── Sélection multiple (Galerie) ──────────────────────────
  Future<void> _pickMultipleMedia() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.media,
        allowMultiple: true,
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty || !mounted) return;

      final files = result.files.map((f) {
        if (kIsWeb && f.bytes != null) {
          return XFile.fromData(f.bytes!, name: f.name, mimeType: _mimeFromExt(f.extension ?? ''));
        } else if (f.path != null) {
          return XFile(f.path!, name: f.name);
        } else {
          return null;
        }
      }).whereType<XFile>().toList();

      if (files.isEmpty) return;

      // Ouvrir l'écran de prévisualisation
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MediaPreviewScreen(
            initialFiles: files,
            onSend: (compressedFiles, caption) async {
              // Envoyer chaque fichier un par un
              for (final file in compressedFiles) {
                final ext = file.name.split('.').last.toLowerCase();
                final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
                final fileType = isImage ? 'image' : 'video';
                await _sendFile(
                  file,
                  originalName: file.name,
                  caption: caption.isNotEmpty ? caption : null,
                  fileType: fileType,
                );
              }
            },
          ),
        ),
      );
    } catch (e) {
      _showError('Erreur sélection: $e');
    }
  }

  // ─── Appareil photo ──────────────────────────────────────────
  Future<void> _pickCamera() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
      if (picked == null || !mounted) return;
      // Envoyer directement sans compression (un seul fichier)
      _showPreviewDialog(XFile(picked.path, name: picked.name), originalName: picked.name);
    } catch (e) {
      _showError('Erreur caméra: $e');
    }
  }

  // ─── GARDE : anciennes méthodes (pour compatibilité, mais inutilisées) ──
  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (picked == null || !mounted) return;
      _showPreviewDialog(XFile(picked.path, name: picked.name), originalName: picked.name);
    } catch (e) { _showError('Erreur sélection image: $e'); }
  }

  Future<void> _pickVideo() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickVideo(source: ImageSource.gallery);
      if (picked == null || !mounted) return;
      _showPreviewDialog(XFile(picked.path, name: picked.name), originalName: picked.name);
    } catch (e) { _showError('Erreur sélection vidéo: $e'); }
  }

  Future<void> _pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv', 'zip', 'rar'],
        allowMultiple: false,
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      final f = result.files.first;
      final originalName = f.name;
      if (kIsWeb) {
        if (f.bytes == null) { _showError('Impossible de lire ce fichier.'); return; }
        _showPreviewDialog(
          XFile.fromData(f.bytes!, name: originalName, mimeType: _mimeFromExt(f.extension ?? '')),
          originalName: originalName,
        );
      } else {
        if (f.path == null) { _showError('Impossible de lire ce fichier.'); return; }
        _showPreviewDialog(XFile(f.path!, name: originalName), originalName: originalName);
      }
    } catch (e) { _showError('Erreur sélection document: $e'); }
  }

  String _mimeFromExt(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf': return 'application/pdf';
      case 'doc': return 'application/msword';
      case 'docx': return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls': return 'application/vnd.ms-excel';
      case 'xlsx': return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt': return 'application/vnd.ms-powerpoint';
      case 'pptx': return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'txt': return 'text/plain';
      case 'csv': return 'text/csv';
      case 'zip': return 'application/zip';
      default: return 'application/octet-stream';
    }
  }

  void _showPreviewDialog(XFile file, {required String originalName}) {
    final ext = originalName.split('.').last.toLowerCase();
    final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
    final isVideo = ['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext);
    final isPdf = ext == 'pdf';
    String fileType;
    if (isImage) fileType = 'image';
    else if (isVideo) fileType = 'video';
    else if (isPdf) fileType = 'pdf';
    else fileType = 'document';

    final captionCtrl = TextEditingController(text: _ctrl.text.trim());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(ctx)),
            const Spacer(),
            const Text('Aperçu', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            const SizedBox(width: 48),
          ]),
          const SizedBox(height: 12),
          if (isImage)
            FutureBuilder<Uint8List>(
              future: file.readAsBytes(),
              builder: (_, snap) {
                if (snap.hasData) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.memory(snap.data!, height: 260, fit: BoxFit.contain),
                  );
                }
                if (snap.hasError) return _fileIconPreview(Icons.broken_image, Colors.grey[400]!, ext, originalName);
                return const SizedBox(height: 260, child: Center(child: CircularProgressIndicator(color: Colors.white)));
              },
            )
          else
            _fileIconPreview(
              isVideo ? Icons.videocam : isPdf ? Icons.picture_as_pdf : Icons.insert_drive_file,
              isVideo ? Colors.blue[200]! : isPdf ? Colors.red[200]! : Colors.orange[200]!,
              ext,
              originalName,
            ),
          const SizedBox(height: 14),
          TextField(
            controller: captionCtrl,
            style: const TextStyle(color: Colors.white),
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(
              hintText: 'Ajouter un message (optionnel)...',
              hintStyle: TextStyle(color: Colors.grey[400]),
              filled: true,
              fillColor: Colors.grey[800],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                _ctrl.clear();
                await _sendFile(
                  file,
                  originalName: originalName,
                  caption: captionCtrl.text.trim().isNotEmpty ? captionCtrl.text.trim() : null,
                  fileType: fileType,
                );
              },
              icon: const Icon(Icons.send),
              label: const Text('Envoyer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kBrand,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _fileIconPreview(IconData icon, Color color, String ext, String name) {
    return Container(
      height: 130,
      decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(16)),
      child: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: color, size: 56),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 13), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(height: 4),
          Text(ext.toUpperCase(), style: TextStyle(color: Colors.grey[400], fontSize: 11)),
        ]),
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
    );
  }

  void _navigateToPost(String postId) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => PostDetailScreen(postId: postId),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            transitionBuilder: (child, anim) => SizeTransition(sizeFactor: anim, child: FadeTransition(opacity: anim, child: child)),
            child: _pinnedInfo != null ? _buildPinnedBanner(_pinnedInfo!) : const SizedBox.shrink(key: ValueKey('no_pin')),
          ),
          if (_isBlocked && !widget.isGroup) _buildBlockedBanner(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: _loading
                  ? _buildLoadingSkeleton()
                  : _messages.isEmpty
                      ? _buildEmptyState()
                      : ScrollablePositionedList.builder(
                          key: const ValueKey('list'),
                          itemScrollController: _itemScrollController,
                          itemPositionsListener: _itemPositionsListener,
                          padding: const EdgeInsets.all(12),
                          itemCount: _messages.length,
                          itemBuilder: (_, i) => _buildAnimatedBubble(_messages[i], i),
                        ),
            ),
          ),
          if (_sending) const LinearProgressIndicator(color: _kBrand, minHeight: 2, backgroundColor: Colors.transparent),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, anim) => SizeTransition(sizeFactor: anim, child: child),
            child: _replyingTo != null ? _buildReplyBar() : const SizedBox.shrink(key: ValueKey('no_reply')),
          ),
          if (_isBlocked && !widget.isGroup)
            Container(
              padding: const EdgeInsets.all(14),
              color: Colors.grey[200],
              child: const Center(child: Text('Vous ne pouvez pas envoyer de messages', style: TextStyle(color: Colors.grey))),
            )
          else
            _buildInputBar(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(64),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [_kBrand, _kBrandDark], begin: Alignment.topLeft, end: Alignment.bottomRight),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DmInfoScreen(userId: widget.receiverId, userName: widget.receiverName),
                      ),
                    ).then((_) { if (mounted) _loadBlockStatus(); });
                  },
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(shape: BoxShape.circle, border: Border.fromBorderSide(BorderSide(color: Colors.white30, width: 1.5))),
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.white24,
                          child: Text(
                            widget.receiverName.isNotEmpty ? widget.receiverName[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(widget.receiverName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white), overflow: TextOverflow.ellipsis),
                            Text(widget.isGroup ? '👥 Groupe' : '🔒 Chiffré', style: const TextStyle(fontSize: 11, color: Colors.white70)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBlockedBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.block_rounded, color: Colors.red.shade400),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Vous avez bloqué cet utilisateur (ou il vous a bloqué). Vous ne pouvez pas lui envoyer de messages.',
              style: TextStyle(color: Colors.red.shade800, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DmInfoScreen(userId: widget.receiverId, userName: widget.receiverName),
                ),
              ).then((_) { if (mounted) _loadBlockStatus(); });
            },
            child: const Text('Gérer', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return ListView.builder(
      key: const ValueKey('skeleton'),
      padding: const EdgeInsets.all(16),
      itemCount: 7,
      itemBuilder: (_, i) {
        final isMe = i % 3 == 1;
        return Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: _ShimmerBlock(width: 120.0 + (i % 4) * 35, height: 38, isMe: isMe),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      key: const ValueKey('empty'),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.85, end: 1),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutBack,
        builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(width: 84, height: 84, decoration: BoxDecoration(color: _kBrand.withOpacity(0.08), shape: BoxShape.circle), child: const Icon(Icons.lock_outline_rounded, size: 40, color: _kBrand)),
            const SizedBox(height: 16),
            const Text('Début de la conversation', style: TextStyle(color: Colors.grey, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildPinnedBanner(_PinnedInfo pin) {
    return GestureDetector(
      key: const ValueKey('pin_banner'),
      onTap: () => _scrollToMessage(pin.id),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.amber.shade50, Colors.amber.shade100]),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.amber.shade200),
        ),
        child: Row(
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.9, end: 1.1),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeInOut,
              builder: (_, v, child) => Transform.scale(scale: v, child: child),
              child: const Icon(Icons.push_pin_rounded, size: 18, color: Colors.amber),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Message épinglé · ${pin.sender}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.amber.shade800)),
                  const SizedBox(height: 2),
                  Text(pin.content, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              onPressed: () {
                setState(() => _pinnedInfo = null);
                _savePinnedMessage(null);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedBubble(Message msg, int index) {
    final bubble = _buildBubble(msg, index);
    if (_animatedIds.contains(msg.id)) return KeyedSubtree(key: ValueKey(msg.id), child: bubble);
    _animatedIds.add(msg.id);
    return _FadeSlideIn(key: ValueKey('anim_${msg.id}'), index: index, child: bubble);
  }

  Widget _buildBubble(Message msg, int index) {
    // Partages de post
    if (MessageUtils.isPostShare(msg.content)) {
      final postId = MessageUtils.extractPostId(msg.content);
      if (postId != null) {
        final future = _postFutures.putIfAbsent(postId, () => _api.getPost(postId));
        return FutureBuilder<Map<String, dynamic>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: _kBrand)),
                    SizedBox(width: 8),
                    Text('📤 Chargement du post...'),
                  ],
                ),
              );
            }
            if (snapshot.hasError || !snapshot.hasData) {
              final bool isSentByMe = msg.senderId == _meId;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    children: [
                      const Icon(Icons.share, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isSentByMe ? 'Vous avez envoyé un post' : 'Un post vous a été envoyé',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            final postData = snapshot.data!;
            final metadata = {
              'content': postData['content'],
              'mediaUrl': postData['media_url'] ?? postData['mediaUrl'],
              'fullName': postData['full_name'] ?? postData['fullName'],
              'username': postData['username'],
              'avatarUrl': postData['avatar_url'] ?? postData['avatarUrl'],
            };
            final sharedByName = msg.senderUsername ?? 'quelqu\'un';
            return GestureDetector(
              key: ValueKey(msg.id),
              onLongPress: () => _showMessageOptions(index),
              behavior: HitTestBehavior.translucent,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: SharedPostCard(
                  metadata: metadata,
                  onTap: () => _navigateToPost(postId),
                  sharedBy: sharedByName,
                ),
              ),
            );
          },
        );
      }
    }

    // Messages normaux
    final isMe = msg.senderId == _meId;
    final isHighlighted = msg.id == _highlightedMessageId;

    String? quoteText;
    String? mainContent = msg.content;
    if (msg.content != null && msg.content!.startsWith('> ') && msg.content!.contains('\n\n')) {
      final parts = msg.content!.split('\n\n');
      quoteText = parts.first;
      mainContent = parts.length > 1 ? parts.sublist(1).join('\n\n') : null;
    }

    final bubbleCore = GestureDetector(
      key: ValueKey(msg.id),
      onLongPress: () {
        HapticFeedback.mediumImpact();
        _showMessageOptions(index);
      },
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(vertical: 4),
          constraints: const BoxConstraints(maxWidth: 280),
          padding: isHighlighted ? const EdgeInsets.all(4) : EdgeInsets.zero,
          decoration: BoxDecoration(
            color: isHighlighted ? const Color(0xFFFFF3CD) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            boxShadow: isHighlighted ? [BoxShadow(color: Colors.amber.withOpacity(0.35), blurRadius: 14, spreadRadius: 1)] : [],
          ),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isMe)
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 2),
                  child: Text(msg.senderUsername ?? 'Membre', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kBrand)),
                ),
              if (quoteText != null) _buildQuoteWidget(msg),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: isMe ? const LinearGradient(colors: [_kBrand, _kBrandDark], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
                  color: isMe ? null : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isMe ? 18 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 18),
                  ),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6, offset: const Offset(0, 2))],
                ),
                child: _buildBubbleContent(msg, isMe, mainContent),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(timeago.format(msg.createdAt, locale: 'fr'), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      Icon(msg.isRead ? Icons.done_all : Icons.done, size: 12, color: msg.isRead ? const Color(0xFF006838) : Colors.grey),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return _SwipeToReply(isMe: isMe, onReply: () => _replyTo(msg), child: bubbleCore);
  }

  Widget _buildBubbleContent(Message msg, bool isMe, String? customContent) {
    final textColor = isMe ? Colors.white : Colors.black87;

    final hasFile = (msg.fileType != null && msg.fileType!.isNotEmpty) ||
        (msg.fileName != null && msg.fileName!.isNotEmpty) ||
        (msg.fileUrl != null && msg.fileUrl!.isNotEmpty && msg.fileUrl != 'placeholder');

    final hasText = (customContent != null && customContent.isNotEmpty) ||
        (msg.content != null && msg.content!.isNotEmpty);

    if (hasFile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildFileWidget(msg, isMe),
          if (hasText) ...[
            const SizedBox(height: 6),
            Text(customContent ?? msg.content!, style: TextStyle(color: textColor, fontSize: 14)),
          ],
        ],
      );
    }

    if (hasText) {
      return Text(customContent ?? msg.content!, style: TextStyle(color: textColor, fontSize: 15));
    }

    return const SizedBox.shrink();
  }

  // ============================================================
  // WIDGET FICHIER AMÉLIORÉ (avec support vidéo)
  // ============================================================
  Widget _buildFileWidget(Message msg, bool isMe) {
    final textColor = isMe ? Colors.white : Colors.black87;
    final ext = (msg.fileName ?? '').split('.').last.toLowerCase();
    final isImage = msg.fileType == 'image';
    final isVideo = msg.fileType == 'video' || MediaUtils.isVideo(msg.fileUrl ?? '');
    final isAudio = msg.fileType == 'audio';
    final isPdf = msg.fileType == 'pdf' || ext == 'pdf';

    final hasValidUrl = msg.fileUrl != null && msg.fileUrl!.isNotEmpty && msg.fileUrl != 'placeholder';

    if (isVideo && hasValidUrl) {
      // ✅ AFFICHER LE LECTEUR VIDÉO
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _VideoMessagePlayer(fileUrl: msg.fileUrl!, isMe: isMe),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam, size: 14, color: textColor.withOpacity(0.6)),
              const SizedBox(width: 4),
              Text(
                msg.fileName ?? 'Vidéo',
                style: TextStyle(color: textColor.withOpacity(0.6), fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      );
    }

    if (isImage && hasValidUrl) {
      return GestureDetector(
        onTap: () => _openFile(msg.fileUrl, msg.fileName),
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                '${AppConstants.baseUrl}${msg.fileUrl}',
                width: 200,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) {
                  if (progress == null) return child;
                  return SizedBox(
                    width: 200,
                    height: 150,
                    child: Center(
                      child: CircularProgressIndicator(
                        value: progress.expectedTotalBytes != null
                            ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                            : null,
                        color: _kBrand,
                      ),
                    ),
                  );
                },
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey, size: 48),
              ),
            ),
            Container(
              width: 200,
              padding: const EdgeInsets.symmetric(vertical: 5),
              decoration: const BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(10), bottomRight: Radius.circular(10)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.download, size: 12, color: Colors.white),
                  SizedBox(width: 4),
                  Text('Appuyer pour télécharger', style: TextStyle(color: Colors.white, fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Autres types (audio, pdf, document)
    IconData icon;
    Color iconColor;
    Color bgColor;
    if (isAudio) {
      icon = Icons.audiotrack;
      iconColor = isMe ? Colors.white : Colors.purple[400]!;
      bgColor = isMe ? Colors.white24 : Colors.purple[50]!;
    } else if (isPdf) {
      icon = Icons.picture_as_pdf;
      iconColor = isMe ? Colors.white : Colors.red[400]!;
      bgColor = isMe ? Colors.white24 : Colors.red[50]!;
    } else {
      icon = Icons.insert_drive_file;
      iconColor = isMe ? Colors.white70 : Colors.orange[400]!;
      bgColor = isMe ? Colors.white24 : Colors.orange[50]!;
    }

    return GestureDetector(
      onTap: () => _openFile(msg.fileUrl, msg.fileName),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: textColor.withOpacity(0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: iconColor.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    msg.fileName ?? 'Fichier',
                    style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.download, size: 11, color: textColor.withOpacity(0.6)),
                      const SizedBox(width: 3),
                      Text(
                        hasValidUrl ? 'Appuyer pour télécharger' : 'Envoi en cours...',
                        style: TextStyle(color: textColor.withOpacity(0.6), fontSize: 10),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 10,
        right: 10,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, -2))],
      ),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.attach_file_rounded, color: _kBrand),
          onPressed: _showAttachMenu,
        ),
        Expanded(
          child: TextField(
            controller: _ctrl,
            maxLines: null,
            decoration: InputDecoration(
              hintText: _replyingTo != null ? 'Écrire une réponse...' : 'Écrire un message...',
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onSubmitted: (_) => _send(),
          ),
        ),
        const SizedBox(width: 8),
        _SendButton(onTap: _send),
      ]),
    );
  }
}

// ─── Bouton d'envoi ──────────────────────────────────────────
class _SendButton extends StatefulWidget {
  final VoidCallback onTap;
  const _SendButton({required this.onTap});

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.88),
      onTapUp: (_) => setState(() => _scale = 1),
      onTapCancel: () => setState(() => _scale = 1),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        child: Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [_kBrand, _kBrandDark], begin: Alignment.topLeft, end: Alignment.bottomRight),
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
          ),
          child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}