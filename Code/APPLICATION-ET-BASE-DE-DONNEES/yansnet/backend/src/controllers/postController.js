const pool = require('../config/database');
const { v4: uuidv4 } = require('uuid');
const { notify } = require('./notificationController');

// GET /api/posts/feed — Fil d'actualité avec galerie média
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
              EXISTS(SELECT 1 FROM follows WHERE follower_id = $1 AND following_id = p.user_id) as is_following
       FROM posts p
       JOIN users u ON p.user_id = u.id
       WHERE p.is_deleted = false
       ORDER BY p.created_at DESC
       LIMIT $2 OFFSET $3`,
      [userId, limit, offset]
    );
    
    // Parse la galerie JSON pour chaque post
    const posts = result.rows.map(post => {
      let mediaGallery = [];
      let mediaTypes = [];
      
      // Gérer media_gallery (déjà parsé par PostgreSQL)
      if (post.media_gallery) {
        // Si c'est déjà un tableau (PostgreSQL JSON)
        if (Array.isArray(post.media_gallery)) {
          mediaGallery = post.media_gallery;
        }
        // Si c'est une chaîne JSON
        else if (typeof post.media_gallery === 'string') {
          try {
            mediaGallery = JSON.parse(post.media_gallery);
          } catch(e) {
            mediaGallery = [];
          }
        }
        // Si c'est un objet
        else if (typeof post.media_gallery === 'object') {
          mediaGallery = Object.values(post.media_gallery);
        }
      }
      
      // Fallback sur media_url si media_gallery est vide
      if (mediaGallery.length === 0 && post.media_url) {
        mediaGallery = [post.media_url];
      }
      
      // Déterminer les types de médias
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
        media_types: mediaTypes
      };
    });
    
    res.json(posts);
  } catch (err) {
    console.error('Erreur getFeed:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// POST /api/posts — Créer une publication (avec support de plusieurs médias)
exports.createPost = async (req, res) => {
  const { content, tags, is_institutional } = req.body;
  const userId = req.user.userId;
  const role = req.user.role;

  let files = req.files;
  if (!files && req.file) files = [req.file];
  if (!files) files = [];

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
    res.status(201).json({ id: postId, message: 'Publication créée' });
  } catch (err) {
    console.error('Erreur createPost:', err.message);
    if (err.message.includes('column "media_gallery" does not exist')) {
      console.error('Ajoutez la colonne media_gallery : ALTER TABLE posts ADD COLUMN media_gallery JSON;');
    }
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// GET /api/posts/:postId — Détail d'une publication
exports.getPost = async (req, res) => {
  const { postId } = req.params;
  const userId = req.user.userId;
  try {
    const result = await pool.query(
      `SELECT p.*, u.username, u.avatar_url, u.full_name,
              (SELECT COUNT(*) FROM likes WHERE post_id = p.id) AS like_count,
              (SELECT COUNT(*) FROM comments WHERE post_id = p.id AND is_deleted = false) AS comment_count,
              EXISTS(SELECT 1 FROM likes WHERE post_id = p.id AND user_id = $2) AS user_liked
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
      if (Array.isArray(post.media_gallery)) {
        post.media_gallery = post.media_gallery;
      } else if (typeof post.media_gallery === 'string') {
        post.media_gallery = JSON.parse(post.media_gallery);
      } else if (typeof post.media_gallery === 'object') {
        post.media_gallery = Object.values(post.media_gallery);
      }
    } else {
      post.media_gallery = post.media_url ? [post.media_url] : [];
    }
    res.json(post);
  } catch (err) {
    console.error('Erreur getPost:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// GET /api/posts/:postId/comments
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

// GET /api/comments/:commentId/replies
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

// POST /api/posts/:postId/comment
exports.commentPost = async (req, res) => {
  const { postId } = req.params;
  const { content, parentId } = req.body;
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
      `INSERT INTO comments (id, user_id, post_id, content, parent_id) VALUES ($1, $2, $3, $4, $5)`,
      [commentId, userId, postId, content.trim(), parentId || null]
    );
    
    const post = await pool.query('SELECT user_id FROM posts WHERE id = $1', [postId]);
    if (post.rows.length && post.rows[0].user_id !== userId) {
      const commenter = await pool.query('SELECT full_name FROM users WHERE id = $1', [userId]);
      await notify(
        post.rows[0].user_id,
        'comment',
        `${commenter.rows[0]?.full_name} a commenté votre publication.`,
        postId
      );
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

// POST /api/comments/:commentId/like
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

// DELETE /api/comments/:commentId/like
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

// POST /api/posts/:postId/like
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
          postId
        );
      }
    }
    res.json({ message: 'Like ajouté' });
  } catch (err) {
    console.error('Erreur likePost:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// DELETE /api/posts/:postId/like
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

// DELETE /api/posts/:postId
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

// DELETE /api/comments/:commentId
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