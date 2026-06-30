// lib/screens/notifications/notifications_screen.dart
import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../models/notification_model.dart';
import '../../services/api_service.dart';
import '../../services/socket_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final ApiService _api = ApiService();
  final SocketService _socket = SocketService();
  List<AppNotification> _notifs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _socket.onNewNotification((data) {
      if (!mounted) return;
      setState(() {
        _notifs.insert(0, AppNotification.fromJson(data));
      });
    });
  }

  @override
  void dispose() {
    _socket.removeListener('new_notification');
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await _api.getNotifications();
      setState(() {
        _notifs = data.map((json) => AppNotification.fromJson(json)).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _markAllRead() async {
    await _api.markAllNotifsRead();
    setState(() {
      _notifs = _notifs.map((n) => AppNotification(
        id: n.id,
        type: n.type,
        content: n.content,
        isRead: true,
        referenceId: n.referenceId,
        createdAt: n.createdAt,
      )).toList();
    });
  }

  Future<void> _markRead(AppNotification n) async {
    if (n.isRead) return;
    await _api.markNotifRead(n.id);
    setState(() {
      final index = _notifs.indexWhere((x) => x.id == n.id);
      if (index != -1) {
        _notifs[index] = AppNotification(
          id: n.id,
          type: n.type,
          content: n.content,
          isRead: true,
          referenceId: n.referenceId,
          createdAt: n.createdAt,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifs.where((n) => !n.isRead).length;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF9E1B22),
        foregroundColor: Colors.white,
        title: Row(
          children: [
            const Text('Notifications', style: TextStyle(fontWeight: FontWeight.bold)),
            if (unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$unreadCount',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (unreadCount > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text(
                'Tout lire',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF9E1B22)),
            )
          : RefreshIndicator(
              color: const Color(0xFF9E1B22),
              onRefresh: _load,
              child: _notifs.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'Aucune notification',
                            style: TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: _notifs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final notification = _notifs[index];
                        return InkWell(
                          onTap: () => _markRead(notification),
                          child: Container(
                            color: notification.isRead
                                ? Colors.transparent
                                : const Color(0xFF9E1B22).withOpacity(0.04),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              leading: Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF9E1B22).withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    notification.icon,
                                    style: const TextStyle(fontSize: 20),
                                  ),
                                ),
                              ),
                              title: Text(
                                notification.content,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: notification.isRead
                                      ? FontWeight.normal
                                      : FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                timeago.format(notification.createdAt, locale: 'fr'),
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              trailing: notification.isRead
                                  ? null
                                  : Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF9E1B22),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}