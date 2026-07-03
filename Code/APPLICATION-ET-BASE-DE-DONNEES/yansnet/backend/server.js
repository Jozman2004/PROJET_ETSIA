// server.js — VERSION FINALE COMPLÈTE YANSNET
const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const path = require('path');
const fs = require('fs');
require('dotenv').config();

const app = express();
const server = http.createServer(app);
const io = socketIo(server, { cors: { origin: '*', methods: ['GET', 'POST'] } });
global.io = io;

app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
app.use(cors());
app.use(morgan('dev'));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// ─────────────────────────────────────────────────────────────
// SERVIR LES FICHIERS UPLOADS (inline pour images/vidéos/PDF)
// ─────────────────────────────────────────────────────────────
app.get('/uploads/:filename', (req, res) => {
  const filename = req.params.filename;
  const filePath = path.join(__dirname, 'uploads', filename);

  if (!fs.existsSync(filePath)) {
    return res.status(404).json({ error: 'Fichier introuvable' });
  }

  const ext = path.extname(filename).toLowerCase();

  // Ces types s'affichent directement (inline)
  const inlineTypes = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.mp4', '.mov', '.pdf'];

  // Ces types se téléchargent automatiquement
  const downloadTypes = [
    '.mp3', '.ogg', '.wav', '.m4a',
    '.avi', '.mkv',
    '.doc', '.docx',
    '.xls', '.xlsx',
    '.ppt', '.pptx',
    '.txt', '.zip'
  ];

  if (downloadTypes.includes(ext)) {
    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
  } else {
    res.setHeader('Content-Disposition', `inline; filename="${filename}"`);
  }

  res.sendFile(filePath);
});

// ─────────────────────────────────────────────────────────────
// ENDPOINT TÉLÉCHARGEMENT FORCÉ (pour Flutter / bouton download)
// Appelé depuis Flutter avec /download/:filename
// Force le téléchargement de TOUT type de fichier
// ─────────────────────────────────────────────────────────────
app.get('/download/:filename', (req, res) => {
  const filename = req.params.filename;
  const filePath = path.join(__dirname, 'uploads', filename);

  if (!fs.existsSync(filePath)) {
    return res.status(404).json({ error: 'Fichier introuvable' });
  }

  // Toujours forcer le téléchargement, peu importe le type
  res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
  res.sendFile(filePath);
});

// ─────────────────────────────────────────────────────────────
// ROUTES API
// ─────────────────────────────────────────────────────────────
app.use('/api/auth',          require('./src/routes/authRoutes'));
app.use('/api/users',         require('./src/routes/userRoutes'));
app.use('/api/posts',         require('./src/routes/postRoutes'));
app.use('/api/messages',      require('./src/routes/messageRoutes'));
app.use('/api/groups',        require('./src/routes/groupRoutes'));
app.use('/api/notifications', require('./src/routes/notificationRoutes'));
app.use('/api/reports',       require('./src/routes/reportRoutes'));
app.use('/api/admin',         require('./src/routes/adminRoutes'));
app.use('/api/comments',      require('./src/routes/commentRoutes'));
app.use('/api/replies',       require('./src/routes/replyRoutes'));

// ─────────────────────────────────────────────────────────────
// ROUTES UTILITAIRES
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
// SOCKET
// ─────────────────────────────────────────────────────────────
require('./src/socket/socketHandler')(io);

// ─────────────────────────────────────────────────────────────
// DÉMARRAGE
// ─────────────────────────────────────────────────────────────
const PORT = process.env.PORT || 5000;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`\n YANSNET API v2.0 démarrée sur le port ${PORT}\n`);
});