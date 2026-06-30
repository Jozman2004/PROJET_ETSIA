// src/routes/notificationRoutes.js — Routes pour les notifications
const express = require('express');
const router = express.Router();

const notificationController = require('../controllers/notificationController');
const auth = require('../middleware/auth');

// Récupérer les notifications de l'utilisateur connecté
router.get('/', auth, notificationController.getNotifications);

// Récupérer le nombre de notifications non lues
router.get('/unread-count', auth, notificationController.getUnreadCount);

// Marquer toutes les notifications comme lues
router.put('/read-all', auth, notificationController.markAllRead);

// Marquer une notification spécifique comme lue (par son ID)
router.put('/:id/read', auth, notificationController.markOneRead);

module.exports = router;