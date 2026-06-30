const express = require('express');
const router = express.Router();
const pool = require('../config/database');
const auth = require('../middleware/auth');
const { v4: uuidv4 } = require('uuid');

// Récupérer les réponses d'un commentaire
router.get('/:commentId', auth, async (req, res) => {
  const { commentId } = req.params;
  const userId = req.user.userId;
  
  try {
    const result = await pool.query(
      `SELECT c.*, u.username, u.avatar_url, u.full_name,
              (SELECT COUNT(*) FROM comment_likes WHERE comment_id = c.id) as like_count,
              (SELECT EXISTS(SELECT 1 FROM comment_likes WHERE comment_id = c.id AND user_id = $2)) as user_liked
       FROM comments c
       JOIN users u ON c.user_id = u.id
       WHERE c.parent_id = $1
       ORDER BY c.created_at ASC`,
      [commentId, userId]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Ajouter une réponse à un commentaire
router.post('/:commentId', auth, async (req, res) => {
  const { commentId } = req.params;
  const { content } = req.body;
  const userId = req.user.userId;
  
  if (!content?.trim()) {
    return res.status(400).json({ error: 'Réponse vide' });
  }
  
  try {
    const parent = await pool.query('SELECT post_id FROM comments WHERE id = $1', [commentId]);
    if (parent.rows.length === 0) {
      return res.status(404).json({ error: 'Commentaire parent non trouvé' });
    }
    
    const replyId = uuidv4();
    await pool.query(
      `INSERT INTO comments (id, user_id, post_id, content, parent_id) VALUES ($1, $2, $3, $4, $5)`,
      [replyId, userId, parent.rows[0].post_id, content.trim(), commentId]
    );
    
    const newReply = await pool.query(
      `SELECT c.*, u.username, u.avatar_url, u.full_name, 0 as like_count, false as user_liked
       FROM comments c
       JOIN users u ON c.user_id = u.id
       WHERE c.id = $1`,
      [replyId]
    );
    
    res.status(201).json(newReply.rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;