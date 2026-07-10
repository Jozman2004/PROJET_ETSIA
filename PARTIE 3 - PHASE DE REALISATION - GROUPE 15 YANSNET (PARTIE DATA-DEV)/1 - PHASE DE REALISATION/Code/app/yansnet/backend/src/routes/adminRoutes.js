// src/routes/adminRoutes.js — Routes pour l'administration
const express = require('express');
const router = express.Router();

const adminController = require('../controllers/adminController');
const auth = require('../middleware/auth');
const checkRole = require('../middleware/checkRole');

// Toutes les routes admin nécessitent authentification + rôle 'admin'
router.use(auth, checkRole('admin'));

// Statistiques globales
router.get('/stats', adminController.getStats);

// Gestion des utilisateurs
router.get('/users', adminController.getUsers);
router.put('/users/:id/role', adminController.changeUserRole);
router.put('/users/:id/toggle', adminController.toggleUserActive);

// Gestion des groupes
router.post('/groups', adminController.createGroup);
router.get('/groups', adminController.getGroups);

module.exports = router;