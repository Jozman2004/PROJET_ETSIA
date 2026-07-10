// server.js — VERSION FINALE COMPLÈTE YANSNET (sécurisée + Firebase Admin)
const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const path = require('path');
const fs = require('fs');
const rateLimit = require('express-rate-limit');
require('dotenv').config();

// ─── IMPORT FIREBASE ADMIN ──────────────────────────────
const admin = require('firebase-admin');

// ─── INITIALISATION FIREBASE ADMIN ──────────────────────
let firebaseInitialized = false;
try {
  if (!admin.apps.length) {
    const serviceAccountPath = path.join(__dirname, 'config', 'serviceAccountKey.json');
    if (fs.existsSync(serviceAccountPath)) {
      const serviceAccount = require(serviceAccountPath);
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
        projectId: serviceAccount.project_id || 'yansnet-adafe',
      });
      console.log('✅ Firebase Admin initialisé avec succès (fichier JSON)');
      firebaseInitialized = true;
    } else {
      if (process.env.FIREBASE_PROJECT_ID && process.env.FIREBASE_PRIVATE_KEY && process.env.FIREBASE_CLIENT_EMAIL) {
        admin.initializeApp({
          credential: admin.credential.cert({
            projectId: process.env.FIREBASE_PROJECT_ID,
            privateKey: process.env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n'),
            clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
          }),
          projectId: process.env.FIREBASE_PROJECT_ID,
        });
        console.log('✅ Firebase Admin initialisé avec succès (variables d\'env)');
        firebaseInitialized = true;
      } else {
        console.warn('⚠️ Firebase Admin non initialisé : fichier de clé introuvable.');
      }
    }
  } else {
    console.log('✅ Firebase Admin déjà initialisé');
    firebaseInitialized = true;
  }
} catch (error) {
  console.error('❌ Erreur initialisation Firebase Admin :', error.message);
}

global.firebaseInitialized = firebaseInitialized;

const app = express();
const server = http.createServer(app);
const io = socketIo(server, { cors: { origin: '*', methods: ['GET', 'POST'] } });
global.io = io;

// ─────────────────────────────────────────────────────────────
// 1. CONFIGURATION CORS (restreinte)
// ─────────────────────────────────────────────────────────────
const corsOptions = {
  origin: [
    'https://votre-domaine.com',
    'https://www.votre-domaine.com',
    'http://localhost:5000',
    'http://127.0.0.1:5000',
  ],
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: true,
};
app.use(cors(corsOptions));

// ─────────────────────────────────────────────────────────────
// 2. RATE LIMITING
// ─────────────────────────────────────────────────────────────
const globalLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 100,
  message: { error: 'Trop de requêtes. Veuillez ralentir.' },
});
app.use(globalLimiter);

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 5,
  message: { error: 'Trop de tentatives. Réessayez dans 15 minutes.' },
});
app.use('/api/auth/login', authLimiter);
app.use('/api/auth/register', authLimiter);

// ─────────────────────────────────────────────────────────────
// 3. MIDDLEWARES DE SÉCURITÉ ET LOGS
// ─────────────────────────────────────────────────────────────
app.use(helmet({
  crossOriginResourcePolicy: { policy: 'cross-origin' },
  hsts: {
    maxAge: 31536000,
    includeSubDomains: true,
    preload: true,
  },
}));
app.use(morgan(process.env.NODE_ENV === 'production' ? 'combined' : 'dev'));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// ─────────────────────────────────────────────────────────────
// 4. VALIDATION DES UUIDs (sécurité)
// ─────────────────────────────────────────────────────────────
const validateUUID = (paramName) => {
  return (req, res, next, id) => {
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!uuidRegex.test(id)) {
      return res.status(400).json({ error: `${paramName} invalide` });
    }
    next();
  };
};

app.param('userId', validateUUID('userId'));
app.param('postId', validateUUID('postId'));
app.param('groupId', validateUUID('groupId'));
app.param('commentId', validateUUID('commentId'));
app.param('messageId', validateUUID('messageId'));
app.param('replyId', validateUUID('replyId'));

// ─────────────────────────────────────────────────────────────
// 5. FICHIERS STATIQUES POUR LES DEEP LINKS (.well-known)
// ─────────────────────────────────────────────────────────────
app.get('/.well-known/assetlinks.json', (req, res) => {
  res.json([
    {
      relation: ['delegate_permission/common.handle_all_urls'],
      target: {
        namespace: 'android_app',
        package_name: 'com.example.ucac_icam_frontend',
        sha256_cert_fingerprints: [
          'VOTRE_EMPREINTE_SHA256_ICI'
        ]
      }
    }
  ]);
});

