import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/group_detail.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/socket_service.dart';
import 'create_group_screen.dart';

class GroupInfoScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  const GroupInfoScreen({super.key, required this.groupId, required this.groupName});

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  final ApiService _api = ApiService();
  final SocketService _socket = SocketService();
  GroupDetail? _detail;
  bool _loading = true;
  String _meId = '';

  @override
  void initState() {
    super.initState();
    _meId = context.read<AuthProvider>().user?.id ?? '';
    _loadDetail();

    _socket.onGroupUpdated((data) {
      if (data['group_id']?.toString() != widget.groupId) return;
      if (!mounted) return;
      if (data['name'] != null) _loadDetail();
    });
  }

  @override
  void dispose() {
    _socket.removeListener('group_updated');
    super.dispose();
  }

  Future<void> _loadDetail() async {
    try {
      final data = await _api.getGroupDetail(widget.groupId);
      debugPrint('GroupDetail reçu: $data');
      setState(() {
        _detail = GroupDetail.fromJson(data);
        _loading = false;
      });
    } catch (e) {
      debugPrint('Erreur chargement groupe: $e');
      setState(() => _loading = false);
      _showSnack('Impossible de charger les infos du groupe', error: true);
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} à ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _showRenameDialog() {
    final ctrl = TextEditingController(text: _detail?.name ?? widget.groupName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renommer le groupe'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nouveau nom', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF9E1B22), foregroundColor: Colors.white),
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await _api.updateGroup(widget.groupId, name);
                _showSnack('Groupe renommé');
                _loadDetail();
              } catch (e) {
                _showSnack('Erreur: $e', error: true);
              }
            },
            child: const Text('Renommer'),
          ),
        ],
      ),
    );
  }

  Future<void> _addMembers() async {
    final existingIds = _detail?.members.map((m) => m.id).toSet() ?? {};
    final selected = await Navigator.push<List<UserSearchResult>>(
      context,
      MaterialPageRoute(builder: (_) => UserPickerScreen(excludeIds: existingIds)),
    );
    if (selected == null || selected.isEmpty) return;
    try {
      await _api.addGroupMembers(widget.groupId, selected.map((u) => u.id).toList());
      _showSnack('${selected.length} membre(s) ajouté(s)');
      _loadDetail();
    } catch (e) {
      _showSnack('Erreur: $e', error: true);
    }
  }

  void _showMemberOptions(GroupMember member) {
    if (member.id == _meId) return;
    final isAdmin = _detail?.isAdmin ?? false;
    if (!isAdmin) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.grey[100],
                child: Text(member.username[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              title: Text(member.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(member.role == 'admin' ? 'Administrateur' : 'Membre'),
            ),
            const Divider(),
            if (member.role != 'admin')
              ListTile(
                leading: const Icon(Icons.star, color: Colors.amber),
                title: const Text('Promouvoir administrateur'),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    await _api.promoteGroupMember(widget.groupId, member.id);
                    _showSnack('${member.username} est maintenant admin');
                    _loadDetail();
                  } catch (e) {
                    _showSnack('Erreur: $e', error: true);
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.remove_circle_outline, color: Colors.red),
              title: Text('Retirer ${member.username}'),
              onTap: () async {
                Navigator.pop(context);
                final ok = await _confirmDialog(
                  'Retirer ce membre ?',
                  '${member.username} sera retiré du groupe.',
                );
                if (!ok) return;
                try {
                  await _api.removeGroupMember(widget.groupId, member.id);
                  _showSnack('Membre retiré');
                  _loadDetail();
                } catch (e) {
                  _showSnack('Erreur: $e', error: true);
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _leaveGroup() async {
    final ok = await _confirmDialog('Quitter le groupe ?', 'Vous ne recevrez plus les messages de ce groupe.');
    if (!ok) return;
    try {
      await _api.removeGroupMember(widget.groupId, _meId);
      if (mounted) Navigator.popUntil(context, (route) => route.isFirst);
    } catch (e) {
      _showSnack('Erreur: $e', error: true);
    }
  }

  Future<void> _deleteGroup() async {
    final ok = await _confirmDialog(
      'Supprimer le groupe ?',
      'Cette action est irréversible. Tous les messages seront supprimés.',
      danger: true,
    );
    if (!ok) return;
    try {
      await _api.deleteGroup(widget.groupId);
      if (mounted) Navigator.popUntil(context, (route) => route.isFirst);
    } catch (e) {
      _showSnack('Erreur: $e', error: true);
    }
  }

  Future<bool> _confirmDialog(String title, String body, {bool danger = false}) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: danger ? Colors.red : const Color(0xFF9E1B22),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    ) ?? false;
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red : const Color(0xFF006838),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = _detail?.isAdmin ?? false;
    final members = _detail?.members ?? [];
    final isCreator = _detail?.createdBy == _meId;
    final description = _detail?.description;
    final createdAt = _detail?.createdAt;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF9E1B22),
        foregroundColor: Colors.white,
        title: const Text('Infos du groupe'),
        actions: [
          if (isAdmin)
            IconButton(icon: const Icon(Icons.edit), onPressed: _showRenameDialog),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF9E1B22)))
          : RefreshIndicator(
              color: const Color(0xFF9E1B22),
              onRefresh: _loadDetail,
              child: ListView(
                children: [
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 48,
                          backgroundColor: const Color(0xFF9E1B22),
                          child: Text(
                            _detail?.name.isNotEmpty == true ? _detail!.name[0].toUpperCase() : 'G',
                            style: const TextStyle(fontSize: 40, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _detail?.name ?? widget.groupName,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Groupe · ${members.length} membre${members.length > 1 ? 's' : ''}',
                          style: TextStyle(color: Colors.grey[500], fontSize: 13),
                        ),
                        // ---------- DESCRIPTION ----------
                        if (description != null && description.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 24),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              description,
                              style: const TextStyle(fontSize: 14, color: Colors.black87),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                        // ---------- DATE DE CRÉATION ----------
                        if (createdAt != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Créé le ${_formatDate(createdAt)}',
                            style: TextStyle(color: Colors.grey[500], fontSize: 12),
                          ),
                        ],
                        // ---------- CRÉATEUR ----------
                        if (_detail?.creatorUsername.isNotEmpty == true) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Créé par ${_detail!.creatorUsername}',
                            style: TextStyle(color: Colors.grey[400], fontSize: 11),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    color: Colors.white,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Row(
                            children: [
                              Text(
                                '${members.length} membre${members.length > 1 ? 's' : ''}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              const Spacer(),
                              if (isAdmin)
                                TextButton.icon(
                                  onPressed: _addMembers,
                                  icon: const Icon(Icons.person_add, size: 18, color: Color(0xFF9E1B22)),
                                  label: const Text('Ajouter', style: TextStyle(color: Color(0xFF9E1B22))),
                                ),
                            ],
                          ),
                        ),
                        if (members.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Center(child: Text('Aucun membre', style: TextStyle(color: Colors.grey[400]))),
                          )
                        else
                          ...members.map((m) => _buildMemberTile(m, isAdmin)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    color: Colors.white,
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.exit_to_app, color: Colors.orange),
                          title: const Text('Quitter le groupe', style: TextStyle(color: Colors.orange)),
                          onTap: _leaveGroup,
                        ),
                        if (isCreator) ...[
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.delete_forever, color: Colors.red),
                            title: const Text('Supprimer le groupe', style: TextStyle(color: Colors.red)),
                            onTap: _deleteGroup,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildMemberTile(GroupMember member, bool isAdmin) {
    final isMe = member.id == _meId;
    final isMemberAdmin = member.role == 'admin';

    return ListTile(
      onTap: isAdmin && !isMe ? () => _showMemberOptions(member) : null,
      leading: CircleAvatar(
        backgroundColor: isMemberAdmin ? const Color(0xFF9E1B22) : Colors.grey[300],
        child: Text(
          member.username[0].toUpperCase(),
          style: TextStyle(
            color: isMemberAdmin ? Colors.white : Colors.black54,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Row(
        children: [
          Text(member.displayName, style: const TextStyle(fontWeight: FontWeight.w500)),
          if (isMe) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
              child: const Text('Vous', style: TextStyle(fontSize: 10, color: Colors.grey)),
            ),
          ],
        ],
      ),
      subtitle: Text('@${member.username}', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
      trailing: isMemberAdmin
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF9E1B22).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('Admin', style: TextStyle(color: Color(0xFF9E1B22), fontSize: 11, fontWeight: FontWeight.bold)),
            )
          : isAdmin && !isMe
              ? const Icon(Icons.chevron_right, color: Colors.grey)
              : null,
    );
  }
}