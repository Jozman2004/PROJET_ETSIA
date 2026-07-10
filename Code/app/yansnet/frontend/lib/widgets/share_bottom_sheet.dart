// lib/widgets/share_bottom_sheet.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/post.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/constants.dart';

class ShareBottomSheet extends StatefulWidget {
  final Post post;
  final Function(List<String> userIds, String? comment) onShare;
  final Function(List<String> groupIds, String? comment)? onShareToGroup;

  const ShareBottomSheet({
    super.key,
    required this.post,
    required this.onShare,
    this.onShareToGroup,
  });

  @override
  State<ShareBottomSheet> createState() => _ShareBottomSheetState();
}

class _ShareBottomSheetState extends State<ShareBottomSheet> {
  final ApiService _api = ApiService();
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _commentCtrl = TextEditingController();

  List<User> _users = [];
  List<User> _filteredUsers = [];
  final Set<String> _selectedUserIds = {};

  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _filteredGroups = [];
  final Set<String> _selectedGroupIds = {};

  bool _loading = true;
  bool _sending = false;
  String _error = '';
  int _activeTab = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchCtrl.addListener(_filterData);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final me = context.read<AuthProvider>().user?.id ?? '';

      // Charger les utilisateurs
      final followers = await _api.getFollowers(me);
      final following = await _api.getFollowing(me);
      final userMap = <String, User>{};
      for (var j in followers) {
        try { final u = User.fromJson(j); userMap[u.id] = u; } catch (_) {}
      }
      for (var j in following) {
        try { final u = User.fromJson(j); userMap[u.id] = u; } catch (_) {}
      }
      var users = userMap.values.toList();
      if (users.isEmpty) {
        final all = await _api.getAllMembers();
        users = all.map((j) => User.fromJson(j)).toList();
      }

      // Charger les groupes (uniquement ceux où l'utilisateur est membre)
      final groupsData = await _api.getMyGroups();