app.get('/.well-known/apple-app-site-association', (req, res) => {
  res.setHeader('Content-Type', 'application/json');
  res.json({
    applinks: {
      apps: [],
      details: [
        {
          appID: 'VOTRE_TEAM_ID.com.example.ucac_icam_frontend',
          paths: ['/post/*']
        }
      ]
    }
  });
});

// ─────────────────────────────────────────────────────────────
// 6. SERVIRE LES FICHIERS STATIQUES (AVEC STREAMING VIDÉO)
// ─────────────────────────────────────────────────────────────
const uploadPath = path.join(__dirname, 'uploads');
// Créer le dossier s'il n'existe pas
if (!fs.existsSync(uploadPath)) {
  fs.mkdirSync(uploadPath, { recursive: true });
}

// ✅ Utilisation de express.static pour gérer les Range-Headers et le streaming
app.use('/uploads', express.static(uploadPath, {
  setHeaders: (res, filePath) => {
    const ext = path.extname(filePath).toLowerCase();
    // Vidéos : streaming avec Accept-Ranges
    if (['.mp4', '.mov', '.avi', '.mkv', '.webm'].includes(ext)) {
      res.setHeader('Content-Type', 'video/mp4');
      res.setHeader('Accept-Ranges', 'bytes');
      res.setHeader('Cache-Control', 'public, max-age=86400');
    }
    // Images
    else if (['.jpg', '.jpeg', '.png', '.gif', '.webp'].includes(ext)) {
      res.setHeader('Cache-Control', 'public, max-age=86400');
    }
    // Documents : téléchargement forcé
    else if (['.pdf', '.doc', '.docx', '.xls', '.xlsx', '.zip', '.rar'].includes(ext)) {
      res.setHeader('Content-Disposition', `attachment; filename="${path.basename(filePath)}"`);
    }
  }
}));

// ─────────────────────────────────────────────────────────────
// 7. ENDPOINT TÉLÉCHARGEMENT FORCÉ (/download/:filename)
// ─────────────────────────────────────────────────────────────
app.get('/download/:filename', (req, res) => {
  const filename = req.params.filename;
  const filePath = path.join(uploadPath, filename);

  if (!fs.existsSync(filePath)) {
    return res.status(404).json({ error: 'Fichier introuvable' });
  }

  res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
  res.setHeader('Content-Type', 'application/octet-stream');
  res.sendFile(filePath); // ✅ Méthode correcte
});

// ─────────────────────────────────────────────────────────────
// 8. ROUTES API
// ─────────────────────────────────────────────────────────────
app.use('/api/auth',             require('./src/routes/authRoutes'));
app.use('/api/users',            require('./src/routes/userRoutes'));
app.use('/api/posts',            require('./src/routes/postRoutes'));
app.use('/api/messages',         require('./src/routes/messageRoutes'));
app.use('/api/groups',           require('./src/routes/groupRoutes'));
app.use('/api/notifications',    require('./src/routes/notificationRoutes'));
app.use('/api/reports',          require('./src/routes/reportRoutes'));
app.use('/api/admin',            require('./src/routes/adminRoutes'));
app.use('/api/comments',         require('./src/routes/commentRoutes'));
app.use('/api/replies',          require('./src/routes/replyRoutes'));
app.use('/api/recommandations',  require('./src/routes/recommandationRoutes'));

