// middleware/upload.js
const multer = require('multer');
const path = require('path');
const fs = require('fs');

// ─── DOSSIER DE STOCKAGE ──────────────────────────────────────
const uploadDir = path.join(__dirname, '../../uploads');
if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir, { recursive: true });
}

const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, uploadDir),
  filename: (req, file, cb) => {
    const unique = Date.now() + '-' + Math.round(Math.random() * 1E9);
    const ext = path.extname(file.originalname);
    let prefix = 'media-';
    if (file.fieldname === 'avatar') prefix = 'avatar-';
    else if (file.fieldname === 'file') prefix = 'file-';
    cb(null, prefix + unique + ext);
  }
});

// ─── FILTRES PAR TYPE ──────────────────────────────────────────
const imageFilter = (req, file, cb) => {
  const allowed = /jpeg|jpg|png|gif|webp/;
  const ext = path.extname(file.originalname).toLowerCase();
  const mime = file.mimetype;
  if (allowed.test(ext) && mime.startsWith('image/')) {
    cb(null, true);
  } else {
    cb(new Error('Seules les images sont autorisées (jpg, png, gif, webp)'), false);
  }
};

const mediaFilter = (req, file, cb) => {
  const allowedImages = /jpeg|jpg|png|gif|webp/;
  const allowedVideos = /mp4|mov|avi|mkv/;
  const ext = path.extname(file.originalname).toLowerCase();
  const isImage = allowedImages.test(ext) && file.mimetype.startsWith('image/');
  const isVideo = allowedVideos.test(ext) && file.mimetype.startsWith('video/');
  if (isImage || isVideo) {
    cb(null, true);
  } else {
    cb(new Error('Seules les images et vidéos sont acceptées'), false);
  }
};

const fileFilter = (req, file, cb) => {
  const forbidden = ['.exe', '.bat', '.cmd', '.sh', '.msi', '.deb', '.rpm'];
  const ext = path.extname(file.originalname).toLowerCase();
  if (forbidden.includes(ext)) {
    cb(new Error('Type de fichier interdit'), false);
    return;
  }
  const allowedExts = [
    'jpg','jpeg','png','gif','webp',
    'mp4','mov','avi','mkv',
    'mp3','ogg','wav','m4a',
    'pdf','doc','docx','xls','xlsx','ppt','pptx','txt',
    'zip','rar','7z'
  ];
  const extOk = allowedExts.includes(ext.replace('.', ''));
  const mimeOk = file.mimetype.startsWith('image/') ||
                 file.mimetype.startsWith('video/') ||
                 file.mimetype.startsWith('audio/') ||
                 file.mimetype === 'application/pdf' ||
                 file.mimetype.startsWith('application/vnd') ||
                 file.mimetype.startsWith('text/') ||
                 file.mimetype === 'application/zip' ||
                 file.mimetype === 'application/x-rar-compressed';
  if (extOk || mimeOk) {
    cb(null, true);
  } else {
    cb(new Error('Type de fichier non supporté'), false);
  }
};

// ─── INSTANCES MULTER (avec limites) ──────────────────────────
const uploadAvatar = multer({
  storage,
  limits: { fileSize: 3 * 1024 * 1024 },
  fileFilter: imageFilter
});

const uploadPostMedia = multer({
  storage,
  limits: { fileSize: 20 * 1024 * 1024 },
  fileFilter: mediaFilter
});

const uploadMessageFile = multer({
  storage,
  limits: { fileSize: 20 * 1024 * 1024 },
  fileFilter: fileFilter
});

const uploadGroupFile = multer({
  storage,
  limits: { fileSize: 50 * 1024 * 1024 },
  fileFilter: fileFilter
});

// ─── MIDDLEWARES PRÊTS À L'EMPLOI ─────────────────────────────

// ✅ Avatar : un seul fichier, champ 'media'
const upload = uploadAvatar.single('media');

// ✅ Posts : plusieurs fichiers, champ 'media[]' (max 10)
const multipleUpload = (req, res, next) => {
  uploadPostMedia.any()(req, res, (err) => {
    if (err) return next(err);
    next();
  });
};

// ✅ Message privé : un seul fichier, champ 'file'
const messageUpload = (req, res, next) => {
  uploadMessageFile.single('file')(req, res, (err) => {
    if (err) return next(err);
    next();
  });
};

// ✅ Groupe : un seul fichier, champ 'file'
const groupFileUpload = (req, res, next) => {
  uploadGroupFile.single('file')(req, res, (err) => {
    if (err) return next(err);
    next();
  });
};

// ✅ Middleware optionnel pour les posts sans média (0 ou plusieurs fichiers)
const optionalUpload = (req, res, next) => {
  const contentType = req.headers['content-type'] || '';
  if (contentType.includes('multipart/form-data')) {
    uploadPostMedia.any()(req, res, (err) => {
      if (err && err.code === 'LIMIT_UNEXPECTED_FILE') {
        return next(); // pas de fichier, on continue
      }
      if (err) return next(err);
      next();
    });
  } else {
    next();
  }
};

module.exports = {
  upload,                   // upload.single('media') – 3 Mo images
  multipleUpload,           // pour les posts (plusieurs fichiers, 20 Mo)
  optionalUpload,           // 0 ou plusieurs fichiers
  messageUpload,            // un seul fichier, 20 Mo
  groupFileUpload,          // un seul fichier, 50 Mo
  uploadAvatar,
  uploadPostMedia,
  uploadMessageFile,
  uploadGroupFile,
};
