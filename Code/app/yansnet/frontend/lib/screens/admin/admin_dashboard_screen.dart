// lib/screens/admin/admin_dashboard_screen.dart
import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> with SingleTickerProviderStateMixin {
  final _api = ApiService();
  late TabController _tabs;
  Map<String, dynamic>? _stats;
  List<dynamic> _users = [];
  List<dynamic> _reports = [];
  List<dynamic> _groups = [];
  bool _loadingStats = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadStats(), _loadUsers(), _loadReports(), _loadGroups()]);
  }

  Future<void> _loadStats() async {
    try {
      final data = await _api.getAdminStats();
      setState(() { _stats = data; _loadingStats = false; });
    } catch (_) { setState(() => _loadingStats = false); }
  }

  Future<void> _loadUsers({String search = ''}) async {
    try {
      final data = await _api.getAdminUsers(search: search);
      setState(() => _users = data);
    } catch (_) {}
  }

  Future<void> _loadReports() async {
    try {
      final data = await _api.getReports();
      setState(() => _reports = data);
    } catch (_) {}
  }

  Future<void> _loadGroups() async {
    try {
      final data = await _api.getAdminGroups();
      setState(() => _groups = data);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: const Color(0xFF9E1B22),
        foregroundColor: Colors.white,
        title: const Text('Administration', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_outlined, size: 18), text: 'Stats'),
            Tab(icon: Icon(Icons.people_outlined, size: 18), text: 'Utilisateurs'),
            Tab(icon: Icon(Icons.flag_outlined, size: 18), text: 'Signalements'),
            Tab(icon: Icon(Icons.group_outlined, size: 18), text: 'Groupes'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_buildStats(), _buildUsers(), _buildReports(), _buildGroups()],
      ),
    );
  }

  // ─── ONGLET STATS ────────────────────────────────────────
  Widget _buildStats() {
    if (_loadingStats) return const Center(child: CircularProgressIndicator(color: Color(0xFF9E1B22)));
    if (_stats == null) return const Center(child: Text('Erreur chargement stats'));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _statCard('Utilisateurs', _stats!['users']['total'], _stats!['users']['active'], 'actifs', Icons.people, const Color(0xFF9E1B22)),
          _statCard('Publications', _stats!['posts']['total'], _stats!['posts']['visible'], 'visibles', Icons.article, const Color(0xFF006838)),
          _statCard('Messages', _stats!['messages']['total'], null, null, Icons.chat, Colors.blue),
          _statCard('Signalements', _stats!['reports']['total'], _stats!['reports']['pending'], 'en attente', Icons.flag, Colors.orange),
          _statCard('Groupes', _stats!['groups']['total'], null, null, Icons.group, Colors.purple),
        ],
      ),
    );
  }

  Widget _statCard(String title, dynamic total, dynamic sub, String? subLabel, IconData icon, Color color) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 16),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(color: Colors.grey, fontSize: 13)),
              Text('$total', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
              if (sub != null) Text('$sub $subLabel', style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
            ]),
          ],
        ),
      ),
    );
  }

  // ─── ONGLET UTILISATEURS ─────────────────────────────────
  Widget _buildUsers() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Rechercher un utilisateur...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchCtrl.clear(); _loadUsers(); }),
            ),
            onSubmitted: (v) => _loadUsers(search: v),
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: _users.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final u = _users[i];
              final isActive = u['is_active'] ?? true;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF9E1B22).withOpacity(0.1),
                  child: Text((u['full_name'] ?? '?')[0].toUpperCase(), style: const TextStyle(color: Color(0xFF9E1B22), fontWeight: FontWeight.bold)),
                ),
                title: Text(u['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: Text('@${u['username']} · ${u['email']}', style: const TextStyle(fontSize: 12)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Badge rôle
                    GestureDetector(
                      onTap: () => _showRoleDialog(u['id'], u['role']),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFF9E1B22).withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                        child: Text(u['role'] ?? 'student', style: const TextStyle(fontSize: 11, color: Color(0xFF9E1B22), fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Toggle actif
                    GestureDetector(
                      onTap: () async {
                        final res = await _api.toggleUserActive(u['id']);
                        setState(() => _users[i]['is_active'] = res['is_active']);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message']), backgroundColor: Colors.green));
                      },
                      child: Icon(isActive ? Icons.check_circle : Icons.cancel, color: isActive ? Colors.green : Colors.red, size: 22),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showRoleDialog(String userId, String currentRole) {
    const roles = ['student', 'moderator', 'admin', 'alumni', 'concierge'];
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Changer le rôle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: roles.map((r) => RadioListTile<String>(
            value: r, groupValue: currentRole,
            title: Text(r, style: const TextStyle(fontSize: 14)),
            activeColor: const Color(0xFF9E1B22),
            onChanged: (v) async {
              Navigator.pop(context);
              await _api.changeUserRole(userId, v!);
              await _loadUsers(search: _searchCtrl.text);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Rôle changé: $v'), backgroundColor: Colors.green));
            },
          )).toList(),
        ),
      ),
    );
  }

  // ─── ONGLET SIGNALEMENTS ─────────────────────────────────
  Widget _buildReports() {
    return _reports.isEmpty
        ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.flag_outlined, size: 56, color: Colors.grey),
            SizedBox(height: 12),
            Text('Aucun signalement en attente', style: TextStyle(color: Colors.grey)),
          ]))
        : ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _reports.length,
            itemBuilder: (_, i) {
              final r = _reports[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.flag, color: Colors.orange, size: 16),
                          const SizedBox(width: 6),
                          Text('Signalé par @${r['reporter_username'] ?? '?'}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                            child: Text(r['status'] ?? 'pending', style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Raison : ${r['reason'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      if (r['post_content'] != null) ...[
                        const SizedBox(height: 6),
                        Text('Post : ${r['post_content']}', style: const TextStyle(fontSize: 13, color: Colors.grey), maxLines: 2, overflow: TextOverflow.ellipsis),
                        Text('Auteur : @${r['post_author_username'] ?? '?'}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: OutlinedButton(
                            onPressed: () => _resolveReport(r['id'], 'dismiss', 'dismissed', i),
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.grey, side: const BorderSide(color: Colors.grey)),
                            child: const Text('Ignorer', style: TextStyle(fontSize: 12)),
                          )),
                          const SizedBox(width: 8),
                          Expanded(child: OutlinedButton(
                            onPressed: () => _resolveReport(r['id'], 'warn_user', 'resolved', i),
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.orange, side: const BorderSide(color: Colors.orange)),
                            child: const Text('Avertir', style: TextStyle(fontSize: 12)),
                          )),
                          const SizedBox(width: 8),
                          Expanded(child: ElevatedButton(
                            onPressed: () => _resolveReport(r['id'], 'delete_post', 'resolved', i),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF9E1B22), foregroundColor: Colors.white),
                            child: const Text('Supprimer', style: TextStyle(fontSize: 12)),
                          )),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
  }

  Future<void> _resolveReport(String id, String action, String status, int index) async {
    try {
      await _api.resolveReport(id, action, status);
      setState(() => _reports.removeAt(index));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Signalement traité'), backgroundColor: Colors.green));
    } catch (_) {}
  }

  // ─── ONGLET GROUPES ──────────────────────────────────────
  Widget _buildGroups() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: ElevatedButton.icon(
            onPressed: _showCreateGroupDialog,
            icon: const Icon(Icons.add),
            label: const Text('Créer un groupe'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF9E1B22),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 46),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: _groups.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final g = _groups[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF006838).withOpacity(0.1),
                  child: Text(_typeEmoji(g['type'] ?? 'custom'), style: const TextStyle(fontSize: 20)),
                ),
                title: Text(g['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${g['type']} · ${g['member_count'] ?? 0} membres', style: const TextStyle(fontSize: 12)),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showCreateGroupDialog() {
    final nameCtrl = TextEditingController();
    String selectedType = 'promotion';
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Créer un groupe'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nom du groupe')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedType,
                items: ['promotion', 'residence', 'filiere', 'custom'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setS(() => selectedType = v!),
                decoration: const InputDecoration(labelText: 'Type'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF9E1B22), foregroundColor: Colors.white),
              onPressed: () async {
                if (nameCtrl.text.isEmpty) return;
                Navigator.pop(context);
                await _api.createGroup(nameCtrl.text.trim(), selectedType);
                await _loadGroups();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Groupe créé ✓'), backgroundColor: Colors.green));
              },
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );
  }

  String _typeEmoji(String type) {
    const map = {'promotion': '🎓', 'residence': '🏠', 'filiere': '📚', 'custom': '💬'};
    return map[type] ?? '💬';
  }
}