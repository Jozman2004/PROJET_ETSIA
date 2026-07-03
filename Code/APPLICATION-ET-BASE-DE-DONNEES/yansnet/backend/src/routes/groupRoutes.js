// src/routes/groupRoutes.js
const express = require('express');
const {
  createGroup, getMyGroups, getGroupDetails,
  addMembers, removeMember, updateGroup,
  promoteMember, deleteGroup,
  getGroupMessages, sendGroupMessage,
  searchUsers, pinMessage, unpinMessage, getPinnedMessage,
} = require('../controllers/groupController');
const auth = require('../middleware/auth');
const moderation = require('../middleware/moderation');
const { messageUpload } = require('../middleware/upload');

const router = express.Router();

// Recherche d'utilisateurs
router.get('/users/search', auth, searchUsers);

// Groupes
router.post('/', auth, createGroup);
router.get('/', auth, getMyGroups);
router.get('/:groupId', auth, getGroupDetails);
router.patch('/:groupId', auth, updateGroup);
router.delete('/:groupId', auth, deleteGroup);

// Épinglage
router.patch('/:groupId/messages/:messageId/pin', auth, pinMessage);
router.delete('/:groupId/messages/:messageId/pin', auth, unpinMessage);
router.get('/:groupId/pinned-message', auth, getPinnedMessage);

// Membres
router.post('/:groupId/members', auth, addMembers);
router.delete('/:groupId/members/:memberId', auth, removeMember);
router.patch('/:groupId/members/:memberId/promote', auth, promoteMember);

// Messages
router.get('/:groupId/messages', auth, getGroupMessages);
router.post('/:groupId/messages', auth, messageUpload, moderation, sendGroupMessage);

module.exports = router;