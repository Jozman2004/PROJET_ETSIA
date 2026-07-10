// lib/services/notification_service.dart
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import '../services/api_service.dart';

/// Service de gestion des notifications push (Firebase).
/// Version simplifiée : pas d’affichage local, uniquement la réception.
class NotificationService {
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  static Future<void> init() async {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('⚠️ Firebase initialisation: $e');
    }

    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      debugPrint('❌ Permission push refusée');
      return;
    }

    debugPrint('✅ Permission push accordée');

    // Écouter les messages en premier plan
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Gestion du clic sur la notification (quand l’app est ouverte)
    RemoteMessage? initial = await _fcm.getInitialMessage();
    if (initial != null) _handleMessage(initial);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);
  }

  /// Enregistre le token FCM auprès du serveur – à appeler APRÈS l'authentification.
  static Future<void> registerToken() async {
    try {
      String? token = await _fcm.getToken();
      if (token != null) {
        debugPrint('🔑 FCM Token: $token');
        await ApiService().saveFcmToken(token);
      }
    } catch (e) {
      debugPrint('❌ Erreur enregistrement FCM token: $e');
    }
  }

  static void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('📩 Message en premier plan : ${message.notification?.title}');
    // Tu pourras ici afficher une notification locale si besoin
    // mais on évite pour l’instant les problèmes de version.
  }

  static void _handleMessage(RemoteMessage message) {
    debugPrint('📩 Notification cliquée : ${message.data}');
    // À terme, tu pourras naviguer vers l’écran approprié
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('📩 Message en arrière‑plan: ${message.messageId}');
}