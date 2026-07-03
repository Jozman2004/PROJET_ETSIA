// controllers/groupController.js
// Version complète avec épinglage, notifications, description

const pool = require('../config/database');
const { v4: uuidv4 } = require('uuid');
const { notify } = require('./notificationController');

// ========== CRÉATION DU GROUPE ==========
exports.createGroup = async (req, res) => {
  const { name, memberIds, description } = req.body;
  const creatorId = req.user.userId;

  if (!name?.trim())
    return res.status(400).json({ error: 'Nom du groupe requis' });
  if (!Array.isArray(memberIds) || memberIds.length === 0)
    return res.status(400).json({ error: 'Au moins un membre requis' });

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const groupId = uuidv4();
    await client.query(
      `INSERT INTO groups (id, name, created_by, description) VALUES ($1, $2, $3, $4)`,
      [groupId, name.trim(), creatorId, description?.trim() || null]
    );
    await client.query(
      `INSERT INTO group_members (group_id, user_id, role) VALUES ($1, $2, 'admin')`,
      [groupId, creatorId]
    );
    const uniqueMembers = [...new Set(memberIds)].filter(id => id !== creatorId);
    for (const memberId of uniqueMembers) {
      await client.query(
        `INSERT INTO group_members (group_id, user_id, role) VALUES ($1, $2, 'member') ON CONFLICT DO NOTHING`,
        [groupId, memberId]
      );
    }
    const welcomeId = uuidv4();
    await client.query(
      `INSERT INTO group_messages (id, group_id, sender_id, content, is_system) VALUES ($1, $2, $3, $4, true)`,
      [welcomeId, groupId, creatorId, `Groupe "${name.trim()}" créé`]
    );
    await client.query('COMMIT');

    const groupResult = await pool.query(
      `SELECT g.*, u.username AS creator_username, COUNT(gm.user_id) AS member_count
       FROM groups g
       JOIN users u ON g.created_by = u.id
       JOIN group_members gm ON g.id = gm.group_id
       WHERE g.id = $1 GROUP BY g.id, u.username`,
      [groupId]
    );
    const group = groupResult.rows[0];

    // Notifications
    const creator = await pool.query(`SELECT username FROM users WHERE id = $1`, [creatorId]);
    const creatorUsername = creator.rows[0].username;
    const allMemberIds = [creatorId, ...uniqueMembers];
    for (const memberId of allMemberIds) {
      if (memberId !== creatorId) {
        await notify(memberId, 'group_invite', `${creatorUsername} vous a ajouté au groupe "${name.trim()}"`, groupId);
      }
    }
    if (global.io) {
      global.io.to(`group_${groupId}`).emit('group_message', {
        id: welcomeId, group_id: groupId, sender_id: creatorId,
        content: `Groupe "${name.trim()}" créé`, is_system: true, created_at: new Date(),
      });
      for (const memberId of allMemberIds) {
        global.io.to(`user_${memberId}`).emit('added_to_group', {
          group_id: groupId, group_name: group.name, member_count: parseInt(group.member_count),
        });
      }
    }
    return res.status(201).json({
      id: groupId, name: group.name, description: group.description,
      created_by: group.created_by,
      creator_username: group.creator_username, member_count: parseInt(group.member_count),
      role: 'admin', created_at: group.created_at, message: 'Groupe créé avec succès',
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('❌ createGroup:', err.message);
    return res.status(500).json({ error: 'Erreur serveur', detail: err.message });
  } finally {
    client.release();
  }
};

// ========== MODIFIER GROUPE (nom, description) ==========
exports.updateGroup = async (req, res) => {
  const { groupId } = req.params;
  const { name, description } = req.body;
  const userId = req.user.userId;
  if (!name?.trim() && description === undefined) {
    return res.status(400).json({ error: 'Nom ou description requis' });
  }
  try {
    const adminCheck = await pool.query(
      `SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2`,
      [groupId, userId]
    );
    if (adminCheck.rows.length === 0 || adminCheck.rows[0].role !== 'admin')
      return res.status(403).json({ error: 'Seul un admin peut modifier le groupe' });

    let updateQuery = `UPDATE groups SET `;
    const fields = [];
    const values = [];
    if (name?.trim()) {
      fields.push(`name = $${values.length + 1}`);
      values.push(name.trim());
    }
    if (description !== undefined) {
      fields.push(`description = $${values.length + 1}`);
      values.push(description?.trim() || null);
    }
    if (fields.length === 0) return res.status(400).json({ error: 'Aucune modification' });
    updateQuery += fields.join(', ') + ` WHERE id = $${values.length + 1}`;
    values.push(groupId);
    await pool.query(updateQuery, values);

    if (name?.trim()) {
      const msgId = uuidv4();
      await pool.query(
        `INSERT INTO group_messages (id, group_id, sender_id, content, is_system) VALUES ($1, $2, $3, $4, true)`,
        [msgId, groupId, userId, `Le groupe a été renommé "${name.trim()}"`]
      );
      if (global.io) {
        global.io.to(`group_${groupId}`).emit('group_updated', { group_id: groupId, name: name.trim() });
      }
    }
    return res.json({ message: 'Groupe mis à jour', name: name?.trim(), description: description?.trim() });
  } catch (err) {
    console.error('updateGroup:', err.message);
    return res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ========== LISTE DES GROUPES ==========
exports.getMyGroups = async (req, res) => {
  const userId = req.user.userId;
  try {
    const result = await pool.query(
      `SELECT g.id, g.name, g.description, g.created_by, g.created_at, gm.role,
              (SELECT COUNT(*) FROM group_members WHERE group_id = g.id) AS member_count,
              lm.content AS last_message, lm.file_type AS last_file_type,
              lm.sender_id AS last_sender_id, lu.username AS last_sender_username,
              lm.created_at AS last_message_time,
              (SELECT COUNT(*) FROM group_messages WHERE group_id = g.id AND sender_id != $1 AND is_read = false) AS unread_count
       FROM groups g
       JOIN group_members gm ON g.id = gm.group_id AND gm.user_id = $1
       LEFT JOIN LATERAL (SELECT content, file_type, sender_id, created_at FROM group_messages WHERE group_id = g.id ORDER BY created_at DESC LIMIT 1) lm ON true
       LEFT JOIN users lu ON lu.id = lm.sender_id
       ORDER BY COALESCE(lm.created_at, g.created_at) DESC`,
      [userId]
    );
    return res.json(result.rows);
  } catch (err) {
    console.error('getMyGroups:', err.message);
    return res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ========== DÉTAILS D'UN GROUPE (avec membres) ==========
exports.getGroupDetails = async (req, res) => {
  const { groupId } = req.params;
  const userId = req.user.userId;
  try {
    const memberCheck = await pool.query(
      `SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2`,
      [groupId, userId]
    );
    if (memberCheck.rows.length === 0)
      return res.status(403).json({ error: 'Accès refusé' });
    const groupResult = await pool.query(
      `SELECT g.*, u.username AS creator_username FROM groups g JOIN users u ON g.created_by = u.id WHERE g.id = $1`,
      [groupId]
    );
    if (groupResult.rows.length === 0)
      return res.status(404).json({ error: 'Groupe introuvable' });
    const membersResult = await pool.query(
      `SELECT u.id, u.username, u.full_name, u.avatar_url, gm.role, gm.joined_at
       FROM group_members gm JOIN users u ON gm.user_id = u.id WHERE gm.group_id = $1
       ORDER BY gm.role DESC, u.username ASC`,
      [groupId]
    );
    return res.json({
      ...groupResult.rows[0],
      members: membersResult.rows,
      my_role: memberCheck.rows[0].role,
    });
  } catch (err) {
    console.error('getGroupDetails:', err.message);
    return res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ========== AJOUTER DES MEMBRES ==========
exports.addMembers = async (req, res) => {
  const { groupId } = req.params;
  const { memberIds } = req.body;
  const userId = req.user.userId;
  if (!Array.isArray(memberIds) || memberIds.length === 0)
    return res.status(400).json({ error: 'Membres requis' });
  try {
    const adminCheck = await pool.query(
      `SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2`,
      [groupId, userId]
    );
    if (adminCheck.rows.length === 0 || adminCheck.rows[0].role !== 'admin')
      return res.status(403).json({ error: 'Seul un admin peut ajouter des membres' });
    const added = [];
    for (const memberId of memberIds) {
      const r = await pool.query(
        `INSERT INTO group_members (group_id, user_id, role) VALUES ($1, $2, 'member') ON CONFLICT DO NOTHING RETURNING user_id`,
        [groupId, memberId]
      );
      if (r.rows.length > 0) added.push(memberId);
    }
    if (added.length > 0) {
      const usernames = await pool.query(`SELECT username FROM users WHERE id = ANY($1)`, [added]);
      const names = usernames.rows.map(r => r.username).join(', ');
      const sysMsg = `${names} ${added.length > 1 ? 'ont été ajoutés' : 'a été ajouté'}`;
      const msgId = uuidv4();
      await pool.query(
        `INSERT INTO group_messages (id, group_id, sender_id, content, is_system) VALUES ($1, $2, $3, $4, true)`,
        [msgId, groupId, userId, sysMsg]
      );
      const adder = await pool.query(`SELECT username FROM users WHERE id = $1`, [userId]);
      const adderUsername = adder.rows[0].username;
      const groupNameRes = await pool.query(`SELECT name FROM groups WHERE id = $1`, [groupId]);
      const groupName = groupNameRes.rows[0].name;
      for (const memberId of added) {
        await notify(memberId, 'group_invite', `${adderUsername} vous a ajouté au groupe "${groupName}"`, groupId);
      }
      if (global.io) {
        global.io.to(`group_${groupId}`).emit('group_message', {
          id: msgId, group_id: groupId, sender_id: userId, content: sysMsg, is_system: true, created_at: new Date(),
        });
        for (const memberId of added) {
          global.io.to(`user_${memberId}`).emit('added_to_group', { group_id: groupId });
        }
      }
    }
    return res.json({ added, message: `${added.length} membre(s) ajouté(s)` });
  } catch (err) {
    console.error('addMembers:', err.message);
    return res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ========== RETIRER UN MEMBRE / QUITTER ==========
exports.removeMember = async (req, res) => {
  const { groupId, memberId } = req.params;
  const userId = req.user.userId;
  try {
    const adminCheck = await pool.query(
      `SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2`,
      [groupId, userId]
    );
    const isSelf = memberId === userId;
    if (!isSelf && (adminCheck.rows.length === 0 || adminCheck.rows[0].role !== 'admin'))
      return res.status(403).json({ error: 'Non autorisé' });
    await pool.query(`DELETE FROM group_members WHERE group_id = $1 AND user_id = $2`, [groupId, memberId]);
    const userResult = await pool.query(`SELECT username FROM users WHERE id = $1`, [memberId]);
    const username = userResult.rows[0]?.username ?? 'Membre';
    const sysMsg = isSelf ? `${username} a quitté le groupe` : `${username} a été retiré du groupe`;
    const msgId = uuidv4();
    await pool.query(
      `INSERT INTO group_messages (id, group_id, sender_id, content, is_system) VALUES ($1, $2, $3, $4, true)`,
      [msgId, groupId, userId, sysMsg]
    );
    if (global.io) {
      global.io.to(`group_${groupId}`).emit('group_message', {
        id: msgId, group_id: groupId, sender_id: userId, content: sysMsg, is_system: true, created_at: new Date(),
      });
      global.io.to(`user_${memberId}`).emit('removed_from_group', { group_id: groupId });
    }
    return res.json({ message: 'Membre retiré' });
  } catch (err) {
    console.error('removeMember:', err.message);
    return res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ========== RENOMMER / MODIFIER DESCRIPTION ==========
// (déjà géré par updateGroup ci-dessus)

// ========== PROMOUVOIR MEMBRE ==========
exports.promoteMember = async (req, res) => {
  const { groupId, memberId } = req.params;
  const userId = req.user.userId;
  try {
    const adminCheck = await pool.query(
      `SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2`,
      [groupId, userId]
    );
    if (adminCheck.rows.length === 0 || adminCheck.rows[0].role !== 'admin')
      return res.status(403).json({ error: 'Non autorisé' });
    await pool.query(`UPDATE group_members SET role = 'admin' WHERE group_id = $1 AND user_id = $2`, [groupId, memberId]);
    const userResult = await pool.query(`SELECT username FROM users WHERE id = $1`, [memberId]);
    const username = userResult.rows[0]?.username ?? 'Membre';
    const msgId = uuidv4();
    await pool.query(
      `INSERT INTO group_messages (id, group_id, sender_id, content, is_system) VALUES ($1, $2, $3, $4, true)`,
      [msgId, groupId, userId, `${username} est maintenant administrateur`]
    );
    if (global.io) {
      global.io.to(`group_${groupId}`).emit('group_message', {
        id: msgId, group_id: groupId, content: `${username} est maintenant administrateur`,
        is_system: true, created_at: new Date(),
      });
    }
    return res.json({ message: 'Membre promu admin' });
  } catch (err) {
    console.error('promoteMember:', err.message);
    return res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ========== SUPPRIMER LE GROUPE ==========
exports.deleteGroup = async (req, res) => {
  const { groupId } = req.params;
  const userId = req.user.userId;
  try {
    const groupCheck = await pool.query(`SELECT created_by FROM groups WHERE id = $1`, [groupId]);
    if (groupCheck.rows.length === 0) return res.status(404).json({ error: 'Groupe introuvable' });
    if (groupCheck.rows[0].created_by !== userId)
      return res.status(403).json({ error: 'Seul le créateur peut supprimer le groupe' });
    const membersResult = await pool.query(`SELECT user_id FROM group_members WHERE group_id = $1`, [groupId]);
    const memberIds = membersResult.rows.map(r => r.user_id);
    await pool.query(`DELETE FROM groups WHERE id = $1`, [groupId]);
    if (global.io) {
      for (const memberId of memberIds) {
        global.io.to(`user_${memberId}`).emit('group_deleted', { group_id: groupId });
      }
    }
    return res.json({ message: 'Groupe supprimé' });
  } catch (err) {
    console.error('deleteGroup:', err.message);
    return res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ========== MESSAGES DU GROUPE (avec is_pinned) ==========
exports.getGroupMessages = async (req, res) => {
  const { groupId } = req.params;
  const userId = req.user.userId;
  const { limit = 50, before } = req.query;
  try {
    const memberCheck = await pool.query(
      `SELECT 1 FROM group_members WHERE group_id = $1 AND user_id = $2`,
      [groupId, userId]
    );
    if (memberCheck.rows.length === 0) return res.status(403).json({ error: 'Accès refusé' });
    let query = `
      SELECT gm.*, u.username, u.avatar_url,
        (gm.id = (SELECT pinned_message_id FROM groups WHERE id = gm.group_id)) AS is_pinned
      FROM group_messages gm
      LEFT JOIN users u ON gm.sender_id = u.id
      WHERE gm.group_id = $1
    `;
    const params = [groupId];
    if (before) {
      params.push(before);
      query += ` AND gm.created_at < $${params.length}`;
    }
    params.push(parseInt(limit));
    query += ` ORDER BY gm.created_at DESC LIMIT $${params.length}`;
    const result = await pool.query(query, params);
    await pool.query(
      `UPDATE group_messages SET is_read = true WHERE group_id = $1 AND sender_id != $2 AND is_read = false`,
      [groupId, userId]
    );
    return res.json(result.rows.reverse());
  } catch (err) {
    console.error('getGroupMessages:', err.message);
    return res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ========== ENVOYER UN MESSAGE ==========
exports.sendGroupMessage = async (req, res) => {
  const { groupId } = req.params;
  const { content } = req.body;
  const senderId = req.user.userId;
  if (!content?.trim() && !req.file)
    return res.status(400).json({ error: 'Message ou fichier requis' });
  try {
    const memberCheck = await pool.query(
      `SELECT 1 FROM group_members WHERE group_id = $1 AND user_id = $2`,
      [groupId, senderId]
    );
    if (memberCheck.rows.length === 0) return res.status(403).json({ error: 'Accès refusé' });
    const id = uuidv4();
    let fileUrl = null, fileType = null, fileName = null, fileSize = null;
    if (req.file) {
      const mime = req.file.mimetype;
      fileUrl = `/uploads/${req.file.filename}`;
      fileName = req.file.originalname;
      fileSize = req.file.size;
      if (mime.startsWith('image/')) fileType = 'image';
      else if (mime.startsWith('video/')) fileType = 'video';
      else if (mime.startsWith('audio/')) fileType = 'audio';
      else fileType = 'document';
    }
    await pool.query(
      `INSERT INTO group_messages (id, group_id, sender_id, content, file_url, file_type, file_name, file_size, is_system)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, false)`,
      [id, groupId, senderId, content?.trim() || null, fileUrl, fileType, fileName, fileSize]
    );
    const senderResult = await pool.query(`SELECT username, avatar_url FROM users WHERE id = $1`, [senderId]);
    const sender = senderResult.rows[0];
    const messageData = {
      id, group_id: groupId, sender_id: senderId, username: sender?.username,
      avatar_url: sender?.avatar_url, content: content?.trim() || null,
      file_url: fileUrl, file_type: fileType, file_name: fileName, file_size: fileSize,
      is_system: false, is_read: false, created_at: new Date(),
      is_pinned: false,
    };
    if (global.io) {
      global.io.to(`group_${groupId}`).emit('group_message', messageData);
    }
    return res.status(201).json(messageData);
  } catch (err) {
    console.error('sendGroupMessage:', err.message);
    return res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ========== RECHERCHE D'UTILISATEURS ==========
exports.searchUsers = async (req, res) => {
  const { q } = req.query;
  const userId = req.user.userId;
  if (!q?.trim()) return res.json([]);
  try {
    const result = await pool.query(
      `SELECT id, username, full_name, avatar_url FROM users
       WHERE (username ILIKE $1 OR full_name ILIKE $1) AND id != $2 LIMIT 20`,
      [`%${q.trim()}%`, userId]
    );
    return res.json(result.rows);
  } catch (err) {
    console.error('searchUsers:', err.message);
    return res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ========== ÉPINGLER UN MESSAGE (admin) ==========
exports.pinMessage = async (req, res) => {
  const { groupId, messageId } = req.params;
  const userId = req.user.userId;
  try {
    const adminCheck = await pool.query(
      `SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2`,
      [groupId, userId]
    );
    if (adminCheck.rows.length === 0 || adminCheck.rows[0].role !== 'admin') {
      return res.status(403).json({ error: 'Seul un administrateur peut épingler un message' });
    }
    const msgCheck = await pool.query(
      `SELECT id FROM group_messages WHERE id = $1 AND group_id = $2`,
      [messageId, groupId]
    );
    if (msgCheck.rows.length === 0) {
      return res.status(404).json({ error: 'Message introuvable dans ce groupe' });
    }
    await pool.query(`UPDATE groups SET pinned_message_id = $1 WHERE id = $2`, [messageId, groupId]);

    const systemMsgId = uuidv4();
    const adminInfo = await pool.query(`SELECT username FROM users WHERE id = $1`, [userId]);
    const adminName = adminInfo.rows[0]?.username || 'Un administrateur';
    const systemContent = `📌 Message épinglé par ${adminName}`;
    await pool.query(
      `INSERT INTO group_messages (id, group_id, sender_id, content, is_system) VALUES ($1, $2, $3, $4, true)`,
      [systemMsgId, groupId, userId, systemContent]
    );
    if (global.io) {
      const systemMessage = {
        id: systemMsgId, group_id: groupId, sender_id: userId, content: systemContent,
        is_system: true, created_at: new Date(), username: adminName,
      };
      global.io.to(`group_${groupId}`).emit('group_message', systemMessage);
      const pinnedMessage = await pool.query(
        `SELECT gm.*, u.username, u.avatar_url FROM group_messages gm LEFT JOIN users u ON gm.sender_id = u.id WHERE gm.id = $1`,
        [messageId]
      );
      global.io.to(`group_${groupId}`).emit('message_pinned', { groupId, pinnedMessage: pinnedMessage.rows[0] });
    }
    res.json({ message: 'Message épinglé avec succès' });
  } catch (err) {
    console.error('pinMessage:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ========== DÉSÉPINGLER UN MESSAGE (admin) ==========
exports.unpinMessage = async (req, res) => {
  const { groupId } = req.params;
  const userId = req.user.userId;
  try {
    const adminCheck = await pool.query(
      `SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2`,
      [groupId, userId]
    );
    if (adminCheck.rows.length === 0 || adminCheck.rows[0].role !== 'admin') {
      return res.status(403).json({ error: 'Seul un administrateur peut désépingler' });
    }
    await pool.query(`UPDATE groups SET pinned_message_id = NULL WHERE id = $1`, [groupId]);

    const systemMsgId = uuidv4();
    const adminInfo = await pool.query(`SELECT username FROM users WHERE id = $1`, [userId]);
    const adminName = adminInfo.rows[0]?.username || 'Un administrateur';
    const systemContent = `Message désépinglé par ${adminName}`;
    await pool.query(
      `INSERT INTO group_messages (id, group_id, sender_id, content, is_system) VALUES ($1, $2, $3, $4, true)`,
      [systemMsgId, groupId, userId, systemContent]
    );
    if (global.io) {
      const systemMessage = {
        id: systemMsgId, group_id: groupId, sender_id: userId, content: systemContent,
        is_system: true, created_at: new Date(), username: adminName,
      };
      global.io.to(`group_${groupId}`).emit('group_message', systemMessage);
      global.io.to(`group_${groupId}`).emit('message_unpinned', { groupId });
    }
    res.json({ message: 'Message désépinglé' });
  } catch (err) {
    console.error('unpinMessage:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ========== RÉCUPÉRER LE MESSAGE ÉPINGLÉ ==========
exports.getPinnedMessage = async (req, res) => {
  const { groupId } = req.params;
  try {
    const result = await pool.query(
      `SELECT gm.*, u.username, u.avatar_url
       FROM groups g
       LEFT JOIN group_messages gm ON g.pinned_message_id = gm.id
       LEFT JOIN users u ON gm.sender_id = u.id
       WHERE g.id = $1`,
      [groupId]
    );
    res.json(result.rows[0] || null);
  } catch (err) {
    console.error('getPinnedMessage:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};