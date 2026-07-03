import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/api_service.dart';
import '../../models/group_detail.dart';

// ========== ÉCRAN DE SÉLECTION DES PARTICIPANTS ==========
class UserPickerScreen extends StatefulWidget {
  final Set<String> excludeIds;
  const UserPickerScreen({super.key, required this.excludeIds});

  @override
  State<UserPickerScreen> createState() => _UserPickerScreenState();
}

class _UserPickerScreenState extends State<UserPickerScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _searchCtrl = TextEditingController();
  List<UserSearchResult> _users = [];
  List<UserSearchResult> _filteredUsers = [];
  final Set<String> _selectedIds = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _searchCtrl.addListener(_filterUsers);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_filterUsers);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    try {
      final allUsers = await _api.getAllMembers();
      final users = allUsers
          .map((json) => UserSearchResult.fromJson(json))
          .where((u) => !widget.excludeIds.contains(u.id))
          .toList();
      setState(() {
        _users = users;
        _filteredUsers = users;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _filterUsers() {
    final query = _searchCtrl.text.toLowerCase().trim();
    if (query.isEmpty) {
      setState(() => _filteredUsers = _users);
    } else {
      setState(() {
        _filteredUsers = _users.where((u) {
          return u.displayName.toLowerCase().contains(query) ||
              u.username.toLowerCase().contains(query);
        }).toList();
      });
    }
  }

  void _toggleSelection(UserSearchResult user) {
    setState(() {
      if (_selectedIds.contains(user.id)) {
        _selectedIds.remove(user.id);
      } else {
        _selectedIds.add(user.id);
      }
    });
  }

  void _confirmSelection() {
    final selected = _users.where((u) => _selectedIds.contains(u.id)).toList();
    Navigator.pop(context, selected);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF9E1B22),
        foregroundColor: Colors.white,
        title: const Text('Ajouter des membres'),
        actions: [
          if (_selectedIds.isNotEmpty)
            TextButton(
              onPressed: _confirmSelection,
              child: Text(
                'Ajouter (${_selectedIds.length})',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Rechercher un membre...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[100],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF9E1B22)))
                : _filteredUsers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              _searchCtrl.text.isEmpty
                                  ? 'Aucun membre disponible'
                                  : 'Aucun résultat',
                              style: TextStyle(color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredUsers.length,
                        itemBuilder: (_, index) {
                          final user = _filteredUsers[index];
                          final isSelected = _selectedIds.contains(user.id);
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFF9E1B22).withOpacity(0.1),
                              child: Text(
                                user.displayName[0].toUpperCase(),
                                style: const TextStyle(color: Color(0xFF9E1B22)),
                              ),
                            ),
                            title: Text(
                              user.displayName,
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            subtitle: Text('@${user.username}'),
                            trailing: Checkbox(
                              value: isSelected,
                              onChanged: (_) => _toggleSelection(user),
                              activeColor: const Color(0xFF9E1B22),
                            ),
                            onTap: () => _toggleSelection(user),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ========== ÉCRAN DE SAISIE DU NOM ET DE LA DESCRIPTION ==========
class GroupNameSetupScreen extends StatefulWidget {
  final List<Map<String, dynamic>> selectedUsers;
  const GroupNameSetupScreen({super.key, required this.selectedUsers});

  @override
  State<GroupNameSetupScreen> createState() => _GroupNameSetupScreenState();
}

class _GroupNameSetupScreenState extends State<GroupNameSetupScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
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
    final description = _descCtrl.text.trim();
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

      final res = await _api.createGroup(
        name,
        memberIds,
        description: description.isNotEmpty ? description : null,
      );

      if (!mounted) return;

      final groupId = res['id']?.toString() ?? res['groupId']?.toString() ?? '';
      final groupName = res['name']?.toString() ?? name;

      if (groupId.isEmpty) {
        throw Exception('Le serveur n\'a pas retourné d\'ID de groupe.');
      }

      await Future.delayed(const Duration(milliseconds: 300));

      if (mounted) {
        Navigator.pop(context, {'groupId': groupId, 'groupName': groupName});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: ${e.toString()}'), backgroundColor: Colors.red),
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