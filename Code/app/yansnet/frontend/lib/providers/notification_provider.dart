// lib/providers/notification_provider.dart
import 'package:flutter/material.dart';
import '../models/notification_model.dart';

class NotificationProvider extends ChangeNotifier {
  List<AppNotification> _notifications = [];
  List<AppNotification> get notifications => _notifications;

  void addNotification(AppNotification notification) {
    _notifications.insert(0, notification);
    notifyListeners();
  }

  /// Marque toutes les notifications comme lues (immutable)
  void markAllAsRead() {
    _notifications = _notifications.map((n) => AppNotification(
      id: n.id,
      type: n.type,
      content: n.content,
      isRead: true,
      referenceId: n.referenceId,
      createdAt: n.createdAt,
    )).toList();
    notifyListeners();
  }

  /// Marque une notification spécifique comme lue
  void markAsRead(String id) {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index != -1) {
      final old = _notifications[index];
      _notifications[index] = AppNotification(
        id: old.id,
        type: old.type,
        content: old.content,
        isRead: true,
        referenceId: old.referenceId,
        createdAt: old.createdAt,
      );
      notifyListeners();
    }
  }

  void clearAll() {
    _notifications.clear();
    notifyListeners();
  }

  int get unreadCount => _notifications.where((n) => !n.isRead).length;
}