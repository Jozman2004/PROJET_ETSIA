// src/middleware/dataModeration.js
// Détection de harcèlement sur les commentaires via le serveur Data (port 5002)
// Développé par l'équipe Data — Groupe 15

const dataApi = require('../services/dataApiService');
const pool = require('../config/database');

// Middleware Express — bloque un commentaire harcelant avant insertion
async function harcelementCheck(req, res, next) {
  const texte = req.body.content || req.body.comment || '';

  if (!texte.trim()) return next();

  const analyse = await dataApi.analyserHarcelement(texte);

  // Si le serveur Data est injoignable → on laisse passer (fail-safe)
  if (!analyse) return next();

  if (analyse.est_harcelant) {
    return res.status(400).json({
      error: 'Commentaire détecté comme harcelant. Veuillez reformuler votre message.',
      score: analyse.score_toxic,
    });
  }

  next();
}

// Vérification du pattern de harcèlement après insertion d'un commentaire
// (appelé en arrière-plan depuis le controller, ne bloque pas la réponse)
async function verifierHarcelementApresCommentaire(commentId, userId, postAuteurId, texte) {
  try {
    const result = await pool.query(
      `SELECT c.content AS texte, p.user_id AS cible_id
       FROM comments c
       JOIN posts p ON p.id = c.post_id
       WHERE c.user_id = $1
         AND p.user_id = $2
         AND c.created_at > NOW() - INTERVAL '24 hours'
         AND c.is_deleted = false`,
      [userId, postAuteurId]
    );

    if (result.rows.length < 2) return;

    const commentaires = result.rows.map(r => ({
      texte: r.texte,
      cible_id: r.cible_id,
    }));

    const analyse = await dataApi.analyserHarcelementUtilisateur(userId, commentaires);

    if (analyse && analyse.alerte) {
      console.warn(`[Harcèlement] Pattern détecté — user ${userId} → cibles`, analyse.cibles_harcelees);

      await pool.query(
        `INSERT INTO reports (reporter_id, comment_id, reason, status)
         VALUES ($1, $2, $3, 'pending')`,
        [
          userId,
          commentId,
          `Pattern de harcèlement détecté automatiquement (IA) — cibles : ${analyse.cibles_harcelees.join(', ')}`,
        ]
      );
    }
  } catch (err) {
    console.error('[Harcèlement] Erreur verifierPattern:', err.message);
  }
}

module.exports = { harcelementCheck, verifierHarcelementApresCommentaire };
