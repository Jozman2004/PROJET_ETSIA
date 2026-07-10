// src/routes/authRoutes.js
const bcrypt = require('bcryptjs');
const express = require('express');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const { body, validationResult } = require('express-validator');
const pool = require('../config/database');

const router = express.Router();

// ============================================================
// GÉNÉRATION DES TOKENS
// ============================================================
const generateAccessToken = (user) => {
  return jwt.sign(
    { userId: user.id, email: user.email },
    process.env.JWT_SECRET,
    { expiresIn: '15m' }
  );
};

const generateRefreshToken = () => crypto.randomBytes(64).toString('hex');

// ============================================================
// MIDDLEWARE D'AUTHENTIFICATION
// ============================================================
const authenticate = (req, res, next) => {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Token manquant' });
  }

  const token = authHeader.split(' ')[1];
  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    req.user = decoded;
    next();
  } catch (err) {
    if (err.name === 'TokenExpiredError') {
      return res.status(401).json({ error: 'Token expiré', code: 'TOKEN_EXPIRED' });
    }
    return res.status(401).json({ error: 'Token invalide' });
  }
};

// ============================================================
// ROUTES D'AUTHENTIFICATION
// ============================================================

// ✅ Inscription – CORRIGÉE : ajout de username
router.post(
  '/register',
  [
    body('email').isEmail().normalizeEmail(),
    body('password').isLength({ min: 6 }),
    body('full_name').notEmpty().trim().escape(),
    body('username').notEmpty().trim().escape(), // ✅ ajout de la validation
  ],
  async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

    // ✅ Récupération de tous les champs, y compris username
    const { email, password, full_name, username } = req.body;

    try {
      // Vérifier si l'email existe déjà
      const existing = await pool.query('SELECT id FROM users WHERE email = $1', [email]);
      if (existing.rows.length > 0) {
        return res.status(409).json({ error: 'Cet email est déjà utilisé' });
      }

      // ✅ Vérifier si le username est déjà pris (optionnel mais recommandé)
      const existingUser = await pool.query('SELECT id FROM users WHERE username = $1', [username]);
      if (existingUser.rows.length > 0) {
        return res.status(409).json({ error: 'Ce nom d\'utilisateur est déjà pris' });
      }

      const hashedPassword = await bcrypt.hash(password, 10);

      // ✅ Insertion incluant username
      const result = await pool.query(
        `INSERT INTO users (email, password_hash, full_name, username)
         VALUES ($1, $2, $3, $4)
         RETURNING id, email, full_name, username`,
        [email, hashedPassword, full_name, username]
      );
      const user = result.rows[0];

      const accessToken = generateAccessToken(user);
      const refreshToken = generateRefreshToken();
      const refreshExpiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);

      await pool.query(
        `INSERT INTO refresh_tokens (user_id, token, expires_at)
         VALUES ($1, $2, $3)`,
        [user.id, refreshToken, refreshExpiresAt]
      );

      res.status(201).json({
        user: {
          id: user.id,
          email: user.email,
          full_name: user.full_name,
          username: user.username, // ✅ retourné au frontend
        },
        accessToken,
        refreshToken,
      });
    } catch (err) {
      console.error('Erreur inscription:', err);
      res.status(500).json({ error: 'Erreur serveur' });
    }
  }
);

// Connexion (inchangée)
router.post(
  '/login',
  [
    body('email').isEmail().normalizeEmail(),
    body('password').notEmpty(),
  ],
  async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

    const { email, password } = req.body;

    try {
      const result = await pool.query(
        'SELECT id, email, password_hash, full_name, username FROM users WHERE email = $1',
        [email]
      );
      const user = result.rows[0];
      if (!user) {
        return res.status(401).json({ error: 'Email ou mot de passe incorrect' });
      }

      const isValid = await bcrypt.compare(password, user.password_hash);
      if (!isValid) {
        return res.status(401).json({ error: 'Email ou mot de passe incorrect' });
      }

      const accessToken = generateAccessToken(user);
      const refreshToken = generateRefreshToken();
      const refreshExpiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);

      await pool.query(
        `INSERT INTO refresh_tokens (user_id, token, expires_at)
         VALUES ($1, $2, $3)`,
        [user.id, refreshToken, refreshExpiresAt]
      );

      res.json({
        user: {
          id: user.id,
          email: user.email,
          full_name: user.full_name,
          username: user.username,
        },
        accessToken,
        refreshToken,
      });
    } catch (err) {
      console.error('Erreur login:', err);
      res.status(500).json({ error: 'Erreur serveur' });
    }
  }
);

// Rafraîchissement du token (inchangé)
router.post('/refresh-token', async (req, res) => {
  const { refreshToken } = req.body;
  if (!refreshToken) return res.status(401).json({ error: 'Refresh token manquant' });

  try {
    const result = await pool.query(
      `SELECT user_id FROM refresh_tokens
       WHERE token = $1 AND expires_at > NOW()`,
      [refreshToken]
    );
    const tokenRecord = result.rows[0];
    if (!tokenRecord) {
      return res.status(403).json({ error: 'Refresh token invalide ou expiré' });
    }

    const userResult = await pool.query('SELECT id, email, full_name, username FROM users WHERE id = $1', [tokenRecord.user_id]);
    const user = userResult.rows[0];
    if (!user) {
      return res.status(403).json({ error: 'Utilisateur non trouvé' });
    }

    const newAccessToken = generateAccessToken(user);
    res.json({ accessToken: newAccessToken });
  } catch (err) {
    console.error('Erreur refresh token:', err);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

// Déconnexion (inchangée)
router.post('/logout', async (req, res) => {
  const { refreshToken } = req.body;
  if (refreshToken) {
    await pool.query('DELETE FROM refresh_tokens WHERE token = $1', [refreshToken]);
  }
  res.json({ message: 'Déconnecté avec succès' });
});

// ============================================================
// ROUTE FCM TOKEN (inchangée)
// ============================================================
router.post('/fcm-token', authenticate, async (req, res) => {
  const userId = req.user.userId;
  const { token } = req.body;

  if (!token) {
    return res.status(400).json({ error: 'Token FCM manquant' });
  }

  try {
    await pool.query('DELETE FROM fcm_tokens WHERE token = $1', [token]);
    await pool.query(
      'INSERT INTO fcm_tokens (user_id, token) VALUES ($1, $2)',
      [userId, token]
    );
    res.json({ success: true });
  } catch (err) {
    console.error('❌ Erreur saveFcmToken:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

// ============================================================
// EXPORTS
// ============================================================
module.exports = router;
module.exports.authenticate = authenticate;