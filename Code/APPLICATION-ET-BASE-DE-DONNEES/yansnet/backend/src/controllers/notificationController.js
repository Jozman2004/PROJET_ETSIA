// src/controllers/notificationController.js — VERSION CORRIGÉE ET COMPLÈTE
const pool = require('../config/database');
const { v4: uuidv4 } = require('uuid');

/**
 * Fonction interne utilisée par les autres contrôleurs pour créer une notification
 * @param {string} userId - ID de l'utilisateur destinataire
 * @param {string} type - Type de notification (like, comment, new_follower, etc.)
 * @param {string} content - Contenu texte de la notification
 * @param {string|null} referenceId - ID de référence (post, commentaire, etc.)
 */
const notify = async (userId, type, content, referenceId = null) => {
  if (!userId || !type || !content) {
    console.warn('notify appelé avec des paramètres manquants:', { userId, type, content });
    return;
  }
  try {
    const id = uuidv4();
    const createdAt = new Date();
    await pool.query(
      `INSERT INTO notifications (id, user_id, type, content, reference_id, created_at)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [id, userId, type, content, referenceId, createdAt]
    );

    // Émettre en temps réel via WebSocket si disponible
    if (global.io) {
      const room = `user_${userId}`;
      global.io.to(room).emit('new_notification', {
        id,
        type,
        content,
        referenceId,
        createdAt: createdAt.toISOString(),
        is_read: false,
      });
    } else {
      console.warn('global.io non défini, notification WebSocket non envoyée');
    }
  } catch (err) {
    console.error('Erreur dans notify:', err.message);
    // On ne relance pas l'erreur pour ne pas bloquer le processus principal
  }
};

exports.notify = notify;

// GET /api/notifications — Récupérer les notifications de l'utilisateur
exports.getNotifications = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT id, type, content, reference_id, is_read, created_at
       FROM notifications
       WHERE user_id = $1
       ORDER BY created_at DESC
       LIMIT 50`,
      [req.user.userId]
    );
    res.json(result.rows);
  } catch (err) {
    console.error('Erreur getNotifications:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// GET /api/notifications/unread-count — Nombre de notifications non lues
exports.getUnreadCount = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT COUNT(*) as count
       FROM notifications
       WHERE user_id = $1 AND is_read = false`,
      [req.user.userId]
    );
    const count = parseInt(result.rows[0].count, 10);
    res.json({ count });
  } catch (err) {
    console.error('Erreur getUnreadCount:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// PUT /api/notifications/:id/read — Marquer une notification comme lue
exports.markOneRead = async (req, res) => {
  const { id } = req.params;
  const userId = req.user.userId;
  if (!id) {
    return res.status(400).json({ error: 'ID de notification manquant' });
  }
  try {
    const result = await pool.query(
      `UPDATE notifications
       SET is_read = true
       WHERE id = $1 AND user_id = $2
       RETURNING id`,
      [id, userId]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Notification non trouvée ou non autorisée' });
    }
    res.json({ message: 'Notification marquée comme lue' });
  } catch (err) {
    console.error('Erreur markOneRead:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// PUT /api/notifications/read-all — Marquer toutes les notifications comme lues
exports.markAllRead = async (req, res) => {
  try {
    await pool.query(
      `UPDATE notifications
       SET is_read = true
       WHERE user_id = $1 AND is_read = false`,
      [req.user.userId]
    );
    res.json({ message: 'Toutes les notifications ont été marquées comme lues' });
  } catch (err) {
    console.error('Erreur markAllRead:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};