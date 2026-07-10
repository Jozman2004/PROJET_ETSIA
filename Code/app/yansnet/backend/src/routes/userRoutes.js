// src/routes/userRoutes.js
const express = require('express');
const router = express.Router();
const userController = require('../controllers/userController');
const auth = require('../middleware/auth');
const { upload } = require('../middleware/upload'); 

// ============================================================
// ROUTES SPÉCIFIQUES (sans paramètre)
// ============================================================

// Profil et compte
router.get('/me', auth, userController.getMe);
router.put('/me', auth, userController.updateProfile);
router.put('/me/avatar', auth, upload, userController.updateAvatar); 
router.delete('/me/avatar', auth, userController.deleteAvatar);

// Enregistrement du token FCM
router.post('/me/fcm-token', auth, async (req, res) => {
  const { token } = req.body;
  if (!token) {
    return res.status(400).json({ error: 'Token manquant' });
  }
  const userId = req.user.userId;
  try {
    const pool = require('../config/database');
    await pool.query(
      `INSERT INTO fcm_tokens (user_id, token)
       VALUES ($1, $2)
       ON CONFLICT (token) DO UPDATE SET user_id = EXCLUDED.user_id`,
      [userId, token]
    );
    res.json({ message: 'Token FCM enregistré avec succès' });
  } catch (error) {
    console.error('Erreur enregistrement FCM token:', error);
    res.status(500).json({ error: 'Erreur serveur lors de l’enregistrement du token' });
  }
});

// Membres, suggestions, recherche
router.get('/all', auth, userController.getAllMembers);
router.get('/suggestions', auth, userController.getSuggestions);
router.get('/search', auth, userController.searchUsers);
router.get('/follow-status-batch', auth, userController.getFollowStatusBatch);

// ============================================================
// ROUTES AVEC PARAMÈTRE (:userId)
// ============================================================
router.get('/:userId', auth, userController.getProfile);
router.get('/:userId/posts', auth, userController.getUserPosts);
router.get('/:userId/followers', auth, userController.getFollowers);
router.get('/:userId/following', auth, userController.getFollowing);
router.get('/:userId/follow-status', auth, userController.getFollowStatus);

router.post('/:userId/follow', auth, userController.followUser);
router.delete('/:userId/follow', auth, userController.unfollowUser);

// Blocage
router.post('/:userId/block', auth, userController.blockUser);
router.delete('/:userId/block', auth, userController.unblockUser);
router.get('/:userId/block-status', auth, userController.getBlockStatus);

module.exports = router;