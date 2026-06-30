import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cross_file/cross_file.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/message.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/socket_service.dart';
import '../../utils/constants.dart';

class DmScreen extends StatefulWidget {
  final String receiverId;
  final String receiverName;
  final bool isGroup; // true = groupe, false = message direct
  const DmScreen({
    super.key,
    required this.receiverId,
    required this.receiverName,
    this.isGroup = false,
  });

  @override
  State<DmScreen> createState() => _DmScreenState();
}

class _DmScreenState extends State<DmScreen> {
  final _api = ApiService();
  final _socket = SocketService();
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  List<Message> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String _meId = '';

  @override
  void initState() {
    super.initState();
    _meId = context.read<AuthProvider>().user?.id ?? '';
    _loadConversation();

    // Écoute socket uniquement pour les DM (les groupes auraient leur propre événement)
    if (!widget.isGroup) {
      _socket.onNewMessage((data) {
        final senderId = data['senderId']?.toString() ?? data['sender_id']?.toString() ?? '';
        if (senderId == widget.receiverId && mounted) {
          final incoming = Message.fromJson({
            ...data,
            'sender_id': senderId,
            'receiver_id': _meId,
          });
          if (_messages.any((m) => m.id == incoming.id)) return;
          setState(() => _messages.add(incoming));
          _scrollToBottom();
          _socket.markRead(incoming.id);
        }
      });
    }
    // Si ton backend envoie un événement pour les groupes, décommente ceci :
    // _socket.onNewGroupMessage((data) { ... });
  }

