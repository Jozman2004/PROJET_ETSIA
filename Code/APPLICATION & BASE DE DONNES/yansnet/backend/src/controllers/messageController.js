const pool = require('../config/database');
const { v4: uuidv4 } = require('uuid');

// POST /api/messages
exports.sendMessage = async (req, res) => {
  const { receiverId, content } = req.body;
  const senderId = req.user.userId;

  if (!receiverId) {
    return res.status(400).json({ error: 'Destinataire requis' });
  }
  if (!content?.trim() && !req.file) {
    return res.status(400).json({ error: 'Message ou fichier requis' });
  }

  try {
    const id = uuidv4();
    let fileUrl = null, fileType = null, fileName = null, fileSize = null;

    if (req.file) {
      const mime = req.file.mimetype;

      // fileUrl  = chemin de stockage (nom généré par multer ex: file_1777239001781.pdf)
      // fileName = nom original du fichier envoyé par l'utilisateur (ex: rapport.pdf)
      fileUrl  = `/uploads/${req.file.filename}`;
      fileName = req.file.originalname;   // ← NOM ORIGINAL affiché dans la bulle
      fileSize = req.file.size;

      if (mime.startsWith('image/'))      fileType = 'image';
      else if (mime.startsWith('video/')) fileType = 'video';
      else if (mime.startsWith('audio/')) fileType = 'audio';
      else                                fileType = 'document';
    }

    await pool.query(
      `INSERT INTO messages
         (id, sender_id, receiver_id, content, file_url, file_type, file_name, file_size)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [id, senderId, receiverId, content?.trim() || null, fileUrl, fileType, fileName, fileSize]
    );

    // Réponse renvoyée au client Flutter — toutes les clés en camelCase ET snake_case
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
      fileName,               // ← nom original
      file_name:   fileName,  // ← nom original (snake_case pour Message.fromJson)
      fileSize,
      file_size:   fileSize,
      createdAt:   new Date(),
      created_at:  new Date(),
      isRead:      false,
      is_read:     false,
    };

    // Émission socket en temps réel au destinataire
    if (global.io) {
      global.io.to(`user_${receiverId}`).emit('new_message', messageData);
    }

    res.status(201).json({ ...messageData, message: 'Message envoyé' });
  } catch (err) {
    console.error('sendMessage:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// GET /api/messages/:userId  — récupère la conversation entre 2 utilisateurs
exports.getConversation = async (req, res) => {
  const { userId } = req.params;
  const currentUserId = req.user.userId;
  try {
    const result = await pool.query(
      `SELECT
         m.*,
         u.username AS sender_username
       FROM messages m
       JOIN users u ON m.sender_id = u.id
       WHERE
         (m.sender_id = $1 AND m.receiver_id = $2)
         OR
         (m.sender_id = $2 AND m.receiver_id = $1)
       ORDER BY m.created_at ASC`,
      [currentUserId, userId]
    );
    res.json(result.rows);
  } catch (err) {
    console.error('getConversation:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// PUT /api/messages/:messageId/read  — marque un message comme lu
exports.markAsRead = async (req, res) => {
  const { messageId } = req.params;
  const userId = req.user.userId;
  try {
    await pool.query(
      `UPDATE messages SET is_read = true WHERE id = $1 AND receiver_id = $2`,
      [messageId, userId]
    );
    res.json({ message: 'Lu' });
  } catch (err) {
    console.error('markAsRead:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// GET /api/messages/conversations/list  — liste des conversations de l'utilisateur
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
         (
           SELECT COUNT(*)
           FROM messages
           WHERE receiver_id = $1
             AND sender_id = other_user
             AND is_read = false
         ) AS unread_count
       FROM (
         SELECT sender_id   AS other_user FROM messages WHERE receiver_id = $1
         UNION
         SELECT receiver_id AS other_user FROM messages WHERE sender_id   = $1
       ) contacts
       JOIN LATERAL (
         SELECT content, file_type, file_name, created_at
         FROM messages
         WHERE
           (sender_id = $1 AND receiver_id = other_user)
           OR
           (sender_id = other_user AND receiver_id = $1)
         ORDER BY created_at DESC
         LIMIT 1
       ) last_message ON true
       JOIN users u ON u.id = other_user
       ORDER BY other_user, last_message.created_at DESC`,
      [userId]
    );
    res.json(result.rows);
  } catch (err) {
    console.error('getConversations:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};