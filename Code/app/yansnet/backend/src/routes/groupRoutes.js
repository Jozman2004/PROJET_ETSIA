// src/routes/groupRoutes.js
const express = require('express');
const {
  createGroup,
  getMyGroups,
  getGroupDetails,
  addMembers,
  removeMember,
  updateGroup,
  promoteMember,
  deleteGroup,
  getGroupMessages,
  sendGroupMessage,
  searchUsers,
  pinMessage,
  unpinMessage,
  getPinnedMessage,
  deleteGroupMessage,          // Suppression pour tout le monde
  deleteGroupMessageForMe,     // ✅ NOUVEAU : suppression pour moi
  editGroupMessage,            // ✅ NOUVEAU : modification de message
} = require('../controllers/groupController');
const auth = require('../middleware/auth');
const moderation = require('../middleware/moderation');
const { messageUpload } = require('../middleware/upload');

const router = express.Router();

// ============================================================
// RECHERCHE D'UTILISATEURS
// ============================================================
router.get('/users/search', auth, searchUsers);

// ============================================================
// GROUPES
// ============================================================
router.post('/', auth, createGroup);
router.get('/', auth, getMyGroups);
router.get('/:groupId', auth, getGroupDetails);
router.patch('/:groupId', auth, updateGroup);
router.delete('/:groupId', auth, deleteGroup);

// ============================================================
// ÉPINGLAGE
// ============================================================
router.patch('/:groupId/messages/:messageId/pin', auth, pinMessage);
router.delete('/:groupId/messages/:messageId/pin', auth, unpinMessage);
router.get('/:groupId/pinned-message', auth, getPinnedMessage);

// ============================================================
// MEMBRES
// ============================================================
router.post('/:groupId/members', auth, addMembers);
router.delete('/:groupId/members/:memberId', auth, removeMember);
router.patch('/:groupId/members/:memberId/promote', auth, promoteMember);

// ============================================================
// MESSAGES
// ============================================================
router.get('/:groupId/messages', auth, getGroupMessages);
router.post('/:groupId/messages', auth, messageUpload, moderation, sendGroupMessage);

// Suppression pour tout le monde (soft delete)
router.delete('/:groupId/messages/:messageId', auth, deleteGroupMessage);

// ✅ NOUVELLES FONCTIONNALITÉS (WhatsApp-like)
// Modifier un message de groupe (édition)
router.put('/:groupId/messages/:messageId/edit', auth, editGroupMessage);

// Supprimer un message de groupe pour moi (masquer localement)
router.delete('/:groupId/messages/:messageId/for-me', auth, deleteGroupMessageForMe);

module.exports = router;