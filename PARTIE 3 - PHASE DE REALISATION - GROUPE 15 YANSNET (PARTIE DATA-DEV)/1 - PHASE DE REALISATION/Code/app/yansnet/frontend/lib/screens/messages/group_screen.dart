// lib/screens/messages/group_screen.dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cross_file/cross_file.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../../models/group_message.dart';
import '../../models/notification_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../../services/api_service.dart';
import '../../services/socket_service.dart';
import '../../utils/constants.dart';
import '../../utils/message_utils.dart';
import '../../utils/media_utils.dart';
import '../../widgets/shared_post_card.dart';
import '../posts/post_detail_screen.dart';
import 'group_info_screen.dart';

// ─── LECTEUR VIDÉO POUR MESSAGE DE GROUPE ─────────────────────
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
      print('❌ Erreur init vidéo groupe: $e');
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

// ─── WIDGET UTILITAIRE POUR AFFICHER UNE IMAGE EN RÉSEAU ─────
Widget _buildNetworkImage(String url, {double? width, double? height, BoxFit fit = BoxFit.cover}) {
  final fullUrl = url.startsWith('http') ? url : '${AppConstants.baseUrl}$url';
  return Image.network(
    fullUrl,
    width: width,
    height: height,
    fit: fit,
    loadingBuilder: (context, child, loadingProgress) {
      if (loadingProgress == null) return child;
      return Container(
        width: width,
        height: height,
        color: Colors.grey[200],
        child: const Center(child: CircularProgressIndicator()),
      );
    },
    errorBuilder: (context, error, stackTrace) {
      return Container(
        width: width,
        height: height,
        color: Colors.grey[300],
        child: const Icon(Icons.broken_image, color: Colors.grey),
      );
    },
  );
}

// ─── CLASSE PRINCIPALE ──────────────────────────────────────────

class GroupScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  const GroupScreen({super.key, required this.groupId, required this.groupName});

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  final ApiService _api = ApiService();
  final SocketService _socket = SocketService();
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();

  List<GroupMessage> _messages = [];
  GroupMessage? _pinnedMessage;
  GroupMessage? _replyingTo;
  bool _loading = true;
  bool _sending = false;
  bool _isDeleting = false;
  String _meId = '';
  String _myGlobalRole = '';
  String _groupName = '';
  int _memberCount = 0;
  String _myRole = '';

  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _filteredMembers = [];
  OverlayEntry? _suggestionsOverlay;
  bool _showSuggestions = false;

  final Map<String, GlobalKey> _messageKeys = {};
  String? _highlightedMessageId;

  bool _hasLoadedMore = false;
  static const int _initialLimit = 200;

  final Set<String> _processedMentionIds = {};

  int _unreadMentionsCount = 0;
  List<String> _unreadMentionIds = [];

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _meId = auth.user?.id ?? '';
    _myGlobalRole = auth.user?.role ?? '';
    _groupName = widget.groupName;
    _loadMessages();
    _loadGroupInfo();
    _loadPinnedMessage();

    _ctrl.addListener(_onTextChanged);

    _socket.joinGroup(widget.groupId);

    _socket.onGroupMessage((data) {
      // ✅ LOG pour déboguer
      print('📦 Message reçu (brut) : $data');
      if (data['group_id']?.toString() != widget.groupId) return;
      if (!mounted) return;
      final msg = GroupMessage.fromJson(data);
      if (_messages.any((m) => m.id == msg.id)) return;
      if (msg.senderId == _meId) {
        final tempIndex = _messages.indexWhere((m) =>
            m.id.startsWith('temp-') &&
            (m.content == msg.content || (m.fileName == msg.fileName && m.fileType == msg.fileType)));
        if (tempIndex != -1) {
          setState(() {
            _messages[tempIndex] = msg;
          });
          _scrollToBottom();
          return;
        }
      }
      setState(() => _messages.add(msg));
      _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      _scrollToBottom();

      _handleLocalMention(msg);
    });

    _socket.onMention((data) {
      if (!mounted) return;
      if (data['groupId']?.toString() != widget.groupId) return;
      final senderId = data['senderId']?.toString() ?? '';
      if (senderId == _meId) return;

      final messageId = data['messageId']?.toString();
      if (messageId == null || messageId.isEmpty) return;

      if (_processedMentionIds.contains(messageId)) return;
      _processedMentionIds.add(messageId);

      final senderName = data['senderUsername'] ?? 'Quelqu\'un';
      _showMentionSnackBar(senderName, messageId);

      setState(() {
        _unreadMentionsCount++;
        _unreadMentionIds.add(messageId);
      });

      final notif = AppNotification(
        id: 'mention_${DateTime.now().millisecondsSinceEpoch}_$messageId',
        type: 'mention',
        content: '$senderName vous a mentionné dans ${widget.groupName}',
        isRead: false,
        referenceId: messageId,
        createdAt: DateTime.now(),
      );
      Provider.of<NotificationProvider>(context, listen: false).addNotification(notif);

      _socket.incrementUnreadCount();
      _notifyUrgent();
    });

    _socket.onGroupUpdated((data) {
      if (data['group_id']?.toString() != widget.groupId) return;
      if (!mounted) return;
      if (data['name'] != null) {
        setState(() => _groupName = data['name']);
      }
    });

    _socket.onAddedToGroup((data) {
      if (data['group_id']?.toString() != widget.groupId) return;
      _loadGroupInfo();
    });

    _socket.onRemovedFromGroup((data) {
      if (data['group_id']?.toString() != widget.groupId) return;
      if (mounted) Navigator.pop(context);
    });

    _socket.onMessagePinned((data) {
      if (data['groupId'] != widget.groupId) return;
      if (!mounted) return;
      setState(() {
        _pinnedMessage = GroupMessage.fromJson(data['pinnedMessage']);
        final index = _messages.indexWhere((m) => m.id == _pinnedMessage?.id);
        if (index != -1) {
          _messages[index] = _pinnedMessage!;
        }
      });
    });

    _socket.onMessageUnpinned((data) {
      if (data['groupId'] != widget.groupId) return;
      if (!mounted) return;
      setState(() => _pinnedMessage = null);
    });

    _socket.onGroupMessageDeleted((data) {
      if (!mounted) return;
      final messageId = data['messageId']?.toString();
      if (messageId != null && data['groupId']?.toString() == widget.groupId) {
        setState(() {
          _messages.removeWhere((m) => m.id == messageId);
        });
      }
    });

    _socket.onGroupMessageDeletedForMe((data) {
      if (!mounted) return;
      final messageId = data['messageId']?.toString();
      if (messageId != null && data['groupId']?.toString() == widget.groupId) {
        setState(() {
          _messages.removeWhere((m) => m.id == messageId);
        });
      }
    });

    _socket.onGroupMessageEdited((data) {
      if (!mounted) return;
      final edited = GroupMessage.fromJson(data);
      final index = _messages.indexWhere((m) => m.id == edited.id);
      if (index != -1) {
        setState(() => _messages[index] = edited);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTextChanged);
    _ctrl.dispose();
    _socket.leaveGroup(widget.groupId);
    _socket.removeGroupListeners();
    _socket.removeListener('new_notification');
    _socket.removeListener('mention');
    _socket.removeListener('group_message_deleted');
    _socket.removeListener('group_message_deleted_for_me');
    _socket.removeListener('group_message_edited');
    _scroll.dispose();
    _processedMentionIds.clear();
    super.dispose();
  }

  // ─── Suggestions de mentions ─────────────────────────────────
  void _onTextChanged() {
    final text = _ctrl.text;
    final atIndex = text.lastIndexOf('@');
    if (atIndex != -1 && atIndex == text.length - 1) {
      _showSuggestions = true;
      _filteredMembers = _members;
      _updateSuggestionsOverlay();
    } else if (atIndex != -1 && atIndex < text.length - 1) {
      final search = text.substring(atIndex + 1).toLowerCase();
      _filteredMembers = _members.where((m) {
        final name = (m['username'] ?? '').toLowerCase();
        return name.contains(search);
      }).toList();
      _showSuggestions = _filteredMembers.isNotEmpty;
      _updateSuggestionsOverlay();
    } else {
      _showSuggestions = false;
      _removeSuggestionsOverlay();
    }
  }

  void _updateSuggestionsOverlay() {
    _removeSuggestionsOverlay();
    if (!_showSuggestions) return;
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final Offset offset = renderBox.localToGlobal(Offset.zero);
    _suggestionsOverlay = OverlayEntry(
      builder: (context) => Positioned(
        left: offset.dx + 8,
        right: offset.dx + 8,
        top: offset.dy + MediaQuery.of(context).size.height - 120,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 150),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _filteredMembers.length,
              itemBuilder: (ctx, i) {
                final member = _filteredMembers[i];
                final name = member['username'] ?? 'Membre';
                return ListTile(
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundImage: member['avatar_url'] != null
                        ? NetworkImage('${AppConstants.baseUrl}${member['avatar_url']}')
                        : null,
                    child: member['avatar_url'] == null
                        ? Text(name[0].toUpperCase())
                        : null,
                  ),
                  title: Text(name),
                  onTap: () {
                    final currentText = _ctrl.text;
                    final atIndex = currentText.lastIndexOf('@');
                    final before = currentText.substring(0, atIndex);
                    final after = currentText.substring(atIndex + 1);
                    final newText = '$before@$name ';
                    _ctrl.text = newText;
                    _ctrl.selection = TextSelection.collapsed(offset: newText.length);
                    _removeSuggestionsOverlay();
                    _showSuggestions = false;
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

  List<String> _extractMentions(String text) {
    final regExp = RegExp(r'@([\w.-]+)');
    return regExp.allMatches(text).map((m) => m.group(1)!).toList();
  }

  void _handleLocalMention(GroupMessage msg) {
    final currentUser = context.read<AuthProvider>().user;
    if (currentUser == null) return;
    final username = currentUser.username;
    if (username == null || username.isEmpty) return;

    final content = msg.content ?? '';
    final mentions = _extractMentions(content);

    if (!mentions.contains(username)) return;
    if (msg.senderId == _meId) return;
    if (_processedMentionIds.contains(msg.id)) return;
    _processedMentionIds.add(msg.id);

    _socket.incrementUnreadCount();

    final senderName = msg.username ?? 'Quelqu\'un';
    final notif = AppNotification(
      id: 'mention_${DateTime.now().millisecondsSinceEpoch}',
      type: 'mention',
      content: '$senderName vous a mentionné dans ${widget.groupName}',
      isRead: false,
      referenceId: msg.id,
      createdAt: DateTime.now(),
    );
    Provider.of<NotificationProvider>(context, listen: false).addNotification(notif);

    _showMentionSnackBar(senderName, msg.id);

    setState(() {
      _unreadMentionsCount++;
      _unreadMentionIds.add(msg.id);
    });

    _notifyUrgent();
  }

  void _showMentionSnackBar(String senderName, String messageId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$senderName vous a mentionné'),
          backgroundColor: Colors.red[700],
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Voir',
            onPressed: () => _scrollToMessage(messageId),
          ),
        ),
      );
    });
  }

  void _notifyUrgent() {
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
  }

  // ──────────────────────────────────────────────────────────────
  // Chargement des données
  // ──────────────────────────────────────────────────────────────

  Future<void> _loadGroupInfo() async {
    try {
      final info = await _api.getGroupDetail(widget.groupId);
      if (mounted) {
        setState(() {
          final members = info['members'] as List?;
          _members = members?.cast<Map<String, dynamic>>() ?? [];
          _memberCount = _members.length;
          if (info['name'] != null) _groupName = info['name'];
          _myRole = info['my_role'] ?? '';
        });
      }
    } catch (e) {
      debugPrint('Error loading group info: $e');
    }
  }

  Future<void> _loadMessages() async {
    try {
      final data = await _api.getGroupMessages(widget.groupId, limit: _initialLimit);
      setState(() {
        _messages = data.map((j) => GroupMessage.fromJson(j)).toList();
        _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        _loading = false;
        _hasLoadedMore = false;
      });
      _scrollToBottom();
    } catch (e) {
      debugPrint('Error loading messages: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_hasLoadedMore) return;
    setState(() => _hasLoadedMore = true);
    try {
      final data = await _api.getGroupMessages(widget.groupId, limit: 500);
      final newMessages = data.map((j) => GroupMessage.fromJson(j)).toList();
      final existingIds = _messages.map((m) => m.id).toSet();
      final uniqueNew = newMessages.where((m) => !existingIds.contains(m.id)).toList();
      if (uniqueNew.isNotEmpty) {
        setState(() {
          _messages = [...uniqueNew, ..._messages];
          _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        });
      } else {
        setState(() => _hasLoadedMore = true);
      }
    } catch (e) {
      debugPrint('Erreur lors du chargement de plus de messages: $e');
      setState(() => _hasLoadedMore = true);
    }
  }

  Future<void> _loadPinnedMessage() async {
    final data = await _api.getPinnedMessage(widget.groupId);
    if (data != null && data['id'] != null && mounted) {
      setState(() => _pinnedMessage = GroupMessage.fromJson(data));
    } else {
      setState(() => _pinnedMessage = null);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _scrollToMessage(String messageId) async {
    int index = _messages.indexWhere((m) => m.id == messageId);

    if (index == -1) {
      await _loadMoreMessages();
      index = _messages.indexWhere((m) => m.id == messageId);
      if (index == -1) {
        _showError('Message original non trouvé dans l’historique.');
        return;
      }
    }

    setState(() {
      _highlightedMessageId = messageId;
    });

    if (_unreadMentionIds.contains(messageId)) {
      setState(() {
        _unreadMentionIds.remove(messageId);
        _unreadMentionsCount = _unreadMentionIds.length;
      });
    }

    await _ensureMessageVisible(messageId, index);

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _highlightedMessageId == messageId) {
        setState(() {
          _highlightedMessageId = null;
        });
      }
    });
  }

  Future<void> _ensureMessageVisible(String messageId, int index) async {
    if (!_scroll.hasClients) return;

    const int maxAttempts = 8;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final key = _messageKeys[messageId];
      final ctx = key?.currentContext;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
          alignment: 0.5,
        );
        return;
      }

      if (!_scroll.hasClients) return;
      final maxExtent = _scroll.position.maxScrollExtent;
      if (maxExtent <= 0) break;

      final ratio = _messages.isEmpty ? 0.0 : index / (_messages.length - 1).clamp(1, 1 << 30);
      final estimated = (maxExtent * ratio).clamp(0.0, maxExtent);

      await _scroll.animateTo(
        estimated,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
      await Future.delayed(const Duration(milliseconds: 90));
    }

    final key = _messageKeys[messageId];
    final ctx = key?.currentContext;
    if (ctx != null && ctx.mounted) {
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.5,
      );
    }
  }

  void _openGroupInfo() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupInfoScreen(
          groupId: widget.groupId,
          groupName: _groupName,
        ),
      ),
    ).then((_) {
      _loadGroupInfo();
    });
  }

  void _replyTo(GroupMessage msg) {
    setState(() {
      _replyingTo = msg;
    });
    FocusScope.of(context).requestFocus(FocusNode());
  }

  void _cancelReply() {
    setState(() {
      _replyingTo = null;
    });
  }

  // ──────────────────────────────────────────────────────────────
  // SUPPRESSION DE MESSAGE
  // ──────────────────────────────────────────────────────────────

  Future<void> _deleteMessage(GroupMessage msg) async {
    if (_isDeleting) return;
    final bool canDelete = msg.senderId == _meId ||
        _myGlobalRole == 'admin' ||
        _myRole == 'admin';

    if (!canDelete) {
      _showError('Vous ne pouvez pas supprimer ce message.');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer le message ?'),
        content: Text(
          'Voulez-vous vraiment supprimer ce message ${msg.content != null ? ' : "${msg.content!.substring(0, msg.content!.length > 30 ? 30 : msg.content!.length)}..."' : ''} ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
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
      await _api.deleteGroupMessage(widget.groupId, msg.id);
      setState(() {
        _messages.removeWhere((m) => m.id == msg.id);
        _isDeleting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message supprimé'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      setState(() => _isDeleting = false);
      _showError('Erreur lors de la suppression : $e');
    }
  }

  // ─── Supprimer pour moi ──────────────────────────────────────
  Future<void> _deleteGroupMessageForMe(GroupMessage msg) async {
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
      await _api.deleteGroupMessageForMe(widget.groupId, msg.id);
      setState(() {
        _messages.removeWhere((m) => m.id == msg.id);
        _isDeleting = false;
      });
    } catch (e) {
      setState(() => _isDeleting = false);
      _showError('Erreur: $e');
    }
  }

  // ─── Modifier un message ─────────────────────────────────────
  Future<void> _editGroupMessage(GroupMessage msg) async {
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
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF9E1B22)),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (result == true && controller.text.trim().isNotEmpty) {
      setState(() => _isDeleting = true);
      try {
        final updated = await _api.editGroupMessage(widget.groupId, msg.id, controller.text.trim());
        final index = _messages.indexWhere((m) => m.id == msg.id);
        if (index != -1) {
          setState(() {
            _messages[index] = GroupMessage.fromJson({
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

  // ──────────────────────────────────────────────────────────────
  //  MÉTHODES POUR LA CITATION PLATE
  // ──────────────────────────────────────────────────────────────

  String _getCleanContent(GroupMessage msg) {
    if (msg.content == null) return '';
    final lines = msg.content!.split('\n');
    final cleaned = lines.where((line) => !line.trimLeft().startsWith('> ')).toList();
    return cleaned.join('\n').trim();
  }

  (String quoteBlock, String? replyToId) _buildQuoteBlock(GroupMessage? replyingTo) {
    if (replyingTo == null) return ('', null);

    final parent = replyingTo;
    final parentClean = _getCleanContent(parent);
    final parentSender = parent.username ?? 'Membre';
    List<String> quoteLines = [
      '> $parentSender: ${parentClean.isNotEmpty ? parentClean : 'Fichier'}'
    ];

    if (parent.replyToId != null && parent.replyToId!.isNotEmpty) {
      final grandParent = _messages.firstWhere(
        (m) => m.id == parent.replyToId,
        orElse: () => GroupMessage(id: '', groupId: '', senderId: '', content: '', isSystem: false, isRead: false, createdAt: DateTime.now()),
      );
      if (grandParent.id.isNotEmpty) {
        final grandParentClean = _getCleanContent(grandParent);
        final grandParentSender = grandParent.username ?? 'Membre';
        quoteLines.add('> $grandParentSender: ${grandParentClean.isNotEmpty ? grandParentClean : 'Fichier'}');
      }
    }

    final quoteBlock = quoteLines.join('\n');
    return (quoteBlock, parent.id);
  }

  // ──────────────────────────────────────────────────────────────
  //  UTILITAIRE POUR LE TEXTE D'AFFICHAGE
  // ──────────────────────────────────────────────────────────────

  String _getDisplayContent(GroupMessage msg) {
    final content = msg.content ?? '';
    if (content.startsWith('PARTAGE:')) {
      final parts = content.split('\n\n');
      if (parts.length > 1) {
        return parts.sublist(1).join('\n\n');
      }
    }
    return content;
  }

  String _getPinnedPreviewText(GroupMessage msg) {
    final clean = _getCleanContent(msg);
    if (clean.startsWith('PARTAGE:')) {
      return 'Publication partagée';
    }
    if (clean.isNotEmpty) return clean;
    if (msg.fileName != null && msg.fileName!.isNotEmpty) {
      return '📎 ${msg.fileName}';
    }
    return 'Fichier';
  }

  // ──────────────────────────────────────────────────────────────
  //  ENVOI DE MESSAGE (TEXTE)
  // ──────────────────────────────────────────────────────────────

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    _ctrl.clear();

    final mentions = _extractMentions(text);

    String finalContent = text;
    String? replyToId;
    if (_replyingTo != null) {
      final (quoteBlock, replyId) = _buildQuoteBlock(_replyingTo);
      replyToId = replyId;
      if (quoteBlock.isNotEmpty) {
        finalContent = '$quoteBlock\n\n$text';
      }
    }

    final tempId = 'temp-${DateTime.now().millisecondsSinceEpoch}';
    final me = context.read<AuthProvider>().user;
    final temp = GroupMessage(
      id: tempId,
      groupId: widget.groupId,
      senderId: _meId,
      content: finalContent,
      isSystem: false,
      isRead: false,
      createdAt: DateTime.now(),
      username: me?.username,
      replyToId: replyToId,
    );
    setState(() {
      _messages.add(temp);
      _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      _sending = true;
      _replyingTo = null;
    });
    _scrollToBottom();

    try {
      final res = await _api.sendGroupMessage(
        widget.groupId,
        finalContent,
        replyToId: replyToId,
        mentions: mentions,
      );
      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == tempId);
          if (idx != -1) {
            _messages[idx] = GroupMessage.fromJson(res);
          }
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _messages.removeWhere((m) => m.id == tempId));
        _ctrl.text = text;
        _showError('Erreur envoi: $e');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ──────────────────────────────────────────────────────────────
  //  ENVOI DE FICHIER
  // ──────────────────────────────────────────────────────────────

  void _showAttachMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF9E1B22),
                child: Icon(Icons.image, color: Colors.white),
              ),
              title: const Text('Image'),
              onTap: () { Navigator.pop(context); _pickImage(); },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.blue,
                child: Icon(Icons.videocam, color: Colors.white),
              ),
              title: const Text('Vidéo'),
              onTap: () { Navigator.pop(context); _pickVideo(); },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.orange,
                child: Icon(Icons.insert_drive_file, color: Colors.white),
              ),
              title: const Text('Document / PDF'),
              onTap: () { Navigator.pop(context); _pickDocument(); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (picked == null || !mounted) return;
      _showPreviewDialog(XFile(picked.path, name: picked.name), originalName: picked.name);
    } catch (e) { _showError('Erreur: $e'); }
  }

  Future<void> _pickVideo() async {
    try {
      final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (picked == null || !mounted) return;
      _showPreviewDialog(XFile(picked.path, name: picked.name), originalName: picked.name);
    } catch (e) { _showError('Erreur: $e'); }
  }

  Future<void> _pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf','doc','docx','xls','xlsx','ppt','pptx','txt','csv','zip','rar'],
        allowMultiple: false,
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      final f = result.files.first;
      if (kIsWeb) {
        final bytes = f.bytes;
        if (bytes == null) { _showError('Impossible de lire ce fichier.'); return; }
        _showPreviewDialog(
          XFile.fromData(bytes, name: f.name, mimeType: _mimeFromExt(f.extension ?? '')),
          originalName: f.name,
        );
      } else {
        if (f.path == null) { _showError('Impossible de lire ce fichier.'); return; }
        _showPreviewDialog(XFile(f.path!, name: f.name), originalName: f.name);
      }
    } catch (e) { _showError('Erreur: $e'); }
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
    final isImage = ['jpg','jpeg','png','gif','webp','bmp'].contains(ext);
    final isVideo = ['mp4','mov','avi','mkv','webm'].contains(ext);
    final isPdf = ext == 'pdf';
    final captionCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          left: 16, right: 16, top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(ctx)),
              const Spacer(),
              const Text('Aperçu', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
            ]),
            const SizedBox(height: 12),
            if (isImage)
              FutureBuilder<Uint8List>(
                future: file.readAsBytes(),
                builder: (_, snap) {
                  if (snap.hasData) return ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(snap.data!, height: 260, fit: BoxFit.contain));
                  if (snap.hasError) return _fileIconWidget(Icons.broken_image, Colors.grey[400]!, ext, originalName);
                  return const SizedBox(height: 260, child: Center(child: CircularProgressIndicator(color: Colors.white)));
                },
              )
            else
              _fileIconWidget(
                isVideo ? Icons.videocam : isPdf ? Icons.picture_as_pdf : Icons.insert_drive_file,
                isVideo ? Colors.blue[200]! : isPdf ? Colors.red[200]! : Colors.orange[200]!,
                ext, originalName,
              ),
            const SizedBox(height: 14),
            TextField(
              controller: captionCtrl,
              style: const TextStyle(color: Colors.white),
              maxLines: 3, minLines: 1,
              decoration: InputDecoration(
                hintText: 'Ajouter un message (optionnel)...',
                hintStyle: TextStyle(color: Colors.grey[400]),
                filled: true, fillColor: Colors.grey[800],
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
                  await _sendFile(file, originalName: originalName,
                    caption: captionCtrl.text.trim().isNotEmpty ? captionCtrl.text.trim() : null);
                },
                icon: const Icon(Icons.send),
                label: const Text('Envoyer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF9E1B22),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fileIconWidget(IconData icon, Color color, String ext, String name) {
    return Container(
      height: 130,
      decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(12)),
      child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: color, size: 56),
        const SizedBox(height: 10),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 13), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis)),
        const SizedBox(height: 4),
        Text(ext.toUpperCase(), style: TextStyle(color: Colors.grey[400], fontSize: 11)),
      ])),
    );
  }

  Future<void> _sendFile(XFile file, {required String originalName, String? caption}) async {
    setState(() => _sending = true);
    final tempId = 'temp-file-${DateTime.now().millisecondsSinceEpoch}';
    final me = context.read<AuthProvider>().user;

    String finalContent = caption ?? '';
    String? replyToId;
    if (_replyingTo != null) {
      final (quoteBlock, replyId) = _buildQuoteBlock(_replyingTo);
      replyToId = replyId;
      if (quoteBlock.isNotEmpty) {
        finalContent = '$quoteBlock\n\n${caption ?? ''}';
      }
      _cancelReply();
    }

    final mentions = _extractMentions(finalContent);

    final temp = GroupMessage(
      id: tempId,
      groupId: widget.groupId,
      senderId: _meId,
      content: finalContent.isNotEmpty ? finalContent : null,
      isSystem: false,
      isRead: false,
      createdAt: DateTime.now(),
      username: me?.username,
      fileUrl: file.path,
      fileName: originalName,
      fileType: 'image',
      replyToId: replyToId,
    );
    setState(() {
      _messages.add(temp);
      _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    });
    _scrollToBottom();

    try {
      final res = await _api.sendGroupMessageWithFile(
        widget.groupId,
        file.path,
        content: finalContent.isNotEmpty ? finalContent : null,
        originalName: originalName,
        replyToId: replyToId,
        mentions: mentions,
      );
      if (mounted) {
        final realMsg = GroupMessage.fromJson(res);
        setState(() {
          final index = _messages.indexWhere((m) => m.id == tempId);
          if (index != -1) {
            _messages[index] = realMsg;
          } else {
            _messages.add(realMsg);
          }
          _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _messages.removeWhere((m) => m.id == tempId));
        _showError('Erreur envoi: $e');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  // ──────────────────────────────────────────────────────────────
  //  WIDGET D'AFFICHAGE (TEXTE HIGHLIGHTÉ)
  // ──────────────────────────────────────────────────────────────

  Widget _buildHighlightedText(String text, {Color? mentionColor, Color? textColor}) {
    mentionColor ??= Colors.blue[700];
    textColor ??= Colors.black87;
    final regExp = RegExp(r'@([\w.-]+)');
    final matches = regExp.allMatches(text);
    if (matches.isEmpty) {
      return Text(
        text,
        style: TextStyle(fontSize: 15, color: textColor),
      );
    }
    final List<TextSpan> spans = [];
    int lastEnd = 0;
    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: TextStyle(color: textColor),
        ));
      }
      final mention = match.group(0)!;
      spans.add(TextSpan(
        text: mention,
        style: TextStyle(color: mentionColor, fontWeight: FontWeight.bold),
      ));
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: TextStyle(color: textColor),
      ));
    }
    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: 15, color: textColor),
        children: spans,
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  //  BUILD PRINCIPAL
  // ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF9E1B22),
        foregroundColor: Colors.white,
        title: InkWell(
          onTap: _openGroupInfo,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white24,
                  child: Text(
                    _groupName.isNotEmpty ? _groupName[0].toUpperCase() : 'G',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _groupName,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_unreadMentionsCount > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$_unreadMentionsCount',
                                style: const TextStyle(color: Colors.white, fontSize: 11),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        _memberCount == 0 ? 'Chargement...' : '$_memberCount membre${_memberCount > 1 ? 's' : ''}',
                        style: const TextStyle(fontSize: 10, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.info_outline), onPressed: _openGroupInfo),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF9E1B22)))
              : Column(
                  children: [
                    if (_pinnedMessage != null)
                      _buildPinnedBanner(_pinnedMessage!),
                    Expanded(
                      child: _messages.isEmpty
                        ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.group_outlined, size: 56, color: Colors.grey[400]),
                            const SizedBox(height: 12),
                            Text('Aucun message', style: TextStyle(color: Colors.grey[500])),
                            const SizedBox(height: 4),
                            Text('Soyez le premier à écrire !', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                          ]))
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.all(12),
                            itemCount: _messages.length,
                            itemBuilder: (_, index) => _buildBubble(_messages[index], index),
                          ),
                    ),
                  ],
                ),
          ),
          if (_sending) const LinearProgressIndicator(color: Color(0xFF9E1B22)),
          if (_unreadMentionsCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: GestureDetector(
                onTap: () {
                  if (_unreadMentionIds.isNotEmpty) {
                    _scrollToMessage(_unreadMentionIds.first);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.red.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.shade100,
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.alarm, color: Colors.red, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        '$_unreadMentionsCount mention${_unreadMentionsCount > 1 ? 's' : ''} en attente',
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(Icons.arrow_forward, color: Colors.red, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          _buildInputBar(),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  //  BANNIÈRE ÉPINGLÉE
  // ──────────────────────────────────────────────────────────────

  Widget _buildPinnedBanner(GroupMessage msg) {
    return GestureDetector(
      onTap: () => _scrollToMessage(msg.id),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.amber.shade200),
        ),
        child: Row(
          children: [
            const Icon(Icons.push_pin, size: 16, color: Colors.amber),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Message épinglé',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.amber.shade800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _getPinnedPreviewText(msg),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
            if (_myRole == 'admin')
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => _api.unpinGroupMessage(widget.groupId, msg.id),
              ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  //  MENU OPTIONS D'UN MESSAGE (AMÉLIORÉ)
  // ──────────────────────────────────────────────────────────────

  void _showMessageOptions(int index) {
    if (index < 0 || index >= _messages.length) return;
    final msg = _messages[index];
    final isAdmin = _myRole == 'admin';
    final isCurrentlyPinned = (_pinnedMessage?.id == msg.id);
    final bool canDelete = msg.senderId == _meId ||
        _myGlobalRole == 'admin' ||
        isAdmin;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.reply, color: Color(0xFF9E1B22)),
              title: const Text('Répondre'),
              onTap: () {
                Navigator.pop(ctx);
                _replyTo(msg);
              },
            ),
            if (msg.senderId == _meId && !msg.isSystem)
              ListTile(
                leading: const Icon(Icons.edit_rounded, color: Colors.blue),
                title: const Text('Modifier'),
                onTap: () {
                  Navigator.pop(ctx);
                  _editGroupMessage(msg);
                },
              ),
            if (isAdmin)
              ListTile(
                leading: Icon(isCurrentlyPinned ? Icons.push_pin_outlined : Icons.push_pin),
                title: Text(isCurrentlyPinned ? 'Désépingler le message' : 'Épingler le message'),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (isCurrentlyPinned) {
                    await _api.unpinGroupMessage(widget.groupId, msg.id);
                  } else {
                    await _api.pinGroupMessage(widget.groupId, msg.id);
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.orange),
              title: const Text('Supprimer pour moi'),
              onTap: () {
                Navigator.pop(ctx);
                _deleteGroupMessageForMe(msg);
              },
            ),
            if (canDelete)
              ListTile(
                leading: const Icon(Icons.delete_forever_rounded, color: Colors.red),
                title: const Text('Supprimer pour tout le monde'),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteMessage(msg);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  //  OUVERTURE DE FICHIER
  // ──────────────────────────────────────────────────────────────

  Future<void> _openFile(String? fileUrl, String? fileName) async {
    if (fileUrl == null || fileUrl.isEmpty) return;
    final uri = Uri.parse('${AppConstants.baseUrl}$fileUrl');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      _showError('Impossible d\'ouvrir ce fichier: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────
  //  WIDGET DE CITATION
  // ──────────────────────────────────────────────────────────────

  Widget _buildQuoteWidget(GroupMessage msg) {
    final content = msg.content ?? '';
    final lines = content.split('\n').where((line) => line.trimLeft().startsWith('> ')).toList();
    if (lines.isEmpty) return const SizedBox.shrink();

    final List<String?> lineTargetIds = [];
    final parentId = msg.replyToId;
    lineTargetIds.add(parentId);
    if (lines.length > 1) {
      String? grandParentId;
      if (parentId != null && parentId.isNotEmpty) {
        final parent = _messages.firstWhere(
          (m) => m.id == parentId,
          orElse: () => GroupMessage(id: '', groupId: '', senderId: '', content: '', isSystem: false, isRead: false, createdAt: DateTime.now()),
        );
        if (parent.id.isNotEmpty) grandParentId = parent.replyToId;
      }
      lineTargetIds.add(grandParentId);
    }

    final children = <Widget>[];
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final targetId = i < lineTargetIds.length ? lineTargetIds[i] : null;
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
                    Text(
                      author,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF9E1B22),
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    contentPart,
                    style: TextStyle(
                      fontSize: 12,
                      color: canNavigate ? Colors.blue[700] : Colors.black54,
                      decoration: canNavigate ? TextDecoration.underline : null,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
        border: Border(left: BorderSide(color: const Color(0xFF9E1B22), width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  //  BULLE DE MESSAGE
  // ──────────────────────────────────────────────────────────────

  Widget _buildBubble(GroupMessage msg, int index) {
    // Détection des partages de post
    if (MessageUtils.isPostShare(msg.content)) {
      final postId = MessageUtils.extractPostId(msg.content);
      if (postId != null) {
        return FutureBuilder<Map<String, dynamic>>(
          future: _api.getPost(postId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF9E1B22))),
                    SizedBox(width: 8),
                    Text('📤 Chargement du post...'),
                  ],
                ),
              );
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.share, size: 16, color: Colors.grey),
                      SizedBox(width: 8),
                      Expanded(child: Text('Un post a été envoyé')),
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
            final sharedByName = msg.username ?? 'quelqu\'un';
            final extraText = _getDisplayContent(msg);

            return GestureDetector(
              key: _messageKeys.putIfAbsent(msg.id, () => GlobalKey()),
              onLongPress: () => _showMessageOptions(index),
              behavior: HitTestBehavior.translucent,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SharedPostCard(
                      metadata: metadata,
                      onTap: () => _navigateToPost(postId),
                      sharedBy: sharedByName,
                    ),
                    if (extraText.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _buildHighlightedText(extraText, textColor: Colors.black87),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      }
    }

    // Messages système
    if (msg.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              msg.content ?? '',
              style: TextStyle(color: Colors.grey[600], fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    // Messages normaux
    final bool isMe = msg.senderId == _meId;

    String? quoteText;
    String? mainContent = msg.content;
    if (msg.content != null && msg.content!.startsWith('> ') && msg.content!.contains('\n\n')) {
      final parts = msg.content!.split('\n\n');
      quoteText = parts.first;
      mainContent = parts.length > 1 ? parts.sublist(1).join('\n\n') : null;
    }

    final key = _messageKeys.putIfAbsent(msg.id, () => GlobalKey());

    return GestureDetector(
      key: key,
      onLongPress: () => _showMessageOptions(index),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          constraints: const BoxConstraints(maxWidth: 280),
          decoration: BoxDecoration(
            color: msg.id == _highlightedMessageId
                ? Colors.white
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isMe)
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 2),
                  child: Text(
                    msg.username ?? 'Membre',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF9E1B22),
                    ),
                  ),
                ),
              if (quoteText != null)
                _buildQuoteWidget(msg),
              if ((mainContent != null && mainContent.isNotEmpty) || (msg.fileType != null && msg.fileUrl != null))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe ? const Color(0xFF9E1B22) : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isMe ? 18 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: _buildBubbleContent(msg, isMe, mainContent),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                child: Text(
                  timeago.format(msg.createdAt, locale: 'fr'),
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBubbleContent(GroupMessage msg, bool isMe, String? customContent) {
    final textColor = isMe ? Colors.white : Colors.black87;
    final hasFile = msg.fileType != null && msg.fileUrl != null;
    final hasText = (customContent != null && customContent.isNotEmpty) || (msg.content != null && msg.content!.isNotEmpty);

    if (!hasFile && !hasText) {
      return const SizedBox.shrink();
    }

    if (!hasFile) {
      final displayText = customContent ?? msg.content ?? '';
      return _buildHighlightedText(
        displayText,
        mentionColor: isMe ? Colors.white : Colors.blue[700],
        textColor: textColor,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildFileWidget(msg, isMe),
        if (hasText) ...[
          const SizedBox(height: 6),
          _buildHighlightedText(
            customContent ?? msg.content ?? '',
            mentionColor: isMe ? Colors.white : Colors.blue[700],
            textColor: textColor,
          ),
        ],
      ],
    );
  }

  // ============================================================
  // WIDGET FICHIER AVEC SUPPORT VIDÉO (CORRIGÉ)
  // ============================================================
  Widget _buildFileWidget(GroupMessage msg, bool isMe) {
    final textColor = isMe ? Colors.white : Colors.black87;
    final ext = (msg.fileName ?? '').split('.').last.toLowerCase();
    final isImage = msg.fileType == 'image';
    final isVideo = msg.fileType == 'video' || MediaUtils.isVideo(msg.fileUrl ?? '');
    final isAudio = msg.fileType == 'audio';
    final isPdf = msg.fileType == 'pdf' || ext == 'pdf';

    // ✅ Construction de l'URL complète
    final fullUrl = msg.fileUrl != null && msg.fileUrl!.startsWith('http')
        ? msg.fileUrl!
        : '${AppConstants.baseUrl}${msg.fileUrl ?? ''}';

    final hasValidUrl = msg.fileUrl != null && msg.fileUrl!.isNotEmpty && msg.fileUrl != 'placeholder';

    print('📎 Fichier : ${msg.fileName} | URL : $fullUrl | Type : ${msg.fileType}');

    // ✅ VIDÉO
    if (isVideo && hasValidUrl) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _VideoMessagePlayer(fileUrl: fullUrl, isMe: isMe),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam, size: 14, color: textColor.withOpacity(0.6)),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  msg.fileName ?? 'Vidéo',
                  style: TextStyle(color: textColor.withOpacity(0.6), fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      );
    }

    // ✅ IMAGE
    if (isImage && hasValidUrl) {
      return GestureDetector(
        onTap: () => _openFile(msg.fileUrl, msg.fileName),
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _buildNetworkImage(
                fullUrl, // ✅ utiliser fullUrl
                width: 200,
                height: 150,
                fit: BoxFit.cover,
              ),
            ),
            Container(
              width: 200,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: const BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
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

    // ✅ AUTRES (audio, pdf, document)
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

    return InkWell(
      onTap: () => _openFile(msg.fileUrl, msg.fileName),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: textColor.withOpacity(0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
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

  // ──────────────────────────────────────────────────────────────
  //  NAVIGATION VERS POST
  // ──────────────────────────────────────────────────────────────

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

  // ──────────────────────────────────────────────────────────────
  //  BARRE DE SAISIE
  // ──────────────────────────────────────────────────────────────

  Widget _buildInputBar() {
    return Column(
      children: [
        if (_replyingTo != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: Colors.grey[100],
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Réponse à ${_replyingTo!.username ?? 'Membre'}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF9E1B22)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _replyingTo!.content ?? 'Fichier joint',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: _cancelReply,
                ),
              ],
            ),
          ),
        Container(
          padding: EdgeInsets.only(
            left: 8,
            right: 8,
            top: 8,
            bottom: MediaQuery.of(context).padding.bottom + 8,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey[200]!)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.attach_file, color: Color(0xFF9E1B22)),
                onPressed: _showAttachMenu,
              ),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  maxLines: null,
                  decoration: InputDecoration(
                    hintText: _replyingTo != null ?: 'Écrire un message... (Utilisez @ pour mentionner)',
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: const Color(0xFF9E1B22),
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white, size: 18),
                  onPressed: _send,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}