// lib/screens/messages/group_chat_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../models/message.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';

class GroupChatScreen extends StatefulWidget {
  final Group group;
  const GroupChatScreen({super.key, required this.group});
  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _api = ApiService();
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  List<GroupMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    try {
      final data = await _api.getGroupMessages(widget.group.id);
      setState(() {
        _messages = data.map((j) => GroupMessage.fromJson(j)).toList().reversed.toList();
        _loading = false;
      });
      _scrollToBottom();
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    _ctrl.clear();
    setState(() => _sending = true);

    final me = context.read<AuthProvider>().user!;
    final temp = GroupMessage(
      id: 'temp-${DateTime.now().millisecondsSinceEpoch}',
      groupId: widget.group.id,
      senderId: me.id,
      content: text,
      createdAt: DateTime.now(),
      username: me.username,
    );
    setState(() { _messages.add(temp); _sending = false; });
    _scrollToBottom();

    try {
      await _api.sendGroupMessage(widget.group.id, text);
    } catch (e) {
      setState(() => _messages.removeWhere((m) => m.id == temp.id));
      _ctrl.text = text;
      String msg = 'Envoi impossible';
      if (e.toString().contains('inapproprié')) msg = 'Contenu inapproprié détecté';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final meId = context.read<AuthProvider>().user?.id ?? '';

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF9E1B22),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.group.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            Text(widget.group.type, style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF9E1B22)))
                : _messages.isEmpty
                    ? const Center(child: Text('Aucun message. Soyez le premier !', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length,
                        itemBuilder: (_, i) => _buildBubble(_messages[i], meId),
                      ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildBubble(GroupMessage msg, String meId) {
    final isMe = msg.senderId == meId;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        constraints: const BoxConstraints(maxWidth: 280),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 2),
                child: Text(msg.username ?? '', style: const TextStyle(fontSize: 11, color: Color(0xFF006838), fontWeight: FontWeight.bold)),
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
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: Text(msg.content, style: TextStyle(color: isMe ? Colors.white : Colors.black87, fontSize: 15)),
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
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.only(left: 8, right: 8, top: 8, bottom: MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              maxLines: null,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: 'Écrire un message...',
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
              onPressed: _send,
            ),
          ),
        ],
      ),
    );
  }
}