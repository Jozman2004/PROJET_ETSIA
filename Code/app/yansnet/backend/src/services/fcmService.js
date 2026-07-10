// src/services/fcmService.js
const admin = require('firebase-admin');
const path = require('path');
const pool = require('../config/database');
const fs = require('fs');

let initialized = false;

// ✅ Chemin : config/serviceAccountKey.json
const serviceAccountPath = path.resolve(__dirname, '../../config/serviceAccountKey.json');

if (!fs.existsSync(serviceAccountPath)) {
  console.error('❌ Fichier de service account introuvable !');
  console.error(`   Chemin attendu: ${serviceAccountPath}`);
  console.warn('⚠️ Les notifications push ne fonctionneront pas sans ce fichier.');
} else {
  try {
    const serviceAccount = require(serviceAccountPath);
    if (admin && admin.apps) {
      if (admin.apps.length === 0) {
        admin.initializeApp({
          credential: admin.credential.cert(serviceAccount),
          projectId: serviceAccount.project_id || 'yansnet-adafe',
        });
        initialized = true;
        console.log('✅ Firebase Admin SDK initialisé avec succès (depuis fcmService)');
      } else {
        initialized = true;
        console.log('ℹ️ Firebase Admin déjà initialisé (réutilisation)');
      }
    } else {
      console.error('❌ Le module firebase-admin est introuvable ou mal chargé.');
      console.error('   Vérifiez que "npm install firebase-admin --save" a bien été exécuté.');
    }
  } catch (error) {
    console.error('❌ Erreur lors de l\'initialisation de Firebase Admin:', error.message);
    console.error('   Assurez-vous que le fichier serviceAccountKey.json est valide.');
  }
}

/**
 * Envoie une notification push à un utilisateur via FCM
 * @param {string} userId - ID de l'utilisateur destinataire
 * @param {string} title - Titre de la notification
 * @param {string} body - Corps de la notification
 * @param {Object} data - Données supplémentaires (route, senderId, etc.)
 */
async function sendPushNotification(userId, title, body, data = {}) {
  if (!initialized) {
    console.warn('⚠️ Firebase Admin non initialisé, notification non envoyée pour l\'utilisateur', userId);
    return;
  }

  try {
    // 1. Récupérer tous les tokens FCM de l'utilisateur
    const result = await pool.query(
      'SELECT token FROM fcm_tokens WHERE user_id = $1',
      [userId]
    );

    const tokens = result.rows.map(row => row.token);
    if (tokens.length === 0) {
      console.log(`📭 Aucun token FCM pour l'utilisateur ${userId}`);
      return;
    }

    // 2. Construire le message de base
    const message = {
      notification: {
        title: title || 'YANSNET',
        body: body || 'Vous avez une nouvelle notification',
      },
      data: {
        route: data.route || '',
        senderId: data.senderId || '',
        messageId: data.messageId || '',
        postId: data.postId || '',
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
      android: {
        priority: 'high',
        notification: {
          sound: 'default',
          channelId: 'yansnet_channel',
          clickAction: 'FLUTTER_NOTIFICATION_CLICK',
          icon: '@mipmap/ic_launcher',
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            contentAvailable: true,
            mutableContent: true,
          },
        },
      },
    };

    // ✅ Ajouter imageUrl uniquement si c'est une URL valide (commence par http)
    if (data.imageUrl && typeof data.imageUrl === 'string' && data.imageUrl.startsWith('http')) {
      message.android.notification.image = data.imageUrl;
      message.apns.fcmOptions = {
        imageUrl: data.imageUrl,
      };
    }

    // 3. Envoyer à tous les tokens
    const response = await admin.messaging().sendEachForMulticast({
      tokens: tokens,
      ...message,
    });

    console.log(`📨 Push envoyé : ${response.successCount} succès, ${response.failureCount} échecs`);

    // 4. Gérer les tokens invalides
    if (response.failureCount > 0) {
      const invalidTokens = [];
      response.responses.forEach((resp, idx) => {
        if (!resp.success) {
          invalidTokens.push(tokens[idx]);
        }
      });
      if (invalidTokens.length > 0) {
        await pool.query(
          'DELETE FROM fcm_tokens WHERE token = ANY($1)',
          [invalidTokens]
        );
        console.log(`🧹 ${invalidTokens.length} tokens invalides supprimés`);
      }
    }

    return response;
  } catch (error) {
    console.error('❌ Erreur sendPushNotification:', error.message);
    throw error;
  }
}

module.exports = { sendPushNotification };