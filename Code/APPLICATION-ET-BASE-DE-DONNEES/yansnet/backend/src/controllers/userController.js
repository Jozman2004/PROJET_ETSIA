const pool = require('../config/database');
const { notify } = require('./notificationController');
const path = require('path');
const fs = require('fs');

// GET /api/users/:userId
exports.getProfile = async (req, res) => {
  const { userId } = req.params;
  if (!userId) return res.status(400).json({ error: 'ID manquant' });
  try {
    const result = await pool.query(
      `SELECT id, username, full_name, bio, avatar_url, promotion, residence, filiere, role, created_at,
              (SELECT COUNT(*) FROM posts WHERE user_id = $1 AND is_deleted = false) AS post_count,
              (SELECT COUNT(*) FROM follows WHERE following_id = $1) AS followers_count,
              (SELECT COUNT(*) FROM follows WHERE follower_id = $1) AS following_count
       FROM users WHERE id = $1 AND is_active = true`,
      [userId]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: 'Utilisateur non trouvé' });
    res.json(result.rows[0]);
  } catch (err) {
    console.error('getProfile:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// GET /api/users/me
exports.getMe = async (req, res) => {
  req.params.userId = req.user.userId;
  exports.getProfile(req, res);
};

// PUT /api/users/me
exports.updateProfile = async (req, res) => {
  const { full_name, bio, username } = req.body;
  const userId = req.user.userId;
  try {
    if (username) {
      const existing = await pool.query('SELECT id FROM users WHERE username = $1 AND id != $2', [username, userId]);
      if (existing.rows.length > 0)
        return res.status(400).json({ error: 'Nom d\'utilisateur déjà pris' });
    }
    const result = await pool.query(
      `UPDATE users SET full_name = COALESCE($1, full_name), bio = COALESCE($2, bio),
         username = COALESCE($3, username), updated_at = NOW()
       WHERE id = $4
       RETURNING id, username, full_name, bio, avatar_url, promotion, residence, filiere, role`,
      [full_name || null, bio !== undefined ? bio : null, username || null, userId]
    );
    res.json(result.rows[0]);
  } catch (err) {
    console.error('updateProfile:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// PUT /api/users/me/avatar - Version simplifiée
exports.updateAvatar = async (req, res) => {
  console.log('Tentative changement avatar');
  
  if (!req.file) {
    return res.status(400).json({ error: 'Aucune image sélectionnée' });
  }
  
  const userId = req.user.userId;
  const avatarUrl = `/uploads/${req.file.filename}`;
  
  try {
    // Supprimer l'ancien avatar s'il existe
    const old = await pool.query('SELECT avatar_url FROM users WHERE id = $1', [userId]);
    if (old.rows[0]?.avatar_url) {
      const oldPath = path.join(__dirname, '../../', old.rows[0].avatar_url);
      if (fs.existsSync(oldPath)) {
        fs.unlinkSync(oldPath);
      }
    }
    
    await pool.query('UPDATE users SET avatar_url = $1 WHERE id = $2', [avatarUrl, userId]);
    res.json({ avatar_url: avatarUrl, message: 'Photo de profil mise à jour' });
  } catch (err) {
    console.error('Erreur updateAvatar:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// DELETE /api/users/me/avatar - Supprimer l'avatar
exports.deleteAvatar = async (req, res) => {
  console.log('Tentative suppression avatar');
  const userId = req.user.userId;
  
  try {
    // Récupérer l'ancien avatar
    const old = await pool.query('SELECT avatar_url FROM users WHERE id = $1', [userId]);
    if (old.rows[0]?.avatar_url) {
      const oldPath = path.join(__dirname, '../../', old.rows[0].avatar_url);
      if (fs.existsSync(oldPath)) {
        fs.unlinkSync(oldPath);
        console.log('Ancien avatar supprimé du disque');
      }
    }
    
    // Mettre avatar_url à NULL
    await pool.query('UPDATE users SET avatar_url = NULL WHERE id = $1', [userId]);
    res.json({ message: 'Photo de profil supprimée' });
  } catch (err) {
    console.error('Erreur deleteAvatar:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// GET /api/users/:userId/posts
exports.getUserPosts = async (req, res) => {
  const { userId } = req.params;
  const limit = parseInt(req.query.limit, 10) || 20;
  const offset = parseInt(req.query.offset, 10) || 0;
  const currentUserId = req.user.userId;
  if (!userId) return res.status(400).json({ error: 'ID manquant' });
  try {
    const result = await pool.query(
      `SELECT p.*, u.username, u.avatar_url, u.full_name,
              (SELECT COUNT(*) FROM likes WHERE post_id = p.id) AS like_count,
              (SELECT COUNT(*) FROM comments WHERE post_id = p.id AND is_deleted = false) AS comment_count,
              EXISTS(SELECT 1 FROM likes WHERE post_id = p.id AND user_id = $3) AS user_liked
       FROM posts p JOIN users u ON p.user_id = u.id
       WHERE p.user_id = $1 AND p.is_deleted = false
       ORDER BY p.created_at DESC LIMIT $2 OFFSET $4`,
      [userId, limit, currentUserId, offset]
    );
    res.json(result.rows);
  } catch (err) {
    console.error('getUserPosts:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// GET /api/users/:userId/followers
exports.getFollowers = async (req, res) => {
  const { userId } = req.params;
  if (!userId) return res.status(400).json({ error: 'ID manquant' });
  try {
    const result = await pool.query(
      `SELECT u.id, u.username, u.full_name, u.avatar_url, u.filiere
       FROM follows f JOIN users u ON f.follower_id = u.id
       WHERE f.following_id = $1 ORDER BY f.created_at DESC LIMIT 100`,
      [userId]
    );
    res.json(result.rows);
  } catch (err) {
    console.error('getFollowers:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// GET /api/users/:userId/following
exports.getFollowing = async (req, res) => {
  const { userId } = req.params;
  if (!userId) return res.status(400).json({ error: 'ID manquant' });
  try {
    const result = await pool.query(
      `SELECT u.id, u.username, u.full_name, u.avatar_url, u.filiere
       FROM follows f JOIN users u ON f.following_id = u.id
       WHERE f.follower_id = $1 ORDER BY f.created_at DESC LIMIT 100`,
      [userId]
    );
    res.json(result.rows);
  } catch (err) {
    console.error('getFollowing:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// GET /api/users/:userId/follow-status
exports.getFollowStatus = async (req, res) => {
  const { userId } = req.params;
  const followerId = req.user.userId;
  if (!userId) return res.status(400).json({ error: 'ID manquant' });
  try {
    const result = await pool.query(
      'SELECT 1 FROM follows WHERE follower_id = $1 AND following_id = $2',
      [followerId, userId]
    );
    res.json({ following: result.rows.length > 0 });
  } catch (err) {
    console.error('getFollowStatus:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// POST /api/users/:userId/follow
exports.followUser = async (req, res) => {
  const { userId } = req.params;
  const followerId = req.user.userId;
  if (!userId) return res.status(400).json({ error: 'ID manquant' });
  if (followerId === userId) return res.status(400).json({ error: 'Vous ne pouvez pas vous suivre vous-même' });
  try {
    await pool.query(
      'INSERT INTO follows (follower_id, following_id) VALUES ($1, $2) ON CONFLICT DO NOTHING',
      [followerId, userId]
    );
    const follower = await pool.query('SELECT full_name FROM users WHERE id = $1', [followerId]);
    await notify(userId, 'new_follower', `${follower.rows[0]?.full_name} a commencé à vous suivre.`, followerId);
    res.json({ message: 'Abonnement réussi' });
  } catch (err) {
    console.error('followUser:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// DELETE /api/users/:userId/follow
exports.unfollowUser = async (req, res) => {
  const { userId } = req.params;
  const followerId = req.user.userId;
  if (!userId) return res.status(400).json({ error: 'ID manquant' });
  try {
    await pool.query('DELETE FROM follows WHERE follower_id = $1 AND following_id = $2', [followerId, userId]);
    res.json({ message: 'Désabonnement réussi' });
  } catch (err) {
    console.error('unfollowUser:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// GET /api/users/suggestions
exports.getSuggestions = async (req, res) => {
  const userId = req.user.userId;
  try {
    const result = await pool.query(
      `SELECT u.id, u.username, u.full_name, u.avatar_url, u.filiere,
              (SELECT COUNT(*) FROM follows WHERE following_id = u.id) as followers_count,
              EXISTS(SELECT 1 FROM follows WHERE follower_id = $1 AND following_id = u.id) as is_following
       FROM users u
       WHERE u.id != $1 AND u.is_active = true
         AND u.id NOT IN (SELECT following_id FROM follows WHERE follower_id = $1)
       ORDER BY followers_count DESC
       LIMIT 20`,
      [userId]
    );
    res.json(result.rows);
  } catch (err) {
    console.error('getSuggestions:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// GET /api/users/search?q=...
exports.searchUsers = async (req, res) => {
  const { q } = req.query;
  const userId = req.user.userId;
  if (!q || q.trim() === '') return res.json([]);
  try {
    const result = await pool.query(
      `SELECT u.id, u.username, u.full_name, u.avatar_url, u.filiere,
              (SELECT COUNT(*) FROM follows WHERE following_id = u.id) as followers_count,
              EXISTS(SELECT 1 FROM follows WHERE follower_id = $1 AND following_id = u.id) as is_following
       FROM users u
       WHERE (u.full_name ILIKE $2 OR u.username ILIKE $2) AND u.id != $1 AND u.is_active = true
       LIMIT 20`,
      [userId, `%${q.trim()}%`]
    );
    res.json(result.rows);
  } catch (err) {
    console.error('searchUsers:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// GET /api/users/all — Liste tous les membres (sauf soi-même)
exports.getAllMembers = async (req, res) => {
  const userId = req.user.userId;
  try {
    const result = await pool.query(
      `SELECT u.id, u.username, u.full_name, u.avatar_url, u.filiere, u.promotion,
              (SELECT COUNT(*) FROM follows WHERE following_id = u.id) as followers_count,
              EXISTS(SELECT 1 FROM follows WHERE follower_id = $1 AND following_id = u.id) as is_following
       FROM users u
       WHERE u.id != $1 AND u.is_active = true
       ORDER BY u.created_at DESC`,
      [userId]
    );
    res.json(result.rows);
  } catch (err) {
    console.error('getAllMembers:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};