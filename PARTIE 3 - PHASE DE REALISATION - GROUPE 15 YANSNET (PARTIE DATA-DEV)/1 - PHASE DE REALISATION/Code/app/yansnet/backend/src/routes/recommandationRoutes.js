// src/routes/recommandationRoutes.js
// Route recommandation de contenu — Équipe Data Groupe 15

const express = require('express');
const router = express.Router();
const auth = require('../middleware/auth');
const dataApi = require('../services/dataApiService');

// GET /api/recommandations
router.get('/', auth, async (req, res) => {
  const userId = req.user.userId;

  const resultat = await dataApi.obtenirRecommandations(userId);

  if (!resultat) {
    return res.json({
      posts_recommandes: [],
      utilisateurs_suggeres: [],
      message: 'Recommandations indisponibles pour le moment',
    });
  }

  res.json(resultat);
});

module.exports = router;
