// src/controllers/adminController.js — VERSION CORRIGÉE ET COMPLÈTE
const pool = require('../config/database');
const { v4: uuidv4 } = require('uuid');

// GET /api/admin/stats — Statistiques globales
exports.getStats = async (req, res) => {
  try {
    const [usersResult, postsResult, messagesResult, reportsResult, groupsResult] = await Promise.all([
      pool.query("SELECT COUNT(*) total, COUNT(*) FILTER (WHERE is_active = true) active FROM users"),
      pool.query("SELECT COUNT(*) total, COUNT(*) FILTER (WHERE is_deleted = false) visible FROM posts"),
      pool.query("SELECT COUNT(*) total FROM messages"),
      pool.query("SELECT COUNT(*) total, COUNT(*) FILTER (WHERE status = 'pending') pending FROM reports"),
      pool.query("SELECT COUNT(*) total FROM groups"),
    ]);
    res.json({
      users: usersResult.rows[0],
      posts: postsResult.rows[0],
      messages: messagesResult.rows[0],
      reports: reportsResult.rows[0],
      groups: groupsResult.rows[0],
    });
  } catch (err) {
    console.error('Erreur getStats:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// GET /api/admin/users?search=... — Liste des utilisateurs (avec recherche)
exports.getUsers = async (req, res) => {
  const search = req.query.search || '';
  try {
    const result = await pool.query(
      `SELECT id, username, full_name, email, role, is_active, promotion, filiere, created_at
       FROM users
       WHERE ($1 = '' OR username ILIKE $1 OR full_name ILIKE $1 OR email ILIKE $1)
       ORDER BY created_at DESC
       LIMIT 100`,
      [search ? `%${search}%` : '']
    );
    res.json(result.rows);
  } catch (err) {
    console.error('Erreur getUsers:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// PUT /api/admin/users/:id/role — Changer le rôle d'un utilisateur
exports.changeUserRole = async (req, res) => {
  const { id } = req.params;
  const { role } = req.body;
  const validRoles = ['student', 'moderator', 'admin', 'alumni', 'concierge'];

  if (!id) {
    return res.status(400).json({ error: 'ID utilisateur manquant' });
  }
  if (!role || !validRoles.includes(role)) {
    return res.status(400).json({ error: 'Rôle invalide. Valeurs possibles : ' + validRoles.join(', ') });
  }

  try {
    // Vérifier que l'utilisateur existe
    const userCheck = await pool.query('SELECT id FROM users WHERE id = $1', [id]);
    if (userCheck.rows.length === 0) {
      return res.status(404).json({ error: 'Utilisateur non trouvé' });
    }

    await pool.query('UPDATE users SET role = $1 WHERE id = $2', [role, id]);
    res.json({ message: `Rôle mis à jour : ${role}` });
  } catch (err) {
    console.error('Erreur changeUserRole:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// PUT /api/admin/users/:id/toggle-active — Activer/désactiver un compte
exports.toggleUserActive = async (req, res) => {
  const { id } = req.params;
  if (!id) {
    return res.status(400).json({ error: 'ID utilisateur manquant' });
  }
  try {
    const result = await pool.query(
      `UPDATE users
       SET is_active = NOT is_active
       WHERE id = $1
       RETURNING is_active, username`,
      [id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Utilisateur non trouvé' });
    }
    const user = result.rows[0];
    res.json({
      message: `Compte ${user.is_active ? 'activé' : 'désactivé'} : ${user.username}`,
      is_active: user.is_active,
    });
  } catch (err) {
    console.error('Erreur toggleUserActive:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// POST /api/admin/groups — Créer un groupe (promotion, residence, filiere, custom)
exports.createGroup = async (req, res) => {
  const { name, type } = req.body;
  const userId = req.user.userId;

  if (!name || typeof name !== 'string' || name.trim() === '') {
    return res.status(400).json({ error: 'Le nom du groupe est requis' });
  }
  const validTypes = ['promotion', 'residence', 'filiere', 'custom'];
  if (!type || !validTypes.includes(type)) {
    return res.status(400).json({ error: 'Type invalide. Valeurs possibles : ' + validTypes.join(', ') });
  }

  try {
    // Vérifier si un groupe avec le même nom existe déjà (optionnel)
    const existing = await pool.query('SELECT id FROM groups WHERE name = $1', [name.trim()]);
    if (existing.rows.length > 0) {
      return res.status(409).json({ error: 'Un groupe avec ce nom existe déjà' });
    }

    const groupId = uuidv4();
    await pool.query(
      `INSERT INTO groups (id, name, type, created_by)
       VALUES ($1, $2, $3, $4)`,
      [groupId, name.trim(), type, userId]
    );
    res.status(201).json({ id: groupId, message: 'Groupe créé avec succès' });
  } catch (err) {
    console.error('Erreur createGroup:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};

// GET /api/admin/groups — Liste des groupes avec nombre de membres
exports.getGroups = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT g.*, COUNT(gm.user_id) AS member_count
       FROM groups g
       LEFT JOIN group_members gm ON g.id = gm.group_id
       GROUP BY g.id
       ORDER BY g.created_at DESC`
    );
    res.json(result.rows);
  } catch (err) {
    console.error('Erreur getGroups:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};