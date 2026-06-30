const express = require('express');
const { sendMessage, getConversation, markAsRead, getConversations } = require('../controllers/messageController');
const auth = require('../middleware/auth');
const moderation = require('../middleware/moderation');
const { messageUpload } = require('../middleware/upload');

const router = express.Router();

router.post('/', auth, messageUpload, moderation, sendMessage);
router.get('/conversations/list', auth, getConversations);
router.get('/:userId', auth, getConversation);
router.put('/:messageId/read', auth, markAsRead);

module.exports = router;