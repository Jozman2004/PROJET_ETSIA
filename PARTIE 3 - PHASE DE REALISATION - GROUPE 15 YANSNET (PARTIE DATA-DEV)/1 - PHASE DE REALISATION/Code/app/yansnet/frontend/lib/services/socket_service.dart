// lib/services/socket_service.dart
import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../utils/constants.dart';
import 'api_service.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;
  bool get isConnected => _socket?.connected ?? false;

  // ── STREAMS (événements) ──────────────────────────────────────────────
  final _newMessageController = StreamController<Map<String, dynamic>>.broadcast();
  final _newGroupMessageController = StreamController<Map<String, dynamic>>.broadcast();
  final _newNotificationController = StreamController<Map<String, dynamic>>.broadcast();
  final _newMentionController = StreamController<Map<String, dynamic>>.broadcast();
  final _unreadMessagesController = StreamController<int>.broadcast();

  Stream<Map<String, dynamic>> get onNewMessageStream => _newMessageController.stream;
  Stream<Map<String, dynamic>> get onNewGroupMessageStream => _newGroupMessageController.stream;
  Stream<Map<String, dynamic>> get onNewNotificationStream => _newNotificationController.stream;
  Stream<Map<String, dynamic>> get onMentionStream => _newMentionController.stream;
  Stream<int> get onUnreadMessagesStream => _unreadMessagesController.stream;

  // ── MÉTHODES D'ÉCOUTE AVEC STREAMSUBSCRIPTION ────────────────────────
  StreamSubscription<Map<String, dynamic>> onNewMessage(void Function(Map<String, dynamic>) handler) {
    return _newMessageController.stream.listen(handler);
  }
  StreamSubscription<Map<String, dynamic>> onGroupMessage(void Function(Map<String, dynamic>) handler) {
    return _newGroupMessageController.stream.listen(handler);
  }
  StreamSubscription<Map<String, dynamic>> onNewNotification(void Function(Map<String, dynamic>) handler) {
    return _newNotificationController.stream.listen(handler);
  }
  StreamSubscription<Map<String, dynamic>> onMention(void Function(Map<String, dynamic>) handler) {
    return _newMentionController.stream.listen(handler);
  }

  // ── COMPTEURS ───────────────────────────────────────────────────────────
  int _unreadCount = 0;
  int get unreadCount => _unreadCount;

  int _unreadMessagesCount = 0;
  int get unreadMessagesCount => _unreadMessagesCount;

  // Listeners (callback lists)
  final List<void Function(int)> _unreadListeners = [];
  final List<void Function(int)> _unreadMessagesListeners = [];
  final List<void Function()> _reconnectListeners = [];

  // Notifications
  void addUnreadListener(void Function(int) listener) => _unreadListeners.add(listener);
  void removeUnreadListener(void Function(int) listener) => _unreadListeners.remove(listener);
  void _notifyUnreadListeners() { for (var l in _unreadListeners) l(_unreadCount); }
  void setUnreadCount(int count) { _unreadCount = count; _notifyUnreadListeners(); }
  void incrementUnreadCount() { _unreadCount++; _notifyUnreadListeners(); }
  void decrementUnreadCount() { if (_unreadCount > 0) { _unreadCount--; _notifyUnreadListeners(); } }

  // Messages
  void addUnreadMessagesListener(void Function(int) listener) => _unreadMessagesListeners.add(listener);
  void removeUnreadMessagesListener(void Function(int) listener) => _unreadMessagesListeners.remove(listener);
  void _notifyUnreadMessagesListeners() { for (var l in _unreadMessagesListeners) l(_unreadMessagesCount); }
  void setUnreadMessagesCount(int count) {
    _unreadMessagesCount = count;
    _notifyUnreadMessagesListeners();
    _unreadMessagesController.add(count);
  }
  void incrementUnreadMessagesCount() {
    _unreadMessagesCount++;
    _notifyUnreadMessagesListeners();
    _unreadMessagesController.add(_unreadMessagesCount);
  }
  void decrementUnreadMessagesCount() {
    if (_unreadMessagesCount > 0) {
      _unreadMessagesCount--;
      _notifyUnreadMessagesListeners();
      _unreadMessagesController.add(_unreadMessagesCount);
    }
  }

  // Reconnect
  void addReconnectListener(void Function() listener) => _reconnectListeners.add(listener);
  void removeReconnectListener(void Function() listener) => _reconnectListeners.remove(listener);
  void _notifyReconnectListeners() { for (var l in _reconnectListeners) l(); }

  // ── CONNEXION ───────────────────────────────────────────────────────────
  void connect(String userId) {
    if (isConnected) return;
    _socket = IO.io(AppConstants.socketUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'reconnection': true,
      'reconnectionDelay': 1000,
      'reconnectionDelayMax': 5000,
      'reconnectionAttempts': 50,
      'timeout': 20000,
    });

    _socket!.onConnect((_) {
      print('✅ Socket connecté (user: $userId)');
      _socket!.emit('register', userId);
      _loadUnreadCount();
      _setupSocketListeners();
    });

    _socket!.onReconnect((_) {
      print('🔄 Socket reconnecté, réinscription de l\'utilisateur $userId');
      _socket!.emit('register', userId);
      _loadUnreadCount();
      _notifyReconnectListeners();
    });

    _socket!.onConnectError((err) => print('⚠️ Socket connection error: $err'));
    _socket!.onDisconnect((_) => print('❌ Socket déconnecté'));
    _socket!.onError((err) => print('⚠️ Socket error: $err'));

    _socket!.on('ping', (_) {
      print('📥 Ping reçu, envoi pong');
      _socket!.emit('pong');
    });
  }

  void _setupSocketListeners() {
    // Messages privés
    _socket?.on('new_message', (data) {
      if (data is Map) {
        _newMessageController.add(Map<String, dynamic>.from(data));
        incrementUnreadMessagesCount();
      }
    });

    // Messages de groupe
    _socket?.on('group_message', (data) {
      if (data is Map) {
        _newGroupMessageController.add(Map<String, dynamic>.from(data));
        incrementUnreadMessagesCount();
      }
    });

    // Notifications globales
    _socket?.on('new_notification', (data) {
      if (data is Map) {
        final notification = Map<String, dynamic>.from(data);
        _newNotificationController.add(notification);
        incrementUnreadCount();

        final type = notification['type']?.toString().toLowerCase() ?? '';
        if (type == 'mention' || type == 'Mention') {
          _newMentionController.add(notification);
        }
      }
    });

    // Mise à jour du compteur de messages non lus
    _socket?.on('unread_messages_count', (data) {
      if (data is Map && data.containsKey('count')) {
        setUnreadMessagesCount(data['count'] as int);
      }
    });

    // Message lu
    _socket?.on('message_read', (data) {
      if (data != null && data is Map && data.containsKey('messageId')) {
        decrementUnreadMessagesCount();
      }
    });
  }

  Future<void> _loadUnreadCount() async {
    try {
      final api = ApiService();
      final data = await api.getUnreadCount();
      setUnreadCount(data['count'] ?? 0);
    } catch (e) {
      print('Erreur chargement compteur: $e');
    }
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.clearListeners();
    _socket = null;
    setUnreadCount(0);
    setUnreadMessagesCount(0);
  }

  // ── MESSAGES PRIVÉS ─────────────────────────────────────────────────────
  void sendPrivateMessage(String receiverId, String content, Function(Map<String, dynamic>) cb) {
    _socket?.emitWithAck(
      'private_message',
      {'receiverId': receiverId, 'content': content},
      ack: (data) {
        if (data != null && data is Map) {
          cb(Map<String, dynamic>.from(data));
        } else {
          cb({'error': 'Aucune réponse du serveur'});
        }
      },
    );
  }

  void markRead(String messageId) => _socket?.emit('mark_read', messageId);

  // ── GROUPES ─────────────────────────────────────────────────────────────
  void joinGroup(String groupId) {
    print('🔌 Socket: join_group $groupId');
    _socket?.emit('join_group', {'groupId': groupId});
  }

  void leaveGroup(String groupId) {
    _socket?.emit('leave_group', {'groupId': groupId});
  }

  void onGroupUpdated(Function(Map<String, dynamic>) callback) {
    _socket?.on('group_updated', (data) {
      if (data != null && data is Map) callback(Map<String, dynamic>.from(data));
    });
  }

  void onAddedToGroup(Function(Map<String, dynamic>) callback) {
    _socket?.on('added_to_group', (data) {
      if (data != null && data is Map) callback(Map<String, dynamic>.from(data));
    });
  }

  void onRemovedFromGroup(Function(Map<String, dynamic>) callback) {
    _socket?.on('removed_from_group', (data) {
      if (data != null && data is Map) callback(Map<String, dynamic>.from(data));
    });
  }

  void onGroupDeleted(Function(Map<String, dynamic>) callback) {
    _socket?.on('group_deleted', (data) {
      if (data != null && data is Map) callback(Map<String, dynamic>.from(data));
    });
  }

  void onMessagePinned(Function(Map<String, dynamic>) callback) {
    _socket?.on('message_pinned', (data) {
      if (data != null && data is Map) callback(Map<String, dynamic>.from(data));
    });
  }

  void onMessageUnpinned(Function(Map<String, dynamic>) callback) {
    _socket?.on('message_unpinned', (data) {
      if (data != null && data is Map) callback(Map<String, dynamic>.from(data));
    });
  }

  // ── ÉVÉNEMENTS DE SUPPRESSION ──────────────────────────────────────────
  void onMessageDeleted(Function(Map<String, dynamic>) callback) {
    _socket?.on('message_deleted', (data) {
      if (data != null && data is Map) callback(Map<String, dynamic>.from(data));
    });
  }

  void onGroupMessageDeleted(Function(Map<String, dynamic>) callback) {
    _socket?.on('group_message_deleted', (data) {
      if (data != null && data is Map) callback(Map<String, dynamic>.from(data));
    });
  }

  // ── ÉVÉNEMENTS DE MODIFICATION ET SUPPRESSION "POUR MOI" ──────────────
  /// Écoute la modification d'un message privé
  void onMessageEdited(Function(Map<String, dynamic>) callback) {
    _socket?.on('message_edited', (data) {
      if (data != null && data is Map) callback(Map<String, dynamic>.from(data));
    });
  }

  /// Écoute la suppression "pour moi" d'un message privé
  void onMessageDeletedForMe(Function(Map<String, dynamic>) callback) {
    _socket?.on('message_deleted_for_me', (data) {
      if (data != null && data is Map) callback(Map<String, dynamic>.from(data));
    });
  }

  /// Écoute la modification d'un message de groupe
  void onGroupMessageEdited(Function(Map<String, dynamic>) callback) {
    _socket?.on('group_message_edited', (data) {
      if (data != null && data is Map) callback(Map<String, dynamic>.from(data));
    });
  }

  /// Écoute la suppression "pour moi" d'un message de groupe
  void onGroupMessageDeletedForMe(Function(Map<String, dynamic>) callback) {
    _socket?.on('group_message_deleted_for_me', (data) {
      if (data != null && data is Map) callback(Map<String, dynamic>.from(data));
    });
  }

  // ── ALIAS ────────────────────────────────────────────────────────────────
  void onNewGroupMessage(Function(Map<String, dynamic>) cb) => onGroupMessage(cb);

  void onMessageRead(Function(dynamic) callback) {
    _socket?.on('message_read', (data) {
      if (data != null) callback(data);
    });
  }

  // ── NETTOYAGE ────────────────────────────────────────────────────────────
  void removeListener(String event) => _socket?.off(event);
  void clearAllListeners() => _socket?.clearListeners();

  void removeGroupListeners() {
    _socket?.off('group_message');
    _socket?.off('group_updated');
    _socket?.off('added_to_group');
    _socket?.off('removed_from_group');
    _socket?.off('group_deleted');
    _socket?.off('message_pinned');
    _socket?.off('message_unpinned');
    _socket?.off('message_deleted');
    _socket?.off('group_message_deleted');
    // Nettoyer les nouveaux événements
    _socket?.off('message_edited');
    _socket?.off('message_deleted_for_me');
    _socket?.off('group_message_edited');
    _socket?.off('group_message_deleted_for_me');
  }

  void dispose() {
    _newMessageController.close();
    _newGroupMessageController.close();
    _newNotificationController.close();
    _newMentionController.close();
    _unreadMessagesController.close();
    disconnect();
  }
}