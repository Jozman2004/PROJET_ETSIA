const pool = require('../config/database');
const { v4: uuidv4 } = require('uuid');
const { isBlocked } = require('./userController');
const { sendPushNotification } = require('../services/fcmService');

// ============================================================
// ENVOYER UN MESSAGE PRIVÉ
// ============================================================
exports.sendMessage = async (req, res) => {
  const startTime = Date.now();
  const { receiverId, content } = req.body;
  const replyToId = req.body.reply_to_id || req.body.replyToId || null;
  const senderId = req.user.userId;

  console.log(`📨 [sendMessage] Début - sender: ${senderId}, receiver: ${receiverId}`);

  if (!receiverId) {
    return res.status(400).json({ error: 'Destinataire requis' });
  }
  if (!content?.trim() && !req.file) {
    return res.status(400).json({ error: 'Message ou fichier requis' });
  }

  // Vérification blocage
  try {
    const blocked = await isBlocked(senderId, receiverId);
    if (blocked) {
      return res.status(403).json({
        error: 'Vous ne pouvez pas envoyer de message à cet utilisateur (blocage mutuel).',
        code: 'BLOCKED'
      });
    }
  } catch (err) {
    console.error('❌ [sendMessage] Erreur vérification blocage:', err.message);
    return res.status(500).json({ error: 'Erreur serveur' });
  }

  // Vérification reply_to_id
  if (replyToId) {
    try {
      const parentCheck = await pool.query(
        `SELECT id FROM messages
         WHERE id = $1
           AND (
             (sender_id = $2 AND receiver_id = $3)
             OR (sender_id = $3 AND receiver_id = $2)
           )`,
        [replyToId, senderId, receiverId]
      );
      if (parentCheck.rows.length === 0) {
        return res.status(400).json({ error: 'Message auquel vous répondez introuvable dans cette conversation' });
      }
    } catch (err) {
      console.error('❌ [sendMessage] Erreur vérification reply_to_id:', err.message);
      return res.status(500).json({ error: 'Erreur serveur' });
    }
  }

  try {
    const id = uuidv4();
    let fileUrl = null, fileType = null, fileName = null, fileSize = null;

    if (req.file) {
      const mime = req.file.mimetype;
      fileUrl = `/uploads/${req.file.filename}`;
      fileName = req.file.originalname;
      fileSize = req.file.size;
      if (mime.startsWith('image/'))      fileType = 'image';
      else if (mime.startsWith('video/')) fileType = 'video';
      else if (mime.startsWith('audio/')) fileType = 'audio';
      else                                fileType = 'document';
    }

    await pool.query(
      `INSERT INTO messages
         (id, sender_id, receiver_id, content, file_url, file_type, file_name, file_size, reply_to_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
      [id, senderId, receiverId, content?.trim() || null, fileUrl, fileType, fileName, fileSize, replyToId]
    );
    console.log(`💾 [sendMessage] Message ${id} sauvegardé`);

    const senderResult = await pool.query(
      'SELECT full_name, username, avatar_url FROM users WHERE id = $1',
      [senderId]
    );
    const sender = senderResult.rows[0];
    const senderName = sender?.full_name || 'Un utilisateur';

    const messageData = {
      id,
      senderId,
      receiverId,
      sender_id:   senderId,
      receiver_id: receiverId,
      content:     content?.trim() || null,
      fileUrl,
      file_url:    fileUrl,
      fileType,
      file_type:   fileType,
      fileName,
      file_name:   fileName,
      fileSize,
      file_size:   fileSize,
      createdAt:   new Date(),
      created_at:  new Date(),
      isRead:      false,
      is_read:     false,
      sender_username: sender?.username,
      avatar_url:      sender?.avatar_url,
      replyToId:   replyToId,
      reply_to_id: replyToId,
      isEdited:    false,
      is_edited:   false,
    };

    // Notification push (async)
    if (receiverId !== senderId) {
      let body = `${senderName} vous a envoyé un message`;
      if (content?.trim()) {
        const truncated = content.trim().substring(0, 60);
        body += ` : "${truncated}${content.trim().length > 60 ? '…' : ''}"`;
      } else if (fileUrl) {
        body = `${senderName} vous a envoyé un fichier`;
      }
      sendPushNotification(
        receiverId,
        'Nouveau message',
        body,
        { route: `/dm/${senderId}`, senderId, messageId: id }
      ).catch(err => console.error('Push error:', err.message));
    }

    // WebSocket
    if (global.io) {
      global.io.to(`user_${receiverId}`).emit('new_message', messageData);
      const countResult = await pool.query(
        'SELECT COUNT(*) FROM messages WHERE receiver_id = $1 AND is_read = false',
        [receiverId]
      );
      const unreadCount = parseInt(countResult.rows[0].count, 10);
      global.io.to(`user_${receiverId}`).emit('unread_messages_count', { count: unreadCount });
    }

    res.status(201).json({ ...messageData, message: 'Message envoyé' });
  } catch (err) {
    console.error(`❌ [sendMessage] ERREUR:`, err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ============================================================
// RÉCUPÉRER UNE CONVERSATION (avec pagination et filtrage suppressions)
// ============================================================
exports.getConversation = async (req, res) => {
  const { userId } = req.params;
  const currentUserId = req.user.userId;
  const { limit = 50, before } = req.query;

  try {
    let query = `
      SELECT
        m.*,
        u.username AS sender_username,
        u.avatar_url AS avatar_url
      FROM messages m
      JOIN users u ON m.sender_id = u.id
      WHERE
        (m.sender_id = $1 AND m.receiver_id = $2)
        OR
        (m.sender_id = $2 AND m.receiver_id = $1)
        AND m.is_deleted = false
    `;
    const params = [currentUserId, userId];

    if (before) {
      params.push(before);
      query += ` AND m.created_at < $${params.length}`;
    }

    query += ` ORDER BY m.created_at DESC LIMIT $${params.length + 1}`;
    params.push(parseInt(limit));

    const result = await pool.query(query, params);

    // Filtrer les messages supprimés "pour moi"
    const filtered = result.rows.filter(row => {
      if (row.sender_id === currentUserId && row.deleted_for_sender) return false;
      if (row.receiver_id === currentUserId && row.deleted_for_receiver) return false;
      return true;
    });

    res.json(filtered.reverse());
  } catch (err) {
    console.error(`❌ [getConversation] ERREUR:`, err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ============================================================
// MARQUER COMME LU
// ============================================================
exports.markAsRead = async (req, res) => {
  const { messageId } = req.params;
  const userId = req.user.userId;
  try {
    const result = await pool.query(
      `UPDATE messages SET is_read = true WHERE id = $1 AND receiver_id = $2
       RETURNING id, sender_id, receiver_id`,
      [messageId, userId]
    );
    if (result.rows.length > 0) {
      const message = result.rows[0];
      if (global.io) {
        global.io.to(`user_${message.sender_id}`).emit('message_read', {
          messageId, readerId: userId,
        });
      }
    }
    res.json({ message: 'Lu' });
  } catch (err) {
    console.error(`❌ [markAsRead] ERREUR:`, err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ============================================================
// LISTE DES CONVERSATIONS
// ============================================================
exports.getConversations = async (req, res) => {
  const userId = req.user.userId;
  try {
    const result = await pool.query(
      `SELECT DISTINCT ON (other_user)
         other_user,
         u.full_name,
         u.username,
         u.avatar_url,
         last_message.content      AS last_message,
         last_message.file_type    AS last_file_type,
         last_message.file_name    AS last_file_name,
         last_message.created_at   AS last_message_time,
         last_message.sender_id    AS last_sender_id,
         (
           SELECT COUNT(*)
           FROM messages
           WHERE receiver_id = $1
             AND sender_id = other_user
             AND is_read = false
             AND is_deleted = false
             AND NOT (receiver_id = $1 AND deleted_for_receiver = true)
             AND NOT (sender_id = $1 AND deleted_for_sender = true)
         ) AS unread_count
       FROM (
         SELECT sender_id   AS other_user FROM messages WHERE receiver_id = $1 AND is_deleted = false
         UNION
         SELECT receiver_id AS other_user FROM messages WHERE sender_id   = $1 AND is_deleted = false
       ) contacts
       JOIN LATERAL (
         SELECT content, file_type, file_name, created_at, sender_id
         FROM messages
         WHERE
           (sender_id = $1 AND receiver_id = other_user)
           OR
           (sender_id = other_user AND receiver_id = $1)
           AND is_deleted = false
           AND NOT (receiver_id = $1 AND deleted_for_receiver = true)
           AND NOT (sender_id = $1 AND deleted_for_sender = true)
         ORDER BY created_at DESC
         LIMIT 1
       ) last_message ON true
       JOIN users u ON u.id = other_user
       ORDER BY other_user, last_message.created_at DESC`,
      [userId]
    );
    res.json(result.rows);
  } catch (err) {
    console.error(`❌ [getConversations] ERREUR:`, err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ============================================================
// MODIFIER UN MESSAGE PRIVÉ
// ============================================================
exports.editMessage = async (req, res) => {
  const { messageId } = req.params;
  const { content } = req.body;
  const userId = req.user.userId;

  if (!content?.trim()) {
    return res.status(400).json({ error: 'Contenu requis' });
  }

  try {
    const message = await pool.query(
      `SELECT sender_id, receiver_id, content, edit_history FROM messages 
       WHERE id = $1 AND is_deleted = false`,
      [messageId]
    );
    if (message.rows.length === 0) {
      return res.status(404).json({ error: 'Message introuvable' });
    }

    const msg = message.rows[0];
    if (msg.sender_id !== userId) {
      return res.status(403).json({ error: 'Vous ne pouvez pas modifier ce message' });
    }

    const editHistory = msg.edit_history || [];
    editHistory.push({
      content: msg.content,
      edited_at: new Date().toISOString()
    });

    await pool.query(
      `UPDATE messages 
       SET content = $1, is_edited = true, edited_at = NOW(), edit_history = $2
       WHERE id = $3`,
      [content.trim(), JSON.stringify(editHistory), messageId]
    );

    const updated = await pool.query(
      `SELECT * FROM messages WHERE id = $1`,
      [messageId]
    );
    const updatedMsg = updated.rows[0];

    if (global.io) {
      global.io.to(`user_${msg.sender_id}`).emit('message_edited', updatedMsg);
      global.io.to(`user_${msg.receiver_id}`).emit('message_edited', updatedMsg);
    }

    res.json(updatedMsg);
  } catch (err) {
    console.error('❌ [editMessage] ERREUR:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ============================================================
// SUPPRIMER POUR TOUT LE MONDE (soft delete)
// ============================================================
exports.deleteMessage = async (req, res) => {
  const { messageId } = req.params;
  const userId = req.user.userId;
  const isAdmin = req.user.role === 'admin' || req.user.role === 'moderator';

  try {
    const message = await pool.query(
      `SELECT sender_id, receiver_id FROM messages WHERE id = $1 AND is_deleted = false`,
      [messageId]
    );
    if (message.rows.length === 0) {
      return res.status(404).json({ error: 'Message introuvable' });
    }
    const msg = message.rows[0];
    if (msg.sender_id !== userId && !isAdmin) {
      return res.status(403).json({ error: 'Non autorisé' });
    }

    await pool.query(
      `UPDATE messages SET is_deleted = true, deleted_at = NOW() WHERE id = $1`,
      [messageId]
    );

    if (global.io) {
      global.io.to(`user_${msg.sender_id}`).emit('message_deleted', { messageId });
      global.io.to(`user_${msg.receiver_id}`).emit('message_deleted', { messageId });
    }

    res.json({ message: 'Message supprimé', id: messageId });
  } catch (err) {
    console.error('❌ [deleteMessage] ERREUR:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ============================================================
// SUPPRIMER POUR MOI (masquer localement)
// ============================================================
exports.deleteForMe = async (req, res) => {
  const { messageId } = req.params;
  const userId = req.user.userId;

  try {
    const message = await pool.query(
      `SELECT sender_id, receiver_id FROM messages WHERE id = $1 AND is_deleted = false`,
      [messageId]
    );
    if (message.rows.length === 0) {
      return res.status(404).json({ error: 'Message introuvable' });
    }

    const msg = message.rows[0];
    if (msg.sender_id === userId) {
      await pool.query(`UPDATE messages SET deleted_for_sender = true WHERE id = $1`, [messageId]);
    } else if (msg.receiver_id === userId) {
      await pool.query(`UPDATE messages SET deleted_for_receiver = true WHERE id = $1`, [messageId]);
    } else {
      return res.status(403).json({ error: 'Non autorisé' });
    }

    if (global.io) {
      global.io.to(`user_${userId}`).emit('message_deleted_for_me', { messageId });
    }

    res.json({ message: 'Message masqué pour vous' });
  } catch (err) {
    console.error('❌ [deleteForMe] ERREUR:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};