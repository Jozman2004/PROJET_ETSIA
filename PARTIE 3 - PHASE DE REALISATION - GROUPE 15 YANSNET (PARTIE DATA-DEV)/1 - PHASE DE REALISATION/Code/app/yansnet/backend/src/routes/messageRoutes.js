// src/routes/messageRoutes.js
const express = require('express');
const router = express.Router();
const messageController = require('../controllers/messageController');
const auth = require('../middleware/auth');
const { messageUpload } = require('../middleware/upload');

// ============================================================
// ROUTES PRINCIPALES
// ============================================================

// Envoyer un message (texte ou fichier)
router.post('/', auth, messageUpload, messageController.sendMessage);

// Récupérer une conversation (avec pagination)
router.get('/:userId', auth, messageController.getConversation);

// Marquer un message comme lu
router.put('/:messageId/read', auth, messageController.markAsRead);

// Liste des conversations
router.get('/conversations/list', auth, messageController.getConversations);

// ============================================================
// NOUVELLES FONCTIONNALITÉS (WhatsApp-like)
// ============================================================

// Supprimer un message pour tout le monde (soft delete)
router.delete('/:messageId', auth, messageController.deleteMessage);

// Modifier un message (édition)
router.put('/:messageId/edit', auth, messageController.editMessage);

// Supprimer un message pour moi (masquer localement)
router.delete('/:messageId/for-me', auth, messageController.deleteForMe);

module.exports = router;