import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';
import '../../models/post.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../utils/constants.dart';
import '../../widgets/post_card.dart';
import '../messages/dm_screen.dart';
import 'followers_list_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String? userId;
  const ProfileScreen({super.key, this.userId});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  final _api = ApiService();
  User? _profile;
  List<Post> _posts = [];
  bool _loading = true;
  bool _following = false;
  bool _followLoading = false;
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  String get _uid => widget.userId ?? context.read<AuthProvider>().user!.id;
  bool get _isMe => _uid == context.read<AuthProvider>().user?.id;

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _api.getProfile(_uid),
        _api.getUserPosts(_uid),
        if (!_isMe) _api.getFollowStatus(_uid),
      ]);
      
      final profileData = results[0] as Map<String, dynamic>;
      
      setState(() {
        _profile = User.fromJson(profileData);
        _posts = (results[1] as List).map((j) => Post.fromJson(j as Map<String, dynamic>)).toList();
        if (!_isMe && results.length > 2) {
          final followData = results[2] as Map<String, dynamic>;
          _following = followData['following'] ?? false;
        }
        _loading = false;
      });
    } catch (e) {
      print('❌ Erreur: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleFollow() async {
    setState(() => _followLoading = true);
    try {
      _following ? await _api.unfollowUser(_uid) : await _api.followUser(_uid);
      setState(() => _following = !_following);
      if (_profile != null) {
        setState(() {
          if (_following) {
            _profile!.followersCount = (_profile!.followersCount ?? 0) + 1;
          } else {
            _profile!.followersCount = (_profile!.followersCount ?? 1) - 1;
          }
        });
      }
    } catch (e) {
      print('❌ Erreur follow: $e');
    } finally {
      setState(() => _followLoading = false);
    }
  }

  void _showFollowersList() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FollowersListScreen(
          userId: _uid,
          title: 'Abonnés',
          type: 'followers',
        ),
      ),
    );
  }

  void _showFollowingList() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FollowersListScreen(
          userId: _uid,
          title: 'Abonnements',
          type: 'following',
        ),
      ),
    );
  }

  // ============================================================
  // CHANGER L'AVATAR - AVEC OPTION SUPPRIMER
  // ============================================================
  Future<void> _changeAvatar() async {
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
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFF9E1B22)),
              title: const Text('Choisir une photo'),
              onTap: () async {
                Navigator.pop(context);
                await _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF9E1B22)),
              title: const Text('Prendre une photo'),
              onTap: () async {
                Navigator.pop(context);
                await _pickImage(ImageSource.camera);
              },
            ),
            if (_profile!.avatarUrl != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Supprimer la photo', style: TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.pop(context);
                  await _deleteAvatar();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: source,
      imageQuality: 50,
      maxWidth: 300,
    );
    if (image == null) return;
    
    setState(() => _loading = true);
    
    try {
      final res = await _api.updateAvatar(image.path);
      setState(() {
        _profile!.avatarUrl = res['avatar_url'];
      });
      if (_isMe) {
        context.read<AuthProvider>().updateUser(_profile!);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo de profil mise à jour'), backgroundColor: Colors.green),
      );
    } catch (e) {
      print('❌ Erreur: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur, réessayez'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _deleteAvatar() async {
    setState(() => _loading = true);
    try {
      await _api.deleteAvatar();
      setState(() {
        _profile!.avatarUrl = null;
      });
      if (_isMe) {
        context.read<AuthProvider>().updateUser(_profile!);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo de profil supprimée'), backgroundColor: Colors.green),
      );
    } catch (e) {
      print('❌ Erreur: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur, réessayez'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showEditProfile() {
    final nameCtrl = TextEditingController(text: _profile?.fullName);
    final usernameCtrl = TextEditingController(text: _profile?.username);
    final bioCtrl = TextEditingController(text: _profile?.bio ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Modifier le profil', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _editField(nameCtrl, 'Nom complet'),
            const SizedBox(height: 12),
            _editField(usernameCtrl, "Nom d'utilisateur"),
            const SizedBox(height: 12),
            _editField(bioCtrl, 'Biographie', maxLines: 3),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF9E1B22),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  Navigator.pop(context);
                  try {
                    final updated = await _api.updateProfile({
                      if (nameCtrl.text.isNotEmpty) 'full_name': nameCtrl.text.trim(),
                      if (usernameCtrl.text.isNotEmpty) 'username': usernameCtrl.text.trim(),
                      'bio': bioCtrl.text.trim(),
                    });
                    setState(() => _profile = User.fromJson(updated));
                    if (_isMe) context.read<AuthProvider>().updateUser(User.fromJson(updated));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Profil mis à jour ✓'), backgroundColor: Colors.green),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erreur: ${e.toString()}'), backgroundColor: Colors.red),
                    );
                  }
                },
                child: const Text('Enregistrer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _editField(TextEditingController ctrl, String label, {int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF9E1B22), width: 2),
        ),
      ),
    );
  }

  String _roleLabel(String role) {
    const map = {'admin': 'Administrateur', 'moderator': 'Modérateur', 'alumni': 'Alumni', 'concierge': 'Concierge'};
    return map[role] ?? 'Étudiant';
  }

  @override
  Widget build(BuildContext context) {
    final me = context.read<AuthProvider>().user;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF9E1B22))));
    }
    if (_profile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profil')),
        body: const Center(child: Text('Profil introuvable')),
      );
    }

    final avatarUri = _profile!.avatarUrl != null ? '${AppConstants.baseUrl}${_profile!.avatarUrl}' : null;

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            expandedHeight: 420,
            pinned: true,
            backgroundColor: const Color(0xFF9E1B22),
            foregroundColor: Colors.white,
            actions: [
              if (_isMe) ...[
                IconButton(icon: const Icon(Icons.edit_outlined), onPressed: _showEditProfile),
                IconButton(icon: const Icon(Icons.logout), onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Déconnexion'),
                      content: const Text('Voulez-vous vous déconnecter ?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            context.read<AuthProvider>().logout();
                          },
                          child: const Text('Déconnecter', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF9E1B22), Color(0xFF6B1117)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 20),
                      // Avatar
                      GestureDetector(
                        onTap: _isMe ? _changeAvatar : null,
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 55,
                              backgroundColor: Colors.white24,
                              backgroundImage: avatarUri != null ? NetworkImage(avatarUri) : null,
                              child: avatarUri == null
                                  ? Text(
                                      _profile!.fullName.isNotEmpty ? _profile!.fullName[0].toUpperCase() : '?',
                                      style: const TextStyle(fontSize: 45, color: Colors.white, fontWeight: FontWeight.bold),
                                    )
                                  : null,
                            ),
                            if (_isMe)
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                  child: const Icon(Icons.camera_alt, size: 18, color: Color(0xFF9E1B22)),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Nom
                      Text(
                        _profile!.fullName,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      // Username
                      Text(
                        '@${_profile!.username}',
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 10),
                      // Badge rôle
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _roleLabel(_profile!.role),
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // STATS CLIQUABLES
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24, width: 0.5),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  Text(
                                    _posts.length.toString(),
                                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Publications',
                                    style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                            Container(width: 1, height: 45, color: Colors.white30),
                            Expanded(
                              child: GestureDetector(
                                onTap: _showFollowersList,
                                child: Column(
                                  children: [
                                    Text(
                                      _profile!.followersCount?.toString() ?? '0',
                                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Abonnés',
                                      style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Container(width: 1, height: 45, color: Colors.white30),
                            Expanded(
                              child: GestureDetector(
                                onTap: _showFollowingList,
                                child: Column(
                                  children: [
                                    Text(
                                      _profile!.followingCount?.toString() ?? '0',
                                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Abonnements',
                                      style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Container(
                color: Colors.white,
                child: TabBar(
                  controller: _tabs,
                  labelColor: const Color(0xFF9E1B22),
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: const Color(0xFF9E1B22),
                  tabs: const [Tab(text: 'Publications'), Tab(text: 'Infos')],
                ),
              ),
            ),
          ),
        ],
        body: Column(
          children: [
            if (!_isMe)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _followLoading ? null : _toggleFollow,
                        icon: _followLoading
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Icon(_following ? Icons.person_remove_outlined : Icons.person_add_outlined, size: 18),
                        label: Text(_following ? 'Abonné' : 'Suivre', style: const TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _following ? Colors.grey[200] : const Color(0xFF9E1B22),
                          foregroundColor: _following ? Colors.grey[700] : Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => DmScreen(receiverId: _profile!.id, receiverName: _profile!.fullName)),
                        ),
                        icon: const Icon(Icons.chat_bubble_outline, size: 18),
                        label: const Text('Message', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF9E1B22),
                          side: const BorderSide(color: Color(0xFF9E1B22)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _posts.isEmpty
                      ? const Center(child: Text('Aucune publication', style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          itemCount: _posts.length,
                          itemBuilder: (_, i) => PostCard(
                            post: _posts[i],
                            currentUserId: me?.id ?? '',
                            onDelete: () async {
                              await _api.deletePost(_posts[i].id);
                              setState(() => _posts.removeAt(i));
                            },
                            onProfileTap: (uid) => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => ProfileScreen(userId: uid)),
                            ),
                          ),
                        ),
                  ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      if (_profile!.bio?.isNotEmpty == true) ...[
                        _infoSection('Biographie', _profile!.bio!),
                        const SizedBox(height: 16),
                      ],
                      if (_profile!.filiere != null) _infoTile(Icons.book_outlined, 'Filière', _profile!.filiere!),
                      if (_profile!.promotion != null) _infoTile(Icons.school_outlined, 'Promotion', _profile!.promotion!),
                      if (_profile!.residence != null) _infoTile(Icons.home_outlined, 'Résidence', _profile!.residence!),
                      if (_isMe) _infoTile(Icons.email_outlined, 'Email', me!.email),
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

  Widget _infoSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(content, style: const TextStyle(fontSize: 15, height: 1.5)),
      ],
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFF9E1B22).withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: const Color(0xFF9E1B22), size: 18),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}