      setState(() {
        _users = users;
        _filteredUsers = users;
        _groups = List<Map<String, dynamic>>.from(groupsData);
        _filteredGroups = List<Map<String, dynamic>>.from(groupsData);
        _loading = false;
      });
    } catch (e) {
      print('❌ Erreur chargement: $e');
      setState(() {
        _error = 'Impossible de charger les contacts et groupes';
        _loading = false;
      });
    }
  }

  void _filterData() {
    final q = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      if (_activeTab == 0) {
        _filteredUsers = q.isEmpty
            ? _users
            : _users.where((u) =>
                u.fullName.toLowerCase().contains(q) ||
                u.username.toLowerCase().contains(q)).toList();
      } else {
        _filteredGroups = q.isEmpty
            ? _groups
            : _groups.where((g) =>
                (g['name'] ?? '').toLowerCase().contains(q)).toList();
      }
    });
  }

  void _toggleUserSelection(User user) {
    setState(() {
      if (_selectedUserIds.contains(user.id)) {
        _selectedUserIds.remove(user.id);
      } else {
        _selectedUserIds.add(user.id);
      }
    });
  }

  void _toggleGroupSelection(Map<String, dynamic> group) {
    final id = group['id'].toString();
    setState(() {
      if (_selectedGroupIds.contains(id)) {
        _selectedGroupIds.remove(id);
      } else {
        _selectedGroupIds.add(id);
      }
    });
  }

  void _submit() {
    final comment = _commentCtrl.text.trim().isEmpty ? null : _commentCtrl.text.trim();

    if (_activeTab == 0) {
      if (_selectedUserIds.isEmpty) {
        _showError('Sélectionnez au moins une personne');
        return;
      }
      setState(() => _sending = true);
      widget.onShare(_selectedUserIds.toList(), comment);
    } else {
      if (_selectedGroupIds.isEmpty) {
        _showError('Sélectionnez au moins un groupe');
        return;
      }
      if (widget.onShareToGroup == null) {
        _showError('Le partage vers les groupes n\'est pas disponible');
        return;
      }
      setState(() => _sending = true);
      // ✅ Appel du callback avec les IDs des groupes
      widget.onShareToGroup!(_selectedGroupIds.toList(), comment);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  int get _totalSelected => _activeTab == 0 ? _selectedUserIds.length : _selectedGroupIds.length;
  String get _selectedLabel => _activeTab == 0 ? 'personne' : 'groupe';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Partager cette publication',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildPostPreview(),
          const SizedBox(height: 12),
          _buildCommentField(),
          const SizedBox(height: 12),
          _buildTabSelector(),
          const SizedBox(height: 12),
          _buildSearchField(),
          const SizedBox(height: 8),
          Expanded(child: _buildList()),
          const SizedBox(height: 8),
          _buildSendButton(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildPostPreview() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.post.fullName,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.post.content ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
          ),
          if (widget.post.mediaUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                '${AppConstants.baseUrl}${widget.post.mediaUrl}',
                width: 60,
                height: 60,
                fit: BoxFit.cover,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCommentField() {
    return TextField(
      controller: _commentCtrl,
      decoration: InputDecoration(
        hintText: 'Ajouter un commentaire (optionnel)',
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _buildTabSelector() {
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment<int>(value: 0, label: Text('👤 Personnes')),
        ButtonSegment<int>(value: 1, label: Text('👥 Groupes')),
      ],
      selected: {_activeTab},
      onSelectionChanged: (Set<int> newSelection) {
        setState(() {
          _activeTab = newSelection.first;
          _filterData();
        });
      },
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(0xFF9E1B22);
          }
          return Colors.grey[200];
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return Colors.black87;
        }),
        side: WidgetStateProperty.all(BorderSide.none),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        ),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchCtrl,
      decoration: InputDecoration(
        hintText: 'Rechercher...',
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) return Center(child: Text(_error, style: const TextStyle(color: Colors.red)));

    if (_activeTab == 0) {
      if (_filteredUsers.isEmpty) return const Center(child: Text('Aucun contact trouvé'));
      return ListView.builder(
        shrinkWrap: true,
        itemCount: _filteredUsers.length,
        itemBuilder: (_, i) {
          final u = _filteredUsers[i];
          final sel = _selectedUserIds.contains(u.id);
          return ListTile(
            leading: CircleAvatar(
              backgroundImage: u.avatarUrl != null
                  ? NetworkImage('${AppConstants.baseUrl}${u.avatarUrl}')
                  : null,
              child: u.avatarUrl == null
                  ? Text(u.fullName[0].toUpperCase())
                  : null,
            ),
            title: Text(u.fullName),
            subtitle: Text('@${u.username}'),
            trailing: Checkbox(
              value: sel,
              onChanged: (_) => _toggleUserSelection(u),
              activeColor: const Color(0xFF9E1B22),
            ),
            onTap: () => _toggleUserSelection(u),
          );
        },
      );
    } else {
      if (_filteredGroups.isEmpty) {
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.group_outlined, size: 48, color: Colors.grey),
              SizedBox(height: 12),
              Text('Vous n\'êtes dans aucun groupe', style: TextStyle(color: Colors.grey)),
              SizedBox(height: 4),
              Text('Créez ou rejoignez un groupe', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        );
      }
      return ListView.builder(
        shrinkWrap: true,
        itemCount: _filteredGroups.length,
        itemBuilder: (_, i) {
          final g = _filteredGroups[i];
          final id = g['id'].toString();
          final name = g['name'] ?? 'Groupe';
          int memberCount = 0;
          final raw = g['member_count'];
          if (raw is int) memberCount = raw;
          else if (raw is String) memberCount = int.tryParse(raw) ?? 0;

          final sel = _selectedGroupIds.contains(id);
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF9E1B22).withOpacity(0.15),
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : 'G',
                style: const TextStyle(color: Color(0xFF9E1B22), fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(name),
            subtitle: Text('$memberCount membre${memberCount > 1 ? 's' : ''}'),
            trailing: Checkbox(
              value: sel,
              onChanged: (_) => _toggleGroupSelection(g),
              activeColor: const Color(0xFF9E1B22),
            ),
            onTap: () => _toggleGroupSelection(g),
          );
        },
      );
    }
  }

  Widget _buildSendButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _sending ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF9E1B22),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        ),
        child: _sending
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Envoyer à ${_totalSelected} $_selectedLabel${_totalSelected > 1 ? 's' : ''}'),
                  const SizedBox(width: 8),
                  const Icon(Icons.send_rounded, size: 18),
                ],
              ),
      ),
    );
  }
}