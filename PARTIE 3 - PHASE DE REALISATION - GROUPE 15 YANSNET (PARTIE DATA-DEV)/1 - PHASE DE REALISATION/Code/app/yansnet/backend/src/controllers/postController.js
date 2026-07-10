// src/controllers/postController.js
const pool = require('../config/database');
const { v4: uuidv4 } = require('uuid');
const { notify } = require('./notificationController');

// ─── Utilitaire : envoyer des notifications pour les mentions ───────────────
async function notifyMentions(mentionsCsv, postId, commentId, actorId, actorName, type = 'mention', targetType = 'post') {
  if (!mentionsCsv) return;
  const mentions = mentionsCsv.split(',').map(id => id.trim()).filter(id => id && id !== '');
  if (mentions.length === 0) return;

  const message = commentId
    ? `${actorName} vous a mentionné dans un commentaire.`
    : `${actorName} vous a mentionné dans une publication.`;
  const referenceId = commentId || postId;

  for (const userId of mentions) {
    if (userId === actorId) continue;
    try {
      await notify(userId, type, message, referenceId, targetType);
    } catch (err) {
      console.error(`Erreur notification mention pour ${userId} :`, err.message);
    }
  }
}

// ============================================================
// GET /api/posts/feed – Fil d'actualité complet
// ============================================================
exports.getFeed = async (req, res) => {
  const userId = req.user.userId;
  const limit = parseInt(req.query.limit, 10) || 20;
  const offset = parseInt(req.query.offset, 10) || 0;

  try {
    const result = await pool.query(
      `SELECT p.*, u.username, u.avatar_url, u.full_name,
              (SELECT COUNT(*) FROM likes WHERE post_id = p.id) AS like_count,
              (SELECT COUNT(*) FROM comments WHERE post_id = p.id AND is_deleted = false) AS comment_count,
              EXISTS(SELECT 1 FROM likes WHERE post_id = p.id AND user_id = $1) AS user_liked,
              EXISTS(SELECT 1 FROM follows WHERE follower_id = $1 AND following_id = p.user_id) as is_following,
              (SELECT COUNT(*) FROM reposts WHERE post_id = p.id) AS repost_count,
              EXISTS(SELECT 1 FROM reposts WHERE post_id = p.id AND user_id = $1) AS user_reposted
       FROM posts p
       JOIN users u ON p.user_id = u.id
       WHERE p.is_deleted = false
       ORDER BY p.created_at DESC
       LIMIT $2 OFFSET $3`,
      [userId, limit, offset]
    );

    const posts = result.rows.map(post => {
      let mediaGallery = [];
      let mediaTypes = [];

      if (post.media_gallery) {
        if (Array.isArray(post.media_gallery)) {
          mediaGallery = post.media_gallery;
        } else if (typeof post.media_gallery === 'string') {
          try { mediaGallery = JSON.parse(post.media_gallery); } catch(e) { mediaGallery = []; }
        } else if (typeof post.media_gallery === 'object') {
          mediaGallery = Object.values(post.media_gallery);
        }
      }

      if (mediaGallery.length === 0 && post.media_url) {
        mediaGallery = [post.media_url];
      }

      if (mediaGallery.length > 0) {
        if (post.media_type && post.media_type !== 'none') {
          mediaTypes = mediaGallery.map(() => post.media_type);
        } else {
          mediaTypes = mediaGallery.map(url => {
            const ext = url.split('.').pop().toLowerCase();
            return ['mp4', 'mov', 'avi', 'mkv'].includes(ext) ? 'video' : 'photo';
          });
        }
      }

      return {
        ...post,
        media_gallery: mediaGallery,
        media_types: mediaTypes,
        shared_post_id: post.shared_post_id || null,
        shared_post: null,
        liked_by_friends: [],
        reposted_by_friends: []
      };
    });

    res.json(posts);
  } catch (err) {
    console.error('Erreur getFeed:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ============================================================
// POST /api/posts – Créer une publication (avec mentions et fichiers refusés)
// ============================================================
exports.createPost = async (req, res) => {
  const { content, tags, is_institutional, mentions } = req.body;
  const userId = req.user.userId;
  const role = req.user.role;

  // Récupération des fichiers acceptés
  let files = req.files || [];
  if (!Array.isArray(files)) files = [files];
  files = files.filter(f => f && f.size > 0);

  // Fichiers refusés (fournis par le middleware de modération)
  const refusedFiles = req.refusedFiles || [];

  // Si aucun fichier accepté et pas de contenu texte → erreur
  if (files.length === 0 && !content) {
    return res.status(400).json({ error: 'Aucun contenu valide à publier.' });
  }

  const mediaUrls = [];
  const mediaTypes = [];
  const mediaSizes = [];

  for (const file of files) {
    const url = `/uploads/${file.filename}`;
    const type = file.mimetype.startsWith('image') ? 'photo' : 'video';
    mediaUrls.push(url);
    mediaTypes.push(type);
    mediaSizes.push(file.size);
  }

  const primaryMedia = mediaUrls[0] || null;
  const primaryType = mediaTypes[0] || 'none';
  const primarySize = mediaSizes[0] || 0;
  const gallery = mediaUrls.length > 0 ? JSON.stringify(mediaUrls) : null;

  try {
    const postId = uuidv4();
    const tagsArr = tags ? (Array.isArray(tags) ? tags : tags.split(',').map(t => t.trim())) : [];
    const institutional = ['admin', 'moderator'].includes(role) && is_institutional === 'true';

    await pool.query(
      `INSERT INTO posts (id, user_id, content, media_url, media_type, media_size, tags, is_institutional, media_gallery)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
      [postId, userId, content, primaryMedia, primaryType, primarySize, tagsArr, institutional, gallery]
    );

    // Notifier les mentions
    if (mentions) {
      const actor = await pool.query('SELECT full_name FROM users WHERE id = $1', [userId]);
      const actorName = actor.rows[0]?.full_name || 'Quelqu\'un';
      await notifyMentions(mentions, postId, null, userId, actorName, 'mention', 'post');
    }

    // Construction de la réponse avec gestion des fichiers refusés
    const response = {
      id: postId,
      message: 'Publication créée',
    };

    if (refusedFiles.length > 0) {
      response.refused = {
        count: refusedFiles.length,
        files: refusedFiles.map(f => ({
          filename: f.filename,
          reason: f.reason || 'Contenu inapproprié',
          suggestion: f.suggestion || ''
        }))
      };
    }

    if (req.moderationWarning) {
      response.warning = req.moderationWarning;
    }

    res.status(201).json(response);
  } catch (err) {
    console.error('Erreur createPost:', err.message);
    if (err.message.includes('column "media_gallery" does not exist')) {
      console.error('Ajoutez la colonne media_gallery : ALTER TABLE posts ADD COLUMN media_gallery JSON;');
    }
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ============================================================
// GET /api/posts/:postId – Détail d'une publication
// ============================================================
exports.getPost = async (req, res) => {
  const { postId } = req.params;
  const userId = req.user.userId;
  try {
    const result = await pool.query(
      `SELECT p.*, u.username, u.avatar_url, u.full_name,
              (SELECT COUNT(*) FROM likes WHERE post_id = p.id) AS like_count,
              (SELECT COUNT(*) FROM comments WHERE post_id = p.id AND is_deleted = false) AS comment_count,
              EXISTS(SELECT 1 FROM likes WHERE post_id = p.id AND user_id = $2) AS user_liked,
              (SELECT COUNT(*) FROM reposts WHERE post_id = p.id) AS repost_count,
              EXISTS(SELECT 1 FROM reposts WHERE post_id = p.id AND user_id = $2) AS user_reposted
       FROM posts p
       JOIN users u ON p.user_id = u.id
       WHERE p.id = $1 AND p.is_deleted = false`,
      [postId, userId]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Post introuvable' });
    }
    const post = result.rows[0];

    if (post.media_gallery) {
      if (Array.isArray(post.media_gallery)) post.media_gallery = post.media_gallery;
      else if (typeof post.media_gallery === 'string') post.media_gallery = JSON.parse(post.media_gallery);
      else if (typeof post.media_gallery === 'object') post.media_gallery = Object.values(post.media_gallery);
    } else {
      post.media_gallery = post.media_url ? [post.media_url] : [];
    }

    post.shared_post = null;
    post.liked_by_friends = [];
    post.reposted_by_friends = [];

    res.json(post);
  } catch (err) {
    console.error('Erreur getPost:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ============================================================
// GET /api/posts/:postId/comments
// ============================================================
exports.getComments = async (req, res) => {
  const { postId } = req.params;
  const userId = req.user.userId;

  console.log('getComments - postId reçu:', postId);

  if (!postId || postId === '' || postId === 'null' || postId === 'undefined') {
    console.error('postId invalide');
    return res.status(400).json({ error: 'ID de post invalide' });
  }

  try {
    const result = await pool.query(
      `SELECT c.*, u.username, u.avatar_url, u.full_name,
              COALESCE((SELECT COUNT(*) FROM comment_likes WHERE comment_id = c.id), 0) as like_count,
              COALESCE((SELECT EXISTS(SELECT 1 FROM comment_likes WHERE comment_id = c.id AND user_id = $2)), false) as user_liked,
              COALESCE((SELECT COUNT(*) FROM comments WHERE parent_id = c.id), 0) as reply_count
       FROM comments c
       JOIN users u ON c.user_id = u.id
       WHERE c.post_id = $1
       ORDER BY c.created_at ASC`,
      [postId, userId]
    );

    console.log('Commentaires trouvés:', result.rows.length);
    res.json(result.rows);
  } catch (err) {
    console.error('Erreur SQL getComments:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ============================================================
// GET /api/comments/:commentId/replies
// ============================================================
exports.getReplies = async (req, res) => {
  const { commentId } = req.params;
  const userId = req.user.userId;

  if (!commentId || commentId === '' || commentId === 'null') {
    return res.status(400).json({ error: 'ID de commentaire invalide' });
  }

  try {
    const result = await pool.query(
      `SELECT c.*, u.username, u.avatar_url, u.full_name,
              COALESCE((SELECT COUNT(*) FROM comment_likes WHERE comment_id = c.id), 0) as like_count,
              COALESCE((SELECT EXISTS(SELECT 1 FROM comment_likes WHERE comment_id = c.id AND user_id = $2)), false) as user_liked
       FROM comments c
       JOIN users u ON c.user_id = u.id
       WHERE c.parent_id = $1
       ORDER BY c.created_at ASC`,
      [commentId, userId]
    );
    res.json(result.rows);
  } catch (err) {
    console.error('Erreur getReplies:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ============================================================
// POST /api/posts/:postId/comment (avec mentions)
// ============================================================
exports.commentPost = async (req, res) => {
  const { postId } = req.params;
  const { content, parentId, mentions } = req.body;
  const userId = req.user.userId;

  if (!postId || postId === '' || postId === 'null') {
    return res.status(400).json({ error: 'ID de post invalide' });
  }
  if (!content?.trim()) {
    return res.status(400).json({ error: 'Commentaire vide' });
  }
  if (content.length > 500) {
    return res.status(400).json({ error: 'Max 500 caractères' });
  }

  try {
    const commentId = uuidv4();
    await pool.query(
      `INSERT INTO comments (id, user_id, post_id, content, parent_id)
       VALUES ($1, $2, $3, $4, $5)`,
      [commentId, userId, postId, content.trim(), parentId || null]
    );

    // Notification à l'auteur du post
    const post = await pool.query('SELECT user_id FROM posts WHERE id = $1', [postId]);
    if (post.rows.length && post.rows[0].user_id !== userId) {
      const commenter = await pool.query('SELECT full_name FROM users WHERE id = $1', [userId]);
      await notify(
        post.rows[0].user_id,
        'comment',
        `${commenter.rows[0]?.full_name} a commenté votre publication.`,
        postId,
        'post' // targetType
      );
    }

    // Notifier les mentions dans le commentaire
    if (mentions) {
      const actor = await pool.query('SELECT full_name FROM users WHERE id = $1', [userId]);
      const actorName = actor.rows[0]?.full_name || 'Quelqu\'un';
      await notifyMentions(mentions, postId, commentId, userId, actorName, 'mention', 'post');
    }

    const newComment = await pool.query(
      `SELECT c.*, u.username, u.avatar_url, u.full_name,
              COALESCE((SELECT COUNT(*) FROM comment_likes WHERE comment_id = c.id), 0) as like_count,
              COALESCE((SELECT EXISTS(SELECT 1 FROM comment_likes WHERE comment_id = c.id AND user_id = $2)), false) as user_liked,
              0 as reply_count
       FROM comments c
       JOIN users u ON c.user_id = u.id
       WHERE c.id = $1`,
      [commentId, userId]
    );
    res.status(201).json(newComment.rows[0]);
  } catch (err) {
    console.error('Erreur commentPost:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ============================================================
// POST /api/comments/:commentId/like
// ============================================================
exports.likeComment = async (req, res) => {
  const { commentId } = req.params;
  const userId = req.user.userId;

  console.log('likeComment appelé - commentId:', commentId);

  if (!commentId || commentId === '' || commentId === 'null') {
    return res.status(400).json({ error: 'ID de commentaire invalide' });
  }

  try {
    await pool.query(
      `INSERT INTO comment_likes (user_id, comment_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
      [userId, commentId]
    );
    res.json({ message: 'Like ajouté' });
  } catch (err) {
    console.error('Erreur likeComment:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ============================================================
// DELETE /api/comments/:commentId/like
// ============================================================
exports.unlikeComment = async (req, res) => {
  const { commentId } = req.params;
  const userId = req.user.userId;

  if (!commentId || commentId === '' || commentId === 'null') {
    return res.status(400).json({ error: 'ID de commentaire invalide' });
  }

  try {
    await pool.query(
      `DELETE FROM comment_likes WHERE user_id = $1 AND comment_id = $2`,
      [userId, commentId]
    );
    res.json({ message: 'Like retiré' });
  } catch (err) {
    console.error('Erreur unlikeComment:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ============================================================
// POST /api/posts/:postId/like
// ============================================================
exports.likePost = async (req, res) => {
  const { postId } = req.params;
  const userId = req.user.userId;
  try {
    const insert = await pool.query(
      `INSERT INTO likes (user_id, post_id) VALUES ($1, $2) ON CONFLICT DO NOTHING RETURNING *`,
      [userId, postId]
    );
    if (insert.rows.length > 0) {
      const post = await pool.query('SELECT user_id FROM posts WHERE id = $1', [postId]);
      if (post.rows.length && post.rows[0].user_id !== userId) {
        const liker = await pool.query('SELECT full_name FROM users WHERE id = $1', [userId]);
        await notify(
          post.rows[0].user_id,
          'like',
          `${liker.rows[0]?.full_name} a aimé votre publication.`,
          postId,
          'post'
        );
      }
    }
    res.json({ message: 'Like ajouté' });
  } catch (err) {
    console.error('Erreur likePost:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ============================================================
// DELETE /api/posts/:postId/like
// ============================================================
exports.unlikePost = async (req, res) => {
  const { postId } = req.params;
  const userId = req.user.userId;
  try {
    await pool.query('DELETE FROM likes WHERE user_id = $1 AND post_id = $2', [userId, postId]);
    res.json({ message: 'Like retiré' });
  } catch (err) {
    console.error('Erreur unlikePost:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ============================================================
// DELETE /api/posts/:postId – Suppression logique
// ============================================================
exports.deletePost = async (req, res) => {
  const { postId } = req.params;
  const { userId, role } = req.user;
  try {
    const post = await pool.query('SELECT user_id FROM posts WHERE id = $1', [postId]);
    if (post.rows.length === 0) {
      return res.status(404).json({ error: 'Post introuvable' });
    }
    if (post.rows[0].user_id !== userId && !['admin', 'moderator'].includes(role)) {
      return res.status(403).json({ error: 'Permission refusée' });
    }
    await pool.query('UPDATE posts SET is_deleted = true WHERE id = $1', [postId]);
    res.json({ message: 'Post supprimé' });
  } catch (err) {
    console.error('Erreur deletePost:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ============================================================
// DELETE /api/comments/:commentId – Suppression logique
// ============================================================
exports.deleteComment = async (req, res) => {
  const { commentId } = req.params;
  const { userId, role } = req.user;
  try {
    const comment = await pool.query('SELECT user_id FROM comments WHERE id = $1', [commentId]);
    if (comment.rows.length === 0) {
      return res.status(404).json({ error: 'Commentaire introuvable' });
    }
    if (comment.rows[0].user_id !== userId && !['admin', 'moderator'].includes(role)) {
      return res.status(403).json({ error: 'Permission refusée' });
    }
    await pool.query('UPDATE comments SET is_deleted = true WHERE id = $1', [commentId]);
    res.json({ message: 'Commentaire supprimé' });
  } catch (err) {
    console.error('Erreur deleteComment:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ============================================================
// GET /api/posts/:postId/likers – Liste des utilisateurs ayant liké
// ============================================================
exports.getLikers = async (req, res) => {
  const { postId } = req.params;
  try {
    const result = await pool.query(
      `SELECT u.id as user_id, u.full_name, u.avatar_url
       FROM likes l
       JOIN users u ON l.user_id = u.id
       WHERE l.post_id = $1
       ORDER BY l.created_at DESC
       LIMIT 5`,
      [postId]
    );
    res.json(result.rows);
  } catch (err) {
    console.error('Erreur getLikers:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ============================================================
// POST /api/posts/:postId/repost – Reposter (ou mettre à jour le commentaire)
// ============================================================
exports.repost = async (req, res) => {
  const { postId } = req.params;
  const userId = req.user.userId;
  const { comment } = req.body;

  try {
    const postExists = await pool.query('SELECT id FROM posts WHERE id = $1 AND is_deleted = false', [postId]);
    if (postExists.rows.length === 0) {
      return res.status(404).json({ error: 'Post introuvable' });
    }

    const repostId = uuidv4();
    await pool.query(
      `INSERT INTO reposts (id, user_id, post_id, comment)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (user_id, post_id) DO UPDATE SET comment = EXCLUDED.comment, created_at = CURRENT_TIMESTAMP`,
      [repostId, userId, postId, comment || null]
    );

    res.status(201).json({ message: 'Post republié avec succès' });
  } catch (err) {
    console.error('Erreur repost:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ============================================================
// DELETE /api/posts/:postId/repost – Retirer un repost
// ============================================================
exports.unrepost = async (req, res) => {
  const { postId } = req.params;
  const userId = req.user.userId;
  try {
    await pool.query('DELETE FROM reposts WHERE user_id = $1 AND post_id = $2', [userId, postId]);
    res.json({ message: 'Repost retiré' });
  } catch (err) {
    console.error('Erreur unrepost:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// ============================================================
// GET /api/posts/:postId/reposts – Liste des reposts
// ============================================================
exports.getReposts = async (req, res) => {
  const { postId } = req.params;
  try {
    const result = await pool.query(
      `SELECT r.*, u.full_name, u.username, u.avatar_url
       FROM reposts r
       JOIN users u ON r.user_id = u.id
       WHERE r.post_id = $1
       ORDER BY r.created_at DESC`,
      [postId]
    );
    res.json(result.rows);
  } catch (err) {
    console.error('Erreur getReposts:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};