// src/controllers/notificationController.js — VERSION COMPLÈTE AVEC TARGET_TYPE, PAGINATION ET SUPPRESSION
const pool = require('../config/database');
const { v4: uuidv4 } = require('uuid');

// ─── Constantes pour les types de notifications ────────────────────────────
const NOTIFICATION_TYPES = {
  LIKE: 'like',
  COMMENT: 'comment',
  NEW_FOLLOWER: 'new_follower',
  MENTION: 'mention',
  REPOST: 'repost',
  WARNING: 'warning',
  MODERATION_ALERT: 'moderation_alert',
  GROUP_ADDED: 'group_added',
};

// ─── Fonction interne utilisée par les autres contrôleurs ──────────────────
// Ajout du paramètre targetType pour indiquer le type d'objet lié
const notify = async (userId, type, content, referenceId = null, targetType = null) => {
  if (!userId || !type || !content) {
    console.warn('notify appelé avec des paramètres manquants:', { userId, type, content });
    return;
  }

  try {
    const id = uuidv4();
    const createdAt = new Date();

    await pool.query(
      `INSERT INTO notifications (id, user_id, type, content, reference_id, target_type, created_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [id, userId, type, content, referenceId, targetType, createdAt]
    );

    if (global.io) {
      const room = `user_${userId}`;
      global.io.to(room).emit('new_notification', {
        id,
        type,
        content,
        referenceId,
        targetType,
        createdAt: createdAt.toISOString(),
        is_read: false,
      });
    }
  } catch (err) {
    console.error('Erreur dans notify:', err.message);
  }
};

exports.notify = notify;

// ─── GET /api/notifications ──────────────────────────────────────────────────
// Retourne la liste des notifications avec target_type pour la redirection
exports.getNotifications = async (req, res) => {
  const { limit, offset = 0 } = req.query;

  try {
    let result;
    if (limit === undefined) {
      result = await pool.query(
        `SELECT id, type, content, reference_id, target_type, is_read, created_at
         FROM notifications
         WHERE user_id = $1
         ORDER BY created_at DESC
         LIMIT 50`,
        [req.user.userId]
      );
      return res.json(result.rows);
    }

    const parsedLimit = Math.min(parseInt(limit, 10) || 20, 100);
    const parsedOffset = Math.max(parseInt(offset, 10) || 0, 0);

    result = await pool.query(
      `SELECT id, type, content, reference_id, target_type, is_read, created_at
       FROM notifications
       WHERE user_id = $1
       ORDER BY created_at DESC
       LIMIT $2 OFFSET $3`,
      [req.user.userId, parsedLimit, parsedOffset]
    );

    const countResult = await pool.query(
      `SELECT COUNT(*) as total FROM notifications WHERE user_id = $1`,
      [req.user.userId]
    );
    const total = parseInt(countResult.rows[0].total, 10);

    res.json({
      notifications: result.rows,
      pagination: {
        limit: parsedLimit,
        offset: parsedOffset,
        total,
        hasMore: parsedOffset + parsedLimit < total,
      },
    });
  } catch (err) {
    console.error('Erreur getNotifications:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ─── GET /api/notifications/unread-count ─────────────────────────────────────
exports.getUnreadCount = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT COUNT(*) as count
       FROM notifications
       WHERE user_id = $1 AND is_read = false`,
      [req.user.userId]
    );
    const count = parseInt(result.rows[0].count, 10) || 0;
    res.json({ count });
  } catch (err) {
    console.error('Erreur getUnreadCount:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ─── PUT /api/notifications/:id/read ─────────────────────────────────────────
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
       RETURNING id, is_read`,
      [id, userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Notification non trouvée ou non autorisée' });
    }

    if (global.io) {
      const room = `user_${userId}`;
      global.io.to(room).emit('notification_read', { id, is_read: true });
    }

    res.json({ message: 'Notification marquée comme lue', notification: result.rows[0] });
  } catch (err) {
    console.error('Erreur markOneRead:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ─── PUT /api/notifications/read-all ─────────────────────────────────────────
exports.markAllRead = async (req, res) => {
  try {
    const result = await pool.query(
      `UPDATE notifications
       SET is_read = true
       WHERE user_id = $1 AND is_read = false
       RETURNING id`,
      [req.user.userId]
    );

    const updatedIds = result.rows.map(row => row.id);

    if (global.io && updatedIds.length > 0) {
      const room = `user_${req.user.userId}`;
      global.io.to(room).emit('notifications_read_all', { ids: updatedIds });
    }

    res.json({
      message: 'Toutes les notifications ont été marquées comme lues',
      count: updatedIds.length,
    });
  } catch (err) {
    console.error('Erreur markAllRead:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ─── DELETE /api/notifications/:id ───────────────────────────────────────────
exports.deleteNotification = async (req, res) => {
  const { id } = req.params;
  const userId = req.user.userId;

  if (!id) {
    return res.status(400).json({ error: 'ID de notification manquant' });
  }

  try {
    const result = await pool.query(
      `DELETE FROM notifications
       WHERE id = $1 AND user_id = $2
       RETURNING id`,
      [id, userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Notification non trouvée ou non autorisée' });
    }

    if (global.io) {
      const room = `user_${userId}`;
      global.io.to(room).emit('notification_deleted', { id });
    }

    res.json({ message: 'Notification supprimée' });
  } catch (err) {
    console.error('Erreur deleteNotification:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ─── DELETE /api/notifications/clear-all ─────────────────────────────────────
exports.clearAllNotifications = async (req, res) => {
  try {
    const result = await pool.query(
      `DELETE FROM notifications
       WHERE user_id = $1
       RETURNING id`,
      [req.user.userId]
    );

    const deletedIds = result.rows.map(row => row.id);

    if (global.io && deletedIds.length > 0) {
      const room = `user_${req.user.userId}`;
      global.io.to(room).emit('notifications_cleared', { ids: deletedIds });
    }

    res.json({
      message: 'Toutes les notifications ont été supprimées',
      count: deletedIds.length,
    });
  } catch (err) {
    console.error('Erreur clearAllNotifications:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ─── GET /api/notifications/types ───────────────────────────────────────────
exports.getNotificationTypes = (req, res) => {
  res.json({ types: Object.values(NOTIFICATION_TYPES) });
};