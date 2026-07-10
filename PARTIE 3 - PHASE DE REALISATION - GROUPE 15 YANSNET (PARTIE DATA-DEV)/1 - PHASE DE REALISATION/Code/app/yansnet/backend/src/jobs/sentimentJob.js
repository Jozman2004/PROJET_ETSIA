// src/jobs/sentimentJob.js
// Analyse sentimentale en batch toutes les 6h — Équipe Data Groupe 15

const pool = require('../config/database');
const dataApi = require('../services/dataApiService');

async function analyserSentimentTousUtilisateurs() {
  console.log('[Sentiment] Lancement analyse batch...');
  try {
    const usersResult = await pool.query(
      `SELECT DISTINCT user_id FROM posts
       WHERE created_at > NOW() - INTERVAL '7 days' AND is_deleted = false`
    );

    for (const { user_id } of usersResult.rows) {
      const postsResult = await pool.query(
        `SELECT content FROM posts
         WHERE user_id = $1
           AND created_at > NOW() - INTERVAL '7 days'
           AND is_deleted = false
           AND content IS NOT NULL
         ORDER BY created_at DESC LIMIT 10`,
        [user_id]
      );

      const textes = postsResult.rows.map(r => r.content).filter(Boolean);
      if (textes.length === 0) continue;

      const analyse = await dataApi.analyserSentimentUtilisateur(user_id, textes);

      if (analyse && analyse.alerte) {
        console.warn(`[Sentiment] Détresse détectée — user ${user_id} (niveau: ${analyse.niveau})`);

        // Notifier tous les concierges
        await pool.query(
          `INSERT INTO notifications (user_id, type, content)
           SELECT id, 'alerte_detresse', $1
           FROM users WHERE role = 'concierge' AND is_active = true`,
          [`Un étudiant montre des signes de détresse (niveau: ${analyse.niveau}). Vérifiez ses publications récentes.`]
        );
      }
    }

    console.log('[Sentiment] Analyse batch terminée.');
  } catch (err) {
    console.error('[Sentiment] Erreur batch:', err.message);
  }
}

module.exports = { analyserSentimentTousUtilisateurs };
