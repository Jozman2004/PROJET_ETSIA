const express = require('express');
const router = express.Router();
const postController = require('../controllers/postController');
const auth = require('../middleware/auth');
const { multipleUpload } = require('../middleware/upload');
const moderation = require('../middleware/moderation');
const { harcelementCheck } = require('../middleware/dataModeration');
const { trackerAction } = require('../middleware/spamCheck');

// Vérification rapide que tous les middlewares et handlers existent
console.log(' auth:', typeof auth);
console.log('multipleUpload:', typeof multipleUpload);
console.log('moderation:', typeof moderation);
console.log('harcelementCheck:', typeof harcelementCheck);
console.log('trackerAction:', typeof trackerAction);
console.log('postController.getFeed:', typeof postController.getFeed);
console.log('postController.createPost:', typeof postController.createPost);
console.log('postController.getPost:', typeof postController.getPost);
console.log('postController.getComments:', typeof postController.getComments);
console.log('postController.getLikers:', typeof postController.getLikers);
console.log('postController.likePost:', typeof postController.likePost);
console.log('postController.unlikePost:', typeof postController.unlikePost);
console.log('postController.commentPost:', typeof postController.commentPost);
console.log('postController.repost:', typeof postController.repost);
console.log('postController.deletePost:', typeof postController.deletePost);

// ============================================================
// ROUTES PRINCIPALES (sans paramètre)
// ============================================================
router.get('/feed', auth, postController.getFeed);
router.post('/', auth, trackerAction('posts'), multipleUpload, moderation, postController.createPost);

// ============================================================
// ROUTES AVEC :postId
// ============================================================
router.get('/:postId', auth, postController.getPost);
router.get('/:postId/comments', auth, postController.getComments);
router.get('/:postId/likers', auth, postController.getLikers);          // présente uniquement dans le premier code
router.post('/:postId/like', auth, trackerAction('likes'), postController.likePost);
router.delete('/:postId/like', auth, postController.unlikePost);
router.post('/:postId/comment', auth, trackerAction('comments'), moderation, harcelementCheck, postController.commentPost);
router.post('/:postId/repost', auth, postController.repost);             // premier code
router.delete('/:postId/repost', auth, postController.unrepost);        
router.get('/:postId/reposts', auth, postController.getReposts);        
router.delete('/:postId', auth, postController.deletePost);

module.exports = router;