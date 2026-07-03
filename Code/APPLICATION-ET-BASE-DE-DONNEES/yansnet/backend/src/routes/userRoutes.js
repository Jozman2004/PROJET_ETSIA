const express = require('express');
const router = express.Router();
const userController = require('../controllers/userController');
const auth = require('../middleware/auth');
const { upload } = require('../middleware/upload');

// Routes spécifiques (sans paramètre) DOIVENT être avant les routes avec paramètres
router.get('/me', auth, userController.getMe);
router.put('/me', auth, userController.updateProfile);
router.put('/me/avatar', auth, upload.single('media'), userController.updateAvatar);

router.get('/all', auth, userController.getAllMembers);        // ← AVANT /:userId
router.get('/suggestions', auth, userController.getSuggestions);
router.get('/search', auth, userController.searchUsers);

// Routes avec paramètres (:userId)
router.get('/:userId', auth, userController.getProfile);
router.get('/:userId/posts', auth, userController.getUserPosts);
router.get('/:userId/followers', auth, userController.getFollowers);
router.get('/:userId/following', auth, userController.getFollowing);
router.get('/:userId/follow-status', auth, userController.getFollowStatus);

router.post('/:userId/follow', auth, userController.followUser);
router.delete('/:userId/follow', auth, userController.unfollowUser);
router.delete('/me/avatar', auth, userController.deleteAvatar);

module.exports = router;