// ─────────────────────────────────────────────────────────────
// 9. ROUTE DE PARTAGE DE PUBLICATION (redirection intelligente)
// ─────────────────────────────────────────────────────────────
app.get('/post/:postId', async (req, res) => {
  const postId = req.params.postId;

  const appDeepLink = `yansnet://post/${postId}`;
  const downloadUrl = 'https://votre-domaine.com/download';
  const webAppUrl = `https://votre-domaine.com/web/post/${postId}`;

  const html = `
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>YANSNET — Publication</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      display: flex;
      justify-content: center;
      align-items: center;
      min-height: 100vh;
      margin: 0;
      background: #f5f5f5;
      padding: 20px;
    }
    .container {
      max-width: 400px;
      background: white;
      border-radius: 16px;
      padding: 40px 24px;
      text-align: center;
      box-shadow: 0 4px 20px rgba(0,0,0,0.1);
    }
    .logo {
      font-size: 32px;
      font-weight: 900;
      color: #9E1B22;
      letter-spacing: 2px;
      margin-bottom: 16px;
    }
    .spinner {
      display: inline-block;
      width: 40px;
      height: 40px;
      border: 4px solid #e0e0e0;
      border-top-color: #9E1B22;
      border-radius: 50%;
      animation: spin 0.8s linear infinite;
      margin: 20px 0;
    }
    @keyframes spin {
      to { transform: rotate(360deg); }
    }
    .btn {
      display: inline-block;
      padding: 12px 24px;
      background-color: #9E1B22;
      color: white !important;
      text-decoration: none;
      border-radius: 30px;
      font-weight: 600;
      margin-top: 16px;
    }
    .btn-outline {
      background: transparent;
      color: #9E1B22 !important;
      border: 2px solid #9E1B22;
    }
    .small {
      font-size: 14px;
      color: #888;
      margin-top: 20px;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="logo">YANSNET</div>
    <div id="message">
      <div class="spinner"></div>
      <p style="color: #555;">Redirection en cours...</p>
    </div>
    <div id="fallback" style="display: none;">
      <p style="color: #555; margin-bottom: 16px;">
        Vous n'avez pas l'application YANSNET ?
      </p>
      <a href="${downloadUrl}" class="btn">📱 Télécharger l'application</a>
      <br>
      <a href="${webAppUrl}" class="btn btn-outline" style="margin-top: 12px;">
        🌐 Voir sur le web
      </a>
      <p class="small">
        <a href="${appDeepLink}" style="color: #9E1B22;">Ouvrir dans l'application</a>
      </p>
    </div>
  </div>

  <script>
    (function() {
      const deepLink = '${appDeepLink}';
      const fallbackEl = document.getElementById('fallback');
      const messageEl = document.getElementById('message');

      function tryOpenApp() {
        window.location.href = deepLink;
        setTimeout(() => {
          if (!document.hidden) {
            messageEl.style.display = 'none';
            fallbackEl.style.display = 'block';
          }
        }, 2000);
      }

      const isMobile = /Android|iPhone|iPad|iPod/i.test(navigator.userAgent);
      const downloadLink = document.querySelector('.btn:first-of-type');
      if (isMobile) {
        if (/Android/i.test(navigator.userAgent)) {
          downloadLink.href = 'https://play.google.com/store/apps/details?id=com.example.ucac_icam_frontend';
        } else if (/iPhone|iPad|iPod/i.test(navigator.userAgent)) {
          downloadLink.href = 'https://apps.apple.com/app/idXXXXXX';
        }
      }

      tryOpenApp();

      document.querySelector('a[href="${appDeepLink}"]')?.addEventListener('click', (e) => {
        e.preventDefault();
        tryOpenApp();
      });
    })();
  </script>
</body>
</html>
  `;

  res.send(html);
});

// ─────────────────────────────────────────────────────────────
// 10. ROUTES UTILITAIRES
// ─────────────────────────────────────────────────────────────
app.get('/', (req, res) =>
  res.json({ message: 'YANSNET API v2.0 — UCAC-ICAM Yansoki', status: 'OK' })
);

app.use((req, res) =>
  res.status(404).json({ error: 'Route non trouvée' })
);

app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).json({ error: 'Erreur serveur' });
});

// ─────────────────────────────────────────────────────────────
// 11. SOCKET
// ─────────────────────────────────────────────────────────────
require('./src/socket/socketHandler')(io);

// ─────────────────────────────────────────────────────────────
// 12. DÉTECTION SPAM — vérification toutes les 60 secondes
// ─────────────────────────────────────────────────────────────
const { lancerVerificationPeriodique } = require('./src/middleware/spamCheck');
lancerVerificationPeriodique((userId, resultat) => {
  console.warn(`[Spam] Détecté — user ${userId} : ${resultat.raison}`);
  global.io.emit('alerte_spam', { userId, raison: resultat.raison, niveau: resultat.niveau });
});

// ─────────────────────────────────────────────────────────────
// 13. ANALYSE SENTIMENT — batch toutes les 6 heures
// ─────────────────────────────────────────────────────────────
const { analyserSentimentTousUtilisateurs } = require('./src/jobs/sentimentJob');
setInterval(analyserSentimentTousUtilisateurs, 6 * 60 * 60 * 1000);

// ─────────────────────────────────────────────────────────────
// 14. DÉMARRAGE
// ─────────────────────────────────────────────────────────────
const PORT = process.env.PORT || 5000;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`\n✅ YANSNET API v2.0 démarrée sur le port ${PORT}\n`);
});