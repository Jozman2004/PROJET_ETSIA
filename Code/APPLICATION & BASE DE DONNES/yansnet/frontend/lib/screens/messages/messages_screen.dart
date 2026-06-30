import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/api_service.dart';
import '../../services/socket_service.dart';
import '../../utils/constants.dart';
import 'dm_screen.dart';
import 'group_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen>
    with SingleTickerProviderStateMixin {
  final _api    = ApiService();
  final _socket = SocketService();
  late TabController _tabController;

  List<Map<String, dynamic>> _conversations = [];
  List<Map<String, dynamic>> _groups        = [];
  bool _loadingDm    = true;
  bool _loadingGroup = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAll();
    _listenSocketEvents();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _listenSocketEvents() {
    _socket.onAddedToGroup((_) => _loadGroups());
    _socket.onGroupDeleted((_) => _loadGroups());
    _socket.onGroupMessage((_) => _loadGroups());
    _socket.onNewMessage((_)   => _loadConversations());
  }

  Future<void> _loadAll() => Future.wait([_loadConversations(), _loadGroups()]);

  Future<void> _loadConversations() async {
    setState(() => _loadingDm = true);
    try {
      final data = await _api.getConversations();
      if (mounted) {
        setState(() {
          _conversations = List<Map<String, dynamic>>.from(data);
          _loadingDm     = false;
        });
      }
    } catch (e) {
      print('Erreur chargement DM: $e');
      if (mounted) setState(() => _loadingDm = false);
    }
  }

  Future<void> _loadGroups() async {
    setState(() => _loadingGroup = true);
    try {
      final data = await _api.getMyGroups();
      if (mounted) {
        setState(() {
          _groups        = List<Map<String, dynamic>>.from(data);
          _loadingGroup  = false;
        });
      }
    } catch (e) {
      print('Erreur chargement groupes: $e');
      if (mounted) setState(() => _loadingGroup = false);
    }
  }

  void _showNewDmDialog() {
    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> results = [];
    bool searching = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 16, right: 16, top: 16,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Nouvelle conversation',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: searchCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Rechercher un utilisateur...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none),
              ),
              onChanged: (val) async {
                if (val.trim().length < 2) {
                  setModal(() => results = []);
                  return;
                }
                setModal(() => searching = true);
                try {
                  final data = await _api.searchUsers(val.trim());
                  setModal(() {
                    results   = List<Map<String, dynamic>>.from(data);
                    searching = false;
                  });
                } catch (_) {
                  setModal(() => searching = false);
                }
              },
            ),
            const SizedBox(height: 8),
            if (searching)
              const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(color: Color(0xFF9E1B22))),
            if (results.isNotEmpty)
              SizedBox(
                height: 300,
                child: ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (_, i) {
                    final user      = results[i];
                    final avatarUrl = user['avatar_url'] != null
                        ? '${AppConstants.baseUrl}${user['avatar_url']}'
                        : null;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                        backgroundColor: const Color(0xFF9E1B22),
                        child: avatarUrl == null
                            ? Text(
                                (user['full_name'] ?? '?')[0].toUpperCase(),
                                style: const TextStyle(color: Colors.white))
                            : null,
                      ),
                      title:    Text(user['full_name'] ?? ''),
                      subtitle: Text('@${user['username'] ?? ''}'),
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DmScreen(
                              receiverId:   user['id'].toString(),
                              receiverName: user['full_name'] ?? '',
                              isGroup:      false,
                            ),
                          ),
                        ).then((_) => _loadConversations());
                      },
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }

  void _showNewGroupFlow() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => GroupCreationScreen()),
    );
    await Future.delayed(const Duration(milliseconds: 500));
    await _loadGroups();
    await _loadConversations();

    if (result != null && mounted) {
      final groupId   = result['groupId']?.toString() ?? '';
      final groupName = result['groupName']?.toString() ?? '';
      if (groupId.isNotEmpty) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroupScreen(groupId: groupId, groupName: groupName),
          ),
        );
        await _loadGroups();
        await _loadConversations();
      }
    }
  }

  void _showNewChatMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 8),
          ListTile(
            leading:  const Icon(Icons.chat, color: Color(0xFF9E1B22)),
            title:    const Text('Nouvelle conversation'),
            onTap: () { Navigator.pop(ctx); _showNewDmDialog(); },
          ),
          ListTile(
            leading:  const Icon(Icons.group_add, color: Color(0xFF9E1B22)),
            title:    const Text('Nouveau groupe'),
            onTap: () { Navigator.pop(ctx); _showNewGroupFlow(); },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        backgroundColor: const Color(0xFF9E1B22),
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.edit_square),
            onSelected: (value) {
              if (value == 'dm')    _showNewDmDialog();
              if (value == 'group') _showNewGroupFlow();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                  value: 'dm',
                  child: Row(children: [
                    Icon(Icons.chat),
                    SizedBox(width: 12),
                    Text('Nouvelle conversation'),
                  ])),
              const PopupMenuItem(
                  value: 'group',
                  child: Row(children: [
                    Icon(Icons.group_add),
                    SizedBox(width: 12),
                    Text('Nouveau groupe'),
                  ])),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: [
            Tab(text: 'Messages${_unreadDm > 0 ? ' ($_unreadDm)' : ''}'),
            Tab(text: 'Groupes${_unreadGroups > 0 ? ' ($_unreadGroups)' : ''}'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          RefreshIndicator(
            onRefresh: _loadConversations,
            color: const Color(0xFF9E1B22),
            child: _loadingDm
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF9E1B22)))
                : _conversations.isEmpty
                    ? _emptyState('Aucune conversation', 'Démarrez une conversation',
                        Icons.chat_bubble_outline, _showNewDmDialog)
                    : ListView.builder(
                        itemCount: _conversations.length,
                        itemBuilder: (_, i) => _buildDmTile(_conversations[i]),
                      ),
          ),
          RefreshIndicator(
            onRefresh: _loadGroups,
            color: const Color(0xFF9E1B22),
            child: _loadingGroup
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF9E1B22)))
                : _groups.isEmpty
                    ? _emptyState('Aucun groupe', 'Créez un groupe',
                        Icons.group_outlined, _showNewGroupFlow)
                    : ListView.builder(
                        itemCount: _groups.length,
                        itemBuilder: (_, i) => _buildGroupTile(_groups[i]),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showNewChatMenu,
        backgroundColor: const Color(0xFF9E1B22),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  int get _unreadDm => _conversations.fold(
      0, (s, c) => s + (int.tryParse(c['unread_count']?.toString() ?? '0') ?? 0));

  int get _unreadGroups => _groups.fold(
      0, (s, g) => s + (int.tryParse(g['unread_count']?.toString() ?? '0') ?? 0));

  Widget _buildDmTile(Map<String, dynamic> conv) {
    final otherUserId  = conv['other_user'].toString();
    final fullName     = conv['full_name'] ?? '';
    final avatarUrl    = conv['avatar_url'];
    final lastMessage  = conv['last_message'];
    final lastFileType = conv['last_file_type'];
    final unreadCount  = int.tryParse(conv['unread_count']?.toString() ?? '0') ?? 0;
    final lastTime     = conv['last_message_time'];
    final avatarUri    = avatarUrl != null ? '${AppConstants.baseUrl}$avatarUrl' : null;

    String preview = lastMessage ?? 'Nouvelle conversation';
    if (lastMessage == null && lastFileType != null) {
      preview = _fileTypeLabel(lastFileType);
    } else if (lastMessage != null && lastFileType != null) {
      preview = '${_fileTypeLabel(lastFileType)} · $lastMessage';
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF9E1B22),
        backgroundImage: avatarUri != null ? NetworkImage(avatarUri) : null,
        child: avatarUri == null
            ? Text(fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white))
            : null,
      ),
      title: Text(fullName,
          style: TextStyle(fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal)),
      subtitle: Text(preview,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: unreadCount > 0 ? FontWeight.w600 : FontWeight.normal)),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (lastTime != null)
          Text(_formatTime(lastTime), style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        if (unreadCount > 0) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(color: Color(0xFF9E1B22), shape: BoxShape.circle),
            child: Text('$unreadCount', style: const TextStyle(color: Colors.white, fontSize: 11)),
          ),
        ],
      ]),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DmScreen(
              receiverId:   otherUserId,
              receiverName: fullName,
              isGroup:      false,
            ),
          ),
        );
        await _loadConversations();
      },
    );
  }

  Widget _buildGroupTile(Map<String, dynamic> group) {
    final groupId     = group['id'].toString();
    final name        = group['name'] ?? 'Groupe';
    final memberCount = int.tryParse(group['member_count']?.toString() ?? '0') ?? 0;
    final lastMessage  = group['last_message'];
    final lastFileType = group['last_file_type'];
    final lastSender   = group['last_sender_username'];
    final unreadCount  = int.tryParse(group['unread_count']?.toString() ?? '0') ?? 0;
    final lastTime = group['last_message_time'];
    final role     = group['role'] ?? 'member';

    String preview = 'Aucun message';
    if (lastMessage != null || lastFileType != null) {
      final content = lastMessage ?? _fileTypeLabel(lastFileType ?? '');
      preview = lastSender != null ? '$lastSender: $content' : content;
    }

    return ListTile(
      leading: Stack(children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: const Color(0xFF9E1B22),
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : 'G',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
        if (role == 'admin')
          Positioned(
            bottom: 0,
            right:  0,
            child: Container(
              width:  14,
              height: 14,
              decoration: BoxDecoration(
                  color: Colors.amber,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5)),
              child: const Icon(Icons.star, size: 8, color: Colors.white),
            ),
          ),
      ]),
      title: Text(name,
          style: TextStyle(fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal)),
      subtitle: Text(preview,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontWeight: unreadCount > 0 ? FontWeight.w600 : FontWeight.normal,
              color: Colors.grey[600])),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (lastTime != null)
          Text(_formatTime(lastTime), style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        if (unreadCount > 0) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(color: Color(0xFF9E1B22), shape: BoxShape.circle),
            child: Text('$unreadCount', style: const TextStyle(color: Colors.white, fontSize: 11)),
          ),
        ] else ...[
          const SizedBox(height: 4),
          Text('$memberCount membres', style: TextStyle(fontSize: 10, color: Colors.grey[400])),
        ],
      ]),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroupScreen(groupId: groupId, groupName: name),
          ),
        );
        await _loadGroups();
      },
    );
  }

  Widget _emptyState(String title, String subtitle, IconData icon, VoidCallback onTap) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 64, color: Colors.grey[300]),
        const SizedBox(height: 16),
        Text(title, style: TextStyle(color: Colors.grey[500], fontSize: 16)),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.add),
          label: Text(subtitle),
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF9E1B22), foregroundColor: Colors.white),
        ),
      ]),
    );
  }

  String _fileTypeLabel(String type) {
    switch (type) {
      case 'image':    return 'Photo';
      case 'video':    return 'Vidéo';
      case 'audio':    return 'Audio';
      case 'document': return 'Document';
      default:         return 'Fichier';
    }
  }

  String _formatTime(dynamic rawTime) {
    try {
      final dt = rawTime is DateTime ? rawTime : DateTime.parse(rawTime.toString());
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'maintenant';
      if (diff.inHours  < 1) return '${diff.inMinutes}min';
      if (diff.inDays   < 1) return '${diff.inHours}h';
      if (diff.inDays   < 7) return '${diff.inDays}j';
      return '${dt.day}/${dt.month}';
    } catch (_) {
      return '';
    }
  }
}

