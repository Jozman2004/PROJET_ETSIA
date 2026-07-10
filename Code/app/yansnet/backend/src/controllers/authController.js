// src/controllers/authController.js — VERSION CORRIGÉE
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const pool = require('../config/database');

exports.register = async (req, res) => {
  const { email, password, username, full_name, promotion, residence, filiere } = req.body;
  console.log('BODY REÇU :', req.body);
  try {
    // Vérifier si l'utilisateur existe déjà
    const existing = await pool.query('SELECT id FROM users WHERE email = $1', [email]);
    if (existing.rows.length > 0) {
      return res.status(400).json({ error: 'Cet email est déjà utilisé' });
    }
    // Hacher le mot de passe
    const hashedPassword = await bcrypt.hash(password, 10);
    const userId = uuidv4();

    // REQUÊTE CORRIGÉE : l'ordre des colonnes correspond au schéma
    await pool.query(
      `INSERT INTO users (id, username, email, password_hash, full_name, promotion, residence, filiere)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [userId, username, email, hashedPassword, full_name, promotion, residence, filiere]
    );

    // Ajout automatique aux groupes (optionnel)
    if (promotion || residence || filiere) {
      await pool.query(
        `INSERT INTO group_members (group_id, user_id)
         SELECT id, $1 FROM groups
         WHERE (type = 'promotion' AND name = $2)
            OR (type = 'residence' AND name = $3)
            OR (type = 'filiere' AND name = $4)`,
        [userId, promotion, residence, filiere]
      );
    }

    // Générer JWT
    const token = jwt.sign({ userId, email }, process.env.JWT_SECRET, { expiresIn: process.env.JWT_EXPIRES_IN });
    res.status(201).json({
      token,
      user: {
        id: userId,
        email,
        username,
        full_name,
        role: 'student',
        promotion,
        residence,
        filiere
      }
    });
  } catch (err) {
    console.error('Erreur SQL:', err);
    res.status(500).json({ error: 'Erreur serveur', detail: err.message });
  }
};

exports.login = async (req, res) => {
  const { email, password } = req.body;
  console.log('LOGIN BODY :', req.body);
  try {
    const result = await pool.query(
      `SELECT id, email, password_hash, username, full_name, role, is_active, promotion, residence, filiere
       FROM users WHERE email = $1`,
      [email]
    );
    if (result.rows.length === 0) {
      return res.status(401).json({ error: 'Email ou mot de passe incorrect' });
    }
    const user = result.rows[0];
    if (!user.is_active) {
      return res.status(401).json({ error: 'Compte désactivé' });
    }
    const valid = await bcrypt.compare(password, user.password_hash);
    if (!valid) {
      return res.status(401).json({ error: 'Email ou mot de passe incorrect' });
    }
    const token = jwt.sign(
      { userId: user.id, email: user.email, role: user.role },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_EXPIRES_IN }
    );
    res.json({
      token,
      user: {
        id: user.id,
        email: user.email,
        username: user.username,
        full_name: user.full_name,
        role: user.role,
        promotion: user.promotion,
        residence: user.residence,
        filiere: user.filiere
      }
    });
  } catch (err) {
    console.error('Erreur login:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
};