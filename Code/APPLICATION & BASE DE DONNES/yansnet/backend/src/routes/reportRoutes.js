// src/routes/reportRoutes.js — Routes pour les signalements
const express = require('express');
const router = express.Router();

const reportController = require('../controllers/reportController');
const auth = require('../middleware/auth');
const checkRole = require('../middleware/checkRole');

// Créer un signalement (accessible à tout utilisateur authentifié)
router.post('/', auth, reportController.createReport);

// Voir les signalements (réservé aux modérateurs et administrateurs)
router.get('/', auth, checkRole('admin', 'moderator'), reportController.getReports);

// Traiter un signalement (réservé aux modérateurs et administrateurs)
router.put('/:id/resolve', auth, checkRole('admin', 'moderator'), reportController.resolveReport);

module.exports = router;