// ==================== GROUP CREATION SCREENS (intégrés) ====================

class GroupCreationScreen extends StatefulWidget {
  const GroupCreationScreen({super.key});

  @override
  State<GroupCreationScreen> createState() => _GroupCreationScreenState();
}

class _GroupCreationScreenState extends State<GroupCreationScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  final List<Map<String, dynamic>> _selected = [];
  bool _searching = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().length < 2) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final results = await _api.searchUsers(query.trim());
      setState(() {
        _searchResults = List<Map<String, dynamic>>.from(results)
            .where((u) => !_selected.any((s) => s['id'] == u['id']))
            .toList();
        _searching = false;
      });
    } catch (e) {
      print('Erreur recherche: $e');
      setState(() => _searching = false);
    }
  }

  void _toggle(Map<String, dynamic> user) {
    setState(() {
      if (_selected.any((s) => s['id'] == user['id'])) {
        _selected.removeWhere((s) => s['id'] == user['id']);
        _searchResults.add(user);
      } else {
        _selected.add(user);
        _searchResults.removeWhere((r) => r['id'] == user['id']);
      }
    });
  }

  void _nextStep() {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sélectionnez au moins un participant')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupNameSetupScreen(selectedUsers: _selected),
      ),
    ).then((result) {
      if (result != null) Navigator.pop(context, result);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nouveau groupe'),
        backgroundColor: const Color(0xFF9E1B22),
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _selected.isEmpty ? null : _nextStep,
            child: Text(
              _selected.isEmpty ? 'Suivant' : 'Suivant (${_selected.length})',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: Column(children: [
        if (_selected.isNotEmpty)
          Container(
            height: 80,
            color: Colors.white,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _selected.length,
              itemBuilder: (_, i) {
                final u = _selected[i];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: const Color(0xFF9E1B22).withOpacity(0.15),
                          child: Text(
                            (u['full_name'] ?? '?')[0].toUpperCase(),
                            style: const TextStyle(color: Color(0xFF9E1B22), fontWeight: FontWeight.bold),
                          ),
                        ),
                        Positioned(
                          top: 0, right: 0,
                          child: GestureDetector(
                            onTap: () => _toggle(u),
                            child: Container(
                              width: 18, height: 18,
                              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                              child: const Icon(Icons.close, size: 11, color: Colors.white),
                            ),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 2),
                      Text(u['username'] ?? '', style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis),
                    ],
                  ),
                );
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchCtrl,
            onChanged: _search,
            decoration: InputDecoration(
              hintText: 'Rechercher un utilisateur...',
              prefixIcon: const Icon(Icons.search, color: Color(0xFF9E1B22)),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF9E1B22))))
                  : null,
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ),
        Expanded(
          child: _searchResults.isEmpty && _searchCtrl.text.length >= 2 && !_searching
              ? Center(child: Text('Aucun résultat', style: TextStyle(color: Colors.grey[500])))
              : _searchResults.isEmpty && _searchCtrl.text.isEmpty
                  ? Center(child: Text('Tapez un nom pour rechercher', style: TextStyle(color: Colors.grey[400])))
                  : ListView.builder(
                      itemCount: _searchResults.length,
                      itemBuilder: (_, i) {
                        final user = _searchResults[i];
                        final avatarUrl = user['avatar_url'] != null
                            ? '${AppConstants.baseUrl}${user['avatar_url']}'
                            : null;
                        final isSelected = _selected.any((s) => s['id'] == user['id']);
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                            backgroundColor: const Color(0xFF9E1B22),
                            child: avatarUrl == null
                                ? Text((user['full_name'] ?? '?')[0].toUpperCase(), style: const TextStyle(color: Colors.white))
                                : null,
                          ),
                          title: Text(user['full_name'] ?? ''),
                          subtitle: Text('@${user['username'] ?? ''}'),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle, color: Color(0xFF9E1B22))
                              : const Icon(Icons.add_circle_outline, color: Color(0xFF9E1B22)),
                          onTap: () => _toggle(user),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

class GroupNameSetupScreen extends StatefulWidget {
  final List<Map<String, dynamic>> selectedUsers;
  const GroupNameSetupScreen({super.key, required this.selectedUsers});

  @override
  State<GroupNameSetupScreen> createState() => _GroupNameSetupScreenState();
}

class _GroupNameSetupScreenState extends State<GroupNameSetupScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController(); // ✅ Champ description
  File? _avatarFile;
  bool _creating = false;
  Map<String, dynamic>? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final user = await _api.getMe();
      if (mounted) setState(() => _currentUser = user);
    } catch (e) {
      print('Impossible de charger l\'utilisateur courant: $e');
    }
  }

  Future<void> _pickAvatar() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) setState(() => _avatarFile = File(picked.path));
  }

  Future<void> _createGroup() async {
    final name = _nameCtrl.text.trim();
    final description = _descCtrl.text.trim(); // ✅ Récupère la description
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Donnez un nom au groupe')));
      return;
    }
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur: utilisateur non chargé')));
      return;
    }

    setState(() => _creating = true);

    try {
      final List<String> memberIds = widget.selectedUsers.map((u) => u['id'].toString()).toList();
      final String currentUserId = _currentUser!['id'].toString();
      if (!memberIds.contains(currentUserId)) {
        memberIds.add(currentUserId);
      }
      print('Création groupe: name=$name, description=$description, membres=${memberIds.length} (incluant créateur)');

      // ✅ Appel avec la description
      final res = await _api.createGroup(name, memberIds, description: description.isNotEmpty ? description : null);
      print('Réponse API: $res');

      if (!mounted) return;

      final groupId = res['id']?.toString() ?? res['groupId']?.toString() ?? res['group_id']?.toString() ?? '';
      final groupName = res['name']?.toString() ?? res['groupName']?.toString() ?? name;

      if (groupId.isEmpty) {
        throw Exception('Le serveur n\'a pas retourné d\'ID de groupe. Réponse: $res');
      }

      print('🎉 Groupe créé: id=$groupId, name=$groupName');

      await Future.delayed(const Duration(milliseconds: 300));

      if (mounted) {
        Navigator.pop(context, {'groupId': groupId, 'groupName': groupName});
      }
    } catch (e, stack) {
      print('Erreur création: $e');
      print('Stack: $stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: ${e.toString()}'), backgroundColor: Colors.red, duration: const Duration(seconds: 5)),
        );
        setState(() => _creating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalMembers = widget.selectedUsers.length + 1;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres du groupe'),
        backgroundColor: const Color(0xFF9E1B22),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            GestureDetector(
              onTap: _pickAvatar,
              child: CircleAvatar(
                radius: 52,
                backgroundColor: Colors.grey[200],
                backgroundImage: _avatarFile != null ? FileImage(_avatarFile!) : null,
                child: _avatarFile == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.camera_alt, size: 32, color: Colors.grey),
                          const SizedBox(height: 4),
                          Text('Photo', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                        ],
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 6),
            Text('Optionnelle', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
            const SizedBox(height: 24),
            // Champ nom
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              style: const TextStyle(fontSize: 18),
              decoration: InputDecoration(
                labelText: 'Nom du groupe',
                hintText: 'Ex: Promo 2024, Équipe projet...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.group, color: Color(0xFF9E1B22)),
              ),
            ),
            const SizedBox(height: 16),
            // ✅ Champ description (optionnel)
            TextField(
              controller: _descCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Description (optionnelle)',
                hintText: 'Décrivez le but du groupe...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.description, color: Color(0xFF9E1B22)),
              ),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '$totalMembers participant${totalMembers > 1 ? 's' : ''} (dont vous)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (_currentUser != null)
                  Chip(
                    label: Text(_currentUser!['full_name'] ?? _currentUser!['username'] ?? 'Vous'),
                    avatar: CircleAvatar(
                      backgroundColor: const Color(0xFF9E1B22),
                      child: Text(
                        (_currentUser!['full_name'] ?? 'V')[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                    backgroundColor: Colors.grey[100],
                  ),
                ...widget.selectedUsers.map(
                  (u) => Chip(
                    label: Text(u['full_name'] ?? u['username'] ?? ''),
                    avatar: CircleAvatar(
                      backgroundColor: const Color(0xFF9E1B22),
                      child: Text(
                        (u['full_name'] ?? '?')[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                    backgroundColor: Colors.grey[100],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _creating ? null : _createGroup,
                icon: _creating
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check),
                label: Text(_creating ? 'Création en cours...' : 'Créer le groupe'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF9E1B22),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}