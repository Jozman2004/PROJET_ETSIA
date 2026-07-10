import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../models/user.dart';
import '../../utils/constants.dart';
import 'profile_screen.dart';

class FollowersListScreen extends StatefulWidget {
  final String userId;
  final String title;
  final String type; // 'followers' ou 'following'

  const FollowersListScreen({
    super.key,
    required this.userId,
    required this.title,
    required this.type,
  });

  @override
  State<FollowersListScreen> createState() => _FollowersListScreenState();
}

class _FollowersListScreenState extends State<FollowersListScreen> {
  final _api = ApiService();
  List<User> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _loading = true);
    try {
      final data = widget.type == 'followers'
          ? await _api.getFollowers(widget.userId)
          : await _api.getFollowing(widget.userId);
      
      setState(() {
        _users = data.map((j) => User.fromJson(j)).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: const Color(0xFF9E1B22),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF9E1B22)))
          : _users.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        'Aucun ${widget.type == 'followers' ? 'abonné' : 'abonnement'}',
                        style: const TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _users.length,
                  itemBuilder: (_, i) => _buildUserTile(_users[i]),
                ),
    );
  }

  Widget _buildUserTile(User user) {
    final avatarUrl = user.avatarUrl != null ? '${AppConstants.baseUrl}${user.avatarUrl}' : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
          backgroundColor: const Color(0xFFF39200),
          child: avatarUrl == null
              ? Text(user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?')
              : null,
        ),
        title: Text(user.fullName, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('@${user.username}'),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ProfileScreen(userId: user.id)),
          );
        },
      ),
    );
  }
}