  @override
  void dispose() {
    _socket.removeListener('new_message');
    // _socket.removeListener('new_group_message');
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
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

      // Marquer comme lus (uniquement pour les DM)
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
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _openFile(String? fileUrl, String? fileName) async {
    if (fileUrl == null || fileUrl.isEmpty) return;
    final fullUrl = '${AppConstants.baseUrl}$fileUrl';
    final uri = Uri.parse(fullUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      _showError('Impossible d\'ouvrir ce fichier: $e');
    }
  }

  // ------------------------------------------------------------
  // Envoi d’un message texte (DM ou groupe)
  // ------------------------------------------------------------
  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    _ctrl.clear();

    final tempId = 'temp-${DateTime.now().millisecondsSinceEpoch}';
    final temp = Message(
      id: tempId,
      senderId: _meId,
      receiverId: widget.receiverId,
      content: text,
      isRead: false,
      isEdited: false,
      isDeleted: false,
      createdAt: DateTime.now(),
    );
    setState(() {
      _messages.add(temp);
      _sending = true;
    });
    _scrollToBottom();

    try {
      Map<String, dynamic> res;
      if (widget.isGroup) {
        res = await _api.sendGroupMessage(widget.receiverId, text);
      } else {
        res = await _api.sendMessage(widget.receiverId, text);
      }

      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == tempId);
          if (idx != -1) {
            _messages[idx] = Message.fromJson({
              ...res,
              'sender_id':   res['senderId']   ?? res['sender_id']   ?? _meId,
              'receiver_id': res['receiverId'] ?? res['receiver_id'] ?? widget.receiverId,
            });
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

  // ------------------------------------------------------------
  // MENU D’ATTACHEMENT (inchangé)
  // ------------------------------------------------------------
  void _showAttachMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
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
        ]),
      ),
    );
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (picked == null || !mounted) return;
      _showPreviewDialog(XFile(picked.path, name: picked.name), originalName: picked.name);
    } catch (e) {
      _showError('Erreur sélection image: $e');
    }
  }

  Future<void> _pickVideo() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickVideo(source: ImageSource.gallery);
      if (picked == null || !mounted) return;
      _showPreviewDialog(XFile(picked.path, name: picked.name), originalName: picked.name);
    } catch (e) {
      _showError('Erreur sélection vidéo: $e');
    }
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
      final originalName = f.name;
      if (kIsWeb) {
        final bytes = f.bytes;
        if (bytes == null) { _showError('Impossible de lire ce fichier.'); return; }
        final xfile = XFile.fromData(bytes, name: originalName, mimeType: _mimeFromExt(f.extension ?? ''));
        _showPreviewDialog(xfile, originalName: originalName);
      } else {
        final path = f.path;
        if (path == null) { _showError('Impossible de lire ce fichier.'); return; }
        _showPreviewDialog(XFile(path, name: originalName), originalName: originalName);
      }
    } catch (e) {
      _showError('Erreur sélection document: $e');
    }
  }

  String _mimeFromExt(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':  return 'application/pdf';
      case 'doc':  return 'application/msword';
      case 'docx': return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':  return 'application/vnd.ms-excel';
      case 'xlsx': return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt':  return 'application/vnd.ms-powerpoint';
      case 'pptx': return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'txt':  return 'text/plain';
      case 'csv':  return 'text/csv';
      case 'zip':  return 'application/zip';
      default:     return 'application/octet-stream';
    }
  }

  void _showPreviewDialog(XFile file, {required String originalName}) {
    final ext = originalName.split('.').last.toLowerCase();
    final isImage = ['jpg','jpeg','png','gif','webp','bmp'].contains(ext);
    final isVideo = ['mp4','mov','avi','mkv','webm'].contains(ext);
    final isPdf   = ext == 'pdf';
    final captionCtrl = TextEditingController(text: _ctrl.text.trim());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          left: 16, right: 16, top: 16,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(ctx),
            ),
            const Spacer(),
            const Text('Aperçu', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
          ]),
          const SizedBox(height: 12),
          if (isImage)
            FutureBuilder<Uint8List>(
              future: file.readAsBytes(),
              builder: (_, snap) {
                if (snap.hasData) return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(snap.data!, height: 260, fit: BoxFit.contain),
                );
                if (snap.hasError) return _fileIconPreview(Icons.broken_image, Colors.grey[400]!, ext, originalName);
                return const SizedBox(
                  height: 260,
                  child: Center(child: CircularProgressIndicator(color: Colors.white)),
                );
              },
            )
          else
            _fileIconPreview(
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
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
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
                );
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
        ]),
      ),
    );
  }

  Widget _fileIconPreview(IconData icon, Color color, String ext, String name) {
    return Container(
      height: 130,
      decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(12)),
      child: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: color, size: 56),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(name,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 4),
          Text(ext.toUpperCase(), style: TextStyle(color: Colors.grey[400], fontSize: 11)),
        ]),
      ),
    );
  }

  Future<void> _sendFile(XFile file, {required String originalName, String? caption}) async {
    setState(() => _sending = true);
    try {
      Map<String, dynamic> res;
      if (widget.isGroup) {
        res = await _api.sendGroupMessageWithFile(
          widget.receiverId,
          file.path,
          content: caption,
          originalName: originalName,
        );
      } else {
        res = await _api.sendMessageWithFile(
          widget.receiverId,
          file.path,
          content: caption,
          originalName: originalName,
        );
      }
      if (mounted) {
        setState(() {
          _messages.add(Message.fromJson({
            ...res,
            'sender_id':   res['senderId']   ?? res['sender_id']   ?? _meId,
            'receiver_id': res['receiverId'] ?? res['receiver_id'] ?? widget.receiverId,
            'file_name':   res['file_name']  ?? res['fileName']    ?? originalName,
            'file_url':    res['file_url']   ?? res['fileUrl'],
            'file_type':   res['file_type']  ?? res['fileType'],
          }));
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) _showError('Erreur envoi: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  // ------------------------------------------------------------
  // Construction de l’interface
  // ------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF9E1B22),
        foregroundColor: Colors.white,
        title: Row(children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.white24,
            child: Text(
              widget.receiverName.isNotEmpty ? widget.receiverName[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.receiverName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            Text(
              widget.isGroup ? '👥 Groupe' : '🔒 Chiffré',
              style: const TextStyle(fontSize: 9),
            ),
          ]),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF9E1B22)))
              : _messages.isEmpty
                  ? const Center(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.lock_outline, size: 48, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('Début de la conversation', style: TextStyle(color: Colors.grey)),
                      ]),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(12),
                      itemCount: _messages.length,
                      itemBuilder: (_, i) => _buildBubble(_messages[i]),
                    ),
        ),
        if (_sending) const LinearProgressIndicator(color: Color(0xFF9E1B22)),
        _buildInputBar(),
      ]),
    );
  }

  Widget _buildBubble(Message msg) {
    final isMe = msg.senderId == _meId;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        constraints: const BoxConstraints(maxWidth: 280),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
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
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: _buildBubbleContent(msg, isMe),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(timeago.format(msg.createdAt, locale: 'fr'),
                    style: const TextStyle(fontSize: 10, color: Colors.grey)),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    msg.isRead ? Icons.done_all : Icons.done,
                    size: 12,
                    color: msg.isRead ? const Color(0xFF006838) : Colors.grey,
                  ),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBubbleContent(Message msg, bool isMe) {
    final textColor = isMe ? Colors.white : Colors.black87;
    final hasFile = msg.fileType != null && msg.fileUrl != null;
    final hasText = msg.content != null && msg.content!.isNotEmpty;

    if (!hasFile) {
      return Text(msg.content ?? '', style: TextStyle(color: textColor, fontSize: 15));
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

  Widget _buildFileWidget(Message msg, bool isMe) {
    final textColor = isMe ? Colors.white : Colors.black87;
    final ext = (msg.fileName ?? '').split('.').last.toLowerCase();
    final isImage = msg.fileType == 'image';
    final isVideo = msg.fileType == 'video';
    final isAudio = msg.fileType == 'audio';
    final isPdf   = ext == 'pdf';

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
                width: 200, fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) {
                  if (progress == null) return child;
                  return SizedBox(
                    width: 200, height: 150,
                    child: Center(child: CircularProgressIndicator(
                      value: progress.expectedTotalBytes != null
                          ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                          : null,
                      color: const Color(0xFF9E1B22),
                    )),
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
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.download, size: 12, color: Colors.white),
                SizedBox(width: 4),
                Text('Appuyer pour télécharger', style: TextStyle(color: Colors.white, fontSize: 10)),
              ]),
            ),
          ],
        ),
      );
    }

    if (isVideo) {
      return InkWell(
        onTap: () => _openFile(msg.fileUrl, msg.fileName),
        borderRadius: BorderRadius.circular(8),
        child: _buildFileCard(
          icon: Icons.play_circle_fill,
          iconColor: isMe ? Colors.white : Colors.blue[400]!,
          bgColor: isMe ? Colors.white24 : Colors.blue[50]!,
          fileName: msg.fileName ?? 'Vidéo',
          ext: ext, textColor: textColor,
        ),
      );
    }

    if (isAudio) {
      return InkWell(
        onTap: () => _openFile(msg.fileUrl, msg.fileName),
        borderRadius: BorderRadius.circular(8),
        child: _buildFileCard(
          icon: Icons.audiotrack,
          iconColor: isMe ? Colors.white : Colors.purple[400]!,
          bgColor: isMe ? Colors.white24 : Colors.purple[50]!,
          fileName: msg.fileName ?? 'Audio',
          ext: ext, textColor: textColor,
        ),
      );
    }

    return InkWell(
      onTap: () => _openFile(msg.fileUrl, msg.fileName),
      borderRadius: BorderRadius.circular(8),
      child: _buildFileCard(
        icon: isPdf ? Icons.picture_as_pdf : Icons.insert_drive_file,
        iconColor: isPdf
            ? (isMe ? Colors.white : Colors.red[400]!)
            : (isMe ? Colors.white70 : Colors.orange[400]!),
        bgColor: isPdf
            ? (isMe ? Colors.white24 : Colors.red[50]!)
            : (isMe ? Colors.white24 : Colors.orange[50]!),
        fileName: msg.fileName ?? 'Document',
        ext: ext, textColor: textColor,
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
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(fileName,
              style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 13),
              maxLines: 2, overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Row(children: [
              Icon(Icons.download, size: 11, color: textColor.withOpacity(0.6)),
              const SizedBox(width: 3),
              Text('Appuyer pour télécharger',
                  style: TextStyle(color: textColor.withOpacity(0.6), fontSize: 10)),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 8, right: 8, top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(children: [
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
              filled: true, fillColor: Colors.grey[100],
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
      ]),
    );
  }
}