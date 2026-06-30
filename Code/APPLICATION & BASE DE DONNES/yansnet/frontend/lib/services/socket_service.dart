// lib/services/socket_service.dart
// ✅ FIX : événements socket alignés avec le backend Node.js
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../utils/constants.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;
  bool get isConnected => _socket?.connected ?? false;

  void connect(String userId) {
    if (isConnected) return;
    _socket = IO.io(AppConstants.socketUrl, <String, dynamic>{
      'transports':          ['websocket'],
      'autoConnect':         true,
      'reconnection':        true,
      'reconnectionDelay':   1000,
      'reconnectionAttempts': 10,
    });

    _socket!.onConnect((_) {
      print('✅ Socket connecté (user: $userId)');
      _socket!.emit('register', userId);
    });
    _socket!.onConnectError((err) => print('⚠️ Socket connection error: $err'));
    _socket!.onDisconnect((_)    => print('❌ Socket déconnecté'));
    _socket!.onError((err)       => print('⚠️ Socket error: $err'));
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.clearListeners();
    _socket = null;
  }

  // ── Messages privés ───────────────────────────────────────────────────────

  void sendPrivateMessage(
    String receiverId,
    String content,
    Function(Map<String, dynamic>) cb,
  ) {
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

  void onNewMessage(Function(Map<String, dynamic>) cb) {
    _socket?.on('new_message', (data) {
      if (data != null && data is Map) cb(Map<String, dynamic>.from(data));
    });
  }

  void onMessageRead(Function(String) cb) {
    _socket?.on('message_read', (data) {
      if (data != null && data is Map && data.containsKey('messageId')) {
        cb(data['messageId'].toString());
      }
    });
  }

  void onNewNotification(Function(Map<String, dynamic>) cb) {
    _socket?.on('new_notification', (data) {
      if (data != null && data is Map) cb(Map<String, dynamic>.from(data));
    });
  }

  void markRead(String messageId) => _socket?.emit('mark_read', messageId);

  void removeListener(String event)  => _socket?.off(event);
  void clearAllListeners()           => _socket?.clearListeners();

  // ── Groupes ───────────────────────────────────────────────────────────────

  /// Rejoindre la room socket du groupe
  void joinGroup(String groupId) {
    print('🔌 Socket: join_group $groupId');
    _socket?.emit('join_group', {'groupId': groupId});
  }

  /// Quitter la room socket du groupe
  void leaveGroup(String groupId) {
    _socket?.emit('leave_group', {'groupId': groupId});
  }

  // ✅ FIX CRITIQUE : le backend émet 'group_message' (pas 'new_group_message')
  // Vérifiez votre serveur socket — la room s'appelle `group_${groupId}`
  // et l'événement émis est bien 'group_message'.
  void onGroupMessage(Function(Map<String, dynamic>) callback) {
    _socket?.on('group_message', (data) {
      if (data != null && data is Map) callback(Map<String, dynamic>.from(data));
    });
  }

  // Alias conservé pour compatibilité si certains écrans utilisent l'ancien nom
  void onNewGroupMessage(Function(Map<String, dynamic>) cb) => onGroupMessage(cb);

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

  void removeGroupListeners() {
    _socket?.off('group_message');
    _socket?.off('group_updated');
    _socket?.off('added_to_group');
    _socket?.off('removed_from_group');
    _socket?.off('group_deleted');
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
}