// src/routes/postRoutes.js
const express = require('express');
const router = express.Router();
const postController = require('../controllers/postController');
const auth = require('../middleware/auth');
const { multipleUpload } = require('../middleware/upload');
const moderation = require('../middleware/moderation');

// Routes principales
router.get('/feed', auth, postController.getFeed);
router.post('/', auth, multipleUpload, moderation, postController.createPost);

// Routes avec :postId
router.get('/:postId', auth, postController.getPost);
router.get('/:postId/comments', auth, postController.getComments);
router.post('/:postId/like', auth, postController.likePost);
router.delete('/:postId/like', auth, postController.unlikePost);
router.post('/:postId/comment', auth, moderation, postController.commentPost);
router.delete('/:postId', auth, postController.deletePost);

module.exports = router;