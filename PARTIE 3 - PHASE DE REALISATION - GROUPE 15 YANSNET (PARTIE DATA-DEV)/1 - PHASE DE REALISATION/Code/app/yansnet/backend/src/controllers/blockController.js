const pool = require('../config/database');
const { v4: uuidv4 } = require('uuid');

// Bloquer un utilisateur
exports.blockUser = async (req, res) => {
  const { userId } = req.params; // l'utilisateur à bloquer
  const blockerId = req.user.userId;

  if (userId === blockerId) {
    return res.status(400).json({ error: 'Vous ne pouvez pas vous bloquer vous-même' });
  }

  try {
    // Vérifier si déjà bloqué
    const existing = await pool.query(
      'SELECT 1 FROM blocks WHERE blocker_id = $1 AND blocked_id = $2',
      [blockerId, userId]
    );
    if (existing.rows.length > 0) {
      return res.status(400).json({ error: 'Utilisateur déjà bloqué' });
    }

    await pool.query(
      'INSERT INTO blocks (id, blocker_id, blocked_id) VALUES ($1, $2, $3)',
      [uuidv4(), blockerId, userId]
    );

    // Optionnel : supprimer les messages existants entre les deux ? (ou juste masquer)
    res.json({ message: 'Utilisateur bloqué avec succès' });
  } catch (err) {
    console.error('blockUser error:', err);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// Débloquer un utilisateur
exports.unblockUser = async (req, res) => {
  const { userId } = req.params;
  const blockerId = req.user.userId;

  try {
    const result = await pool.query(
      'DELETE FROM blocks WHERE blocker_id = $1 AND blocked_id = $2 RETURNING id',
      [blockerId, userId]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Blocage non trouvé' });
    }
    res.json({ message: 'Utilisateur débloqué' });
  } catch (err) {
    console.error('unblockUser error:', err);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// Vérifier le statut de blocage entre deux utilisateurs
exports.getBlockStatus = async (req, res) => {
  const { userId } = req.params;
  const blockerId = req.user.userId;

  try {
    const result = await pool.query(
      'SELECT 1 FROM blocks WHERE blocker_id = $1 AND blocked_id = $2',
      [blockerId, userId]
    );
    res.json({ isBlocked: result.rows.length > 0 });
  } catch (err) {
    console.error('getBlockStatus error:', err);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};