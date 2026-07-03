// src/routes/commentRoutes.js
const express = require('express');
const router = express.Router();
const pool = require('../config/database');
const auth = require('../middleware/auth');

// POST /api/comments/:commentId/like — Liker un commentaire
router.post('/:commentId/like', auth, async (req, res) => {
  const { commentId } = req.params;
  const userId = req.user.userId;
  
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
});

// DELETE /api/comments/:commentId/like — Retirer un like
router.delete('/:commentId/like', auth, async (req, res) => {
  const { commentId } = req.params;
  const userId = req.user.userId;
  
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
});

module.exports = router;