import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cross_file/cross_file.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/group_message.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/socket_service.dart';
import '../../utils/constants.dart';
import 'group_info_screen.dart';

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
  bool _loading = true;
  bool _sending = false;
  String _meId = '';
  String _groupName = '';
  int _memberCount = 0;
  String _myRole = '';

  @override
  void initState() {
    super.initState();
    _meId = context.read<AuthProvider>().user?.id ?? '';
    _groupName = widget.groupName;
    _loadMessages();
    _loadGroupInfo();
    _loadPinnedMessage();

    _socket.joinGroup(widget.groupId);

    _socket.onGroupMessage((data) {
      if (data['group_id']?.toString() != widget.groupId) return;
      if (!mounted) return;
      final msg = GroupMessage.fromJson(data);
      if (_messages.any((m) => m.id == msg.id)) return;
      if (msg.senderId == _meId) {
        final tempIndex = _messages.indexWhere((m) => m.id.startsWith('temp-') && m.content == msg.content);
        if (tempIndex != -1) {
          setState(() {
            _messages[tempIndex] = msg;
          });
          _scrollToBottom();
          return;
        }
      }
      setState(() => _messages.add(msg));
      _scrollToBottom();
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

    // Écouteurs pour l'épinglage (corrigés)
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
  }

  @override
  void dispose() {
    _socket.leaveGroup(widget.groupId);
    _socket.removeGroupListeners();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadGroupInfo() async {
    try {
      final info = await _api.getGroupDetail(widget.groupId);
      if (mounted) {
        setState(() {
          final members = info['members'] as List?;
          _memberCount = members?.length ?? (info['member_count'] ?? 0) as int;
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
      final data = await _api.getGroupMessages(widget.groupId);
      setState(() {
        _messages = data.map((j) => GroupMessage.fromJson(j)).toList();
        _loading = false;
      });
      _scrollToBottom();
    } catch (e) {
      debugPrint('Error loading messages: $e');
      setState(() => _loading = false);
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

  void _showMessageOptions(GroupMessage msg) {
    final isAdmin = _myRole == 'admin';
    if (!isAdmin) return;

    final isCurrentlyPinned = (_pinnedMessage?.id == msg.id);

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
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _openFile(String? fileUrl, String? fileName) async {
    if (fileUrl == null || fileUrl.isEmpty) return;
    final uri = Uri.parse('${AppConstants.baseUrl}$fileUrl');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      _showError('Impossible d\'ouvrir ce fichier: $e');
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    _ctrl.clear();

    final tempId = 'temp-${DateTime.now().millisecondsSinceEpoch}';
    final me = context.read<AuthProvider>().user;
    final temp = GroupMessage(
      id: tempId,
      groupId: widget.groupId,
      senderId: _meId,
      content: text,
      isSystem: false,
      isRead: false,
      createdAt: DateTime.now(),
      username: me?.username,
    );
    setState(() {
      _messages.add(temp);
      _sending = true;
    });
    _scrollToBottom();

    try {
      await _api.sendGroupMessage(widget.groupId, text);
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
    final temp = GroupMessage(
      id: tempId,
      groupId: widget.groupId,
      senderId: _meId,
      content: caption,
      isSystem: false,
      isRead: false,
      createdAt: DateTime.now(),
      username: me?.username,
      fileUrl: file.path,
      fileName: originalName,
      fileType: 'image',
    );
    setState(() => _messages.add(temp));
    _scrollToBottom();

    try {
      await _api.sendGroupMessageWithFile(widget.groupId, file.path, content: caption, originalName: originalName);
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
            child: Row(children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white24,
                child: Text(
                  _groupName.isNotEmpty ? _groupName[0].toUpperCase() : 'G',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_groupName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                  Text(
                    _memberCount == 0 ? 'Chargement...' : '$_memberCount membre${_memberCount > 1 ? 's' : ''}',
                    style: const TextStyle(fontSize: 10, color: Colors.white70),
                  ),
                ],
              )),
            ]),
          ),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.info_outline), onPressed: _openGroupInfo),
        ],
      ),
      body: Column(children: [
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
                          itemBuilder: (_, i) => _buildBubble(_messages[i]),
                        ),
                  ),
                ],
              ),
        ),
        if (_sending) const LinearProgressIndicator(color: Color(0xFF9E1B22)),
        _buildInputBar(),
      ]),
    );
  }

  Widget _buildPinnedBanner(GroupMessage msg) {
    return Container(
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
                  msg.content ?? (msg.fileType != null ? '📎 Fichier joint' : ''),
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
    );
  }

  Widget _buildBubble(GroupMessage msg) {
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

    final bool isMe = msg.senderId == _meId;

    return GestureDetector(
      onLongPress: () => _showMessageOptions(msg),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          constraints: const BoxConstraints(maxWidth: 280),
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
                child: _buildBubbleContent(msg, isMe),
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

  Widget _buildBubbleContent(GroupMessage msg, bool isMe) {
    final textColor = isMe ? Colors.white : Colors.black87;
    final hasFile = msg.fileType != null && msg.fileUrl != null;
    final hasText = msg.content != null && msg.content!.isNotEmpty;

    if (!hasFile) {
      return Text(
        msg.content ?? '',
        style: TextStyle(color: textColor, fontSize: 15),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildFileWidget(msg, isMe),
        if (hasText) ...[
          const SizedBox(height: 6),
          Text(msg.content!, style: TextStyle(color: textColor, fontSize: 14)),
        ],
      ],
    );
  }

  Widget _buildFileWidget(GroupMessage msg, bool isMe) {
    final textColor = isMe ? Colors.white : Colors.black87;
    final ext = (msg.fileName ?? '').split('.').last.toLowerCase();
    final isImage = msg.fileType == 'image';
    final isVideo = msg.fileType == 'video';
    final isAudio = msg.fileType == 'audio';
    final isPdf = ext == 'pdf';

    if (isImage) {
      return GestureDetector(
        onTap: () => _openFile(msg.fileUrl, msg.fileName),
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
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
                        color: const Color(0xFF9E1B22),
                      ),
                    ),
                  );
                },
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey, size: 48),
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

    return InkWell(
      onTap: () => _openFile(msg.fileUrl, msg.fileName),
      borderRadius: BorderRadius.circular(8),
      child: _buildFileCard(
        icon: isVideo
            ? Icons.play_circle_fill
            : isAudio
                ? Icons.audiotrack
                : isPdf
                    ? Icons.picture_as_pdf
                    : Icons.insert_drive_file,
        iconColor: isVideo
            ? (isMe ? Colors.white : Colors.blue[400]!)
            : isAudio
                ? (isMe ? Colors.white : Colors.purple[400]!)
                : isPdf
                    ? (isMe ? Colors.white : Colors.red[400]!)
                    : (isMe ? Colors.white70 : Colors.orange[400]!),
        bgColor: isVideo
            ? (isMe ? Colors.white24 : Colors.blue[50]!)
            : isAudio
                ? (isMe ? Colors.white24 : Colors.purple[50]!)
                : isPdf
                    ? (isMe ? Colors.white24 : Colors.red[50]!)
                    : (isMe ? Colors.white24 : Colors.orange[50]!),
        fileName: msg.fileName ?? 'Fichier',
        ext: ext,
        textColor: textColor,
      ),
    );
  }

  Widget _buildFileCard({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String fileName,
    required String ext,
    required Color textColor,
  }) {
    return Container(
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
                  fileName,
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
                      'Appuyer pour télécharger',
                      style: TextStyle(color: textColor.withOpacity(0.6), fontSize: 10),
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
                hintText: 'Écrire un message...',
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
    );
  }
}