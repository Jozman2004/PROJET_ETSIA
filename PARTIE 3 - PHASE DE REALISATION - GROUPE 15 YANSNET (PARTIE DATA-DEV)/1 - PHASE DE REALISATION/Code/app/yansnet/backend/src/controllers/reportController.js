// src/controllers/reportController.js — VERSION CORRIGÉE ET COMPLÈTE
const pool = require('../config/database');
const { v4: uuidv4 } = require('uuid');
const { notify } = require('./notificationController');

/**
 * POST /api/reports
 * Créer un signalement (post ou commentaire)
 */
exports.createReport = async (req, res) => {
  const { postId, commentId, reason } = req.body;
  const reporterId = req.user.userId;

  if (!reason?.trim()) {
    return res.status(400).json({ error: 'La raison du signalement est requise' });
  }
  if (!postId && !commentId) {
    return res.status(400).json({ error: 'Vous devez fournir soit un postId, soit un commentId' });
  }
  try {
    const reportId = uuidv4();
    await pool.query(
      `INSERT INTO reports (id, reporter_id, post_id, comment_id, reason)
       VALUES ($1, $2, $3, $4, $5)`,
      [reportId, reporterId, postId || null, commentId || null, reason.trim()]
    );

    // Si le signalement concerne un post, vérifier le seuil de 3 signalements
    if (postId) {
      const countResult = await pool.query(
        `SELECT COUNT(*) as count FROM reports WHERE post_id = $1 AND status = 'pending'`,
        [postId]
      );
      const pendingCount = parseInt(countResult.rows[0].count, 10);
      if (pendingCount >= 3) {
        // Automatiquement supprimer le post après 3 signalements
        await pool.query(`UPDATE posts SET is_deleted = true WHERE id = $1`, [postId]);
        // Notifier les modérateurs et administrateurs
        const moderators = await pool.query(
          `SELECT id FROM users WHERE role IN ('moderator', 'admin') AND is_active = true`
        );
        for (const mod of moderators.rows) {
          await notify(
            mod.id,
            'moderation_alert',
            `Un post a été suspendu automatiquement suite à ${pendingCount} signalements.`,
            postId
          );
        }
      }
    }

    res.status(201).json({ id: reportId, message: 'Signalement envoyé. Merci pour votre vigilance.' });
  } catch (err) {
    console.error('Erreur createReport:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

/**
 * GET /api/reports?status=pending|reviewed|resolved
 * Récupérer la liste des signalements (réservé aux modérateurs/admins)
 */
exports.getReports = async (req, res) => {
  // Vérifier que l'utilisateur a le droit (modérateur ou admin)
  const { role } = req.user;
  if (!['admin', 'moderator'].includes(role)) {
    return res.status(403).json({ error: 'Accès non autorisé' });
  }

  const status = req.query.status || 'pending';
  try {
    const result = await pool.query(
      `SELECT r.*, 
              u.username AS reporter_username,
              p.content AS post_content, p.user_id AS post_author_id,
              ua.username AS post_author_username
       FROM reports r
       LEFT JOIN users u ON r.reporter_id = u.id
       LEFT JOIN posts p ON r.post_id = p.id
       LEFT JOIN users ua ON p.user_id = ua.id
       WHERE r.status = $1
       ORDER BY r.created_at DESC
       LIMIT 50`,
      [status]
    );
    res.json(result.rows);
  } catch (err) {
    console.error('Erreur getReports:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

/**
 * PUT /api/reports/:id
 * Résoudre un signalement (action possible : 'delete_post', 'warn_user', 'ignore')
 */
exports.resolveReport = async (req, res) => {
  // Vérifier les droits
  const { role } = req.user;
  if (!['admin', 'moderator'].includes(role)) {
    return res.status(403).json({ error: 'Action réservée aux modérateurs et administrateurs' });
  }

  const { id } = req.params;
  const { action, status } = req.body;
  const newStatus = status || 'resolved';

  if (!id) {
    return res.status(400).json({ error: 'ID du signalement manquant' });
  }
  if (!action) {
    return res.status(400).json({ error: "L'action à effectuer est requise (delete_post, warn_user, ignore)" });
  }

  try {
    // Récupérer le signalement avec les infos du post associé
    const reportResult = await pool.query(
      `SELECT r.*, p.user_id AS post_author_id
       FROM reports r
       LEFT JOIN posts p ON r.post_id = p.id
       WHERE r.id = $1`,
      [id]
    );
    if (reportResult.rows.length === 0) {
      return res.status(404).json({ error: 'Signalement non trouvé' });
    }
    const report = reportResult.rows[0];

    // Traitement selon l'action
    if (action === 'delete_post' && report.post_id) {
      await pool.query(`UPDATE posts SET is_deleted = true WHERE id = $1`, [report.post_id]);
    } else if (action === 'warn_user' && report.post_author_id) {
      await notify(
        report.post_author_id,
        'warning',
        'Un de vos contenus a été signalé. Veuillez respecter la charte de la communauté UCAC-ICAM.',
        report.post_id
      );
    } else if (action === 'ignore') {
      // Ne rien faire de plus
    } else {
      return res.status(400).json({ error: 'Action non reconnue ou inapplicable' });
    }

    // Mettre à jour le statut du signalement
    await pool.query(`UPDATE reports SET status = $1 WHERE id = $2`, [newStatus, id]);

    res.json({ message: 'Signalement traité avec succès' });
  } catch (err) {
    console.error('Erreur resolveReport:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};