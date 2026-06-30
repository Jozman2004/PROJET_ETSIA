const multer = require('multer');
const path = require('path');
const fs = require('fs');

// Chemin absolu vers le dossier uploads
const uploadDir = path.join(__dirname, '../../uploads');

// Créer le dossier s'il n'existe pas
if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir, { recursive: true });
}

// Configuration de stockage générique
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, uploadDir);
  },
  filename: (req, file, cb) => {
    const unique = Date.now() + '-' + Math.round(Math.random() * 1E9);
    const ext = path.extname(file.originalname);
    let prefix = 'media-';
    if (file.fieldname === 'avatar') {
      prefix = 'avatar-';
    }
    cb(null, prefix + unique + ext);
  }
});

// Filtre pour les images (avatar)
const avatarFilter = (req, file, cb) => {
  const allowedTypes = /jpeg|jpg|png|gif|webp/;
  const ext = path.extname(file.originalname).toLowerCase();
  const mime = file.mimetype;
  if (allowedTypes.test(ext) && mime.startsWith('image/')) {
    cb(null, true);
  } else {
    cb(new Error('Seules les images sont autorisées pour l\'avatar'), false);
  }
};

// Filtre pour les médias (images & vidéos)
const mediaFilter = (req, file, cb) => {
  const allowedImages = /jpeg|jpg|png|gif|webp/;
  const allowedVideos = /mp4|mov|avi|mkv/;
  const ext = path.extname(file.originalname).toLowerCase();
  const isImage = allowedImages.test(ext) && file.mimetype.startsWith('image/');
  const isVideo = allowedVideos.test(ext) && file.mimetype.startsWith('video/');
  if (isImage || isVideo) {
    cb(null, true);
  } else {
    cb(new Error('Type de fichier non supporté (image ou vidéo)'), false);
  }
};

// Multer pour avatar (un seul fichier image, obligatoire)
const uploadAvatar = multer({
  storage,
  limits: { fileSize: 3 * 1024 * 1024 }, // 3 Mo
  fileFilter: avatarFilter
});

// Multer pour média (un seul fichier, optionnel)
const uploadMedia = multer({
  storage,
  limits: { fileSize: 20 * 1024 * 1024 }, // 20 Mo
  fileFilter: mediaFilter
});

// Multer pour plusieurs médias (tableau)
const uploadMultiple = uploadMedia.array('media[]', 10); // max 10 fichiers

// Middleware optionnel (0 ou 1 fichier) – pour compatibilité avec posts sans média
function optionalUpload(req, res, next) {
  const contentType = req.headers['content-type'] || '';
  if (contentType.includes('multipart/form-data')) {
    uploadMedia.single('media')(req, res, (err) => {
      if (err && err.code === 'LIMIT_UNEXPECTED_FILE') {
        return next(); // pas de fichier, on continue
      }
      if (err) return next(err);
      next();
    });
  } else {
    next();
  }
}

// Middleware pour plusieurs fichiers (posts avec galerie)
function multipleUpload(req, res, next) {
  const contentType = req.headers['content-type'] || '';
  if (contentType.includes('multipart/form-data')) {
    uploadMultiple(req, res, (err) => {
      if (err) return next(err);
      next();
    });
  } else {
    next();
  }
}



// Filtre pour messages (images, vidéos, documents, audio)
const messageFilter = (req, file, cb) => {
  const ext = path.extname(file.originalname).replace('.', '').toLowerCase();
  const mime = file.mimetype || '';

  const allowedExts = ['jpg','jpeg','png','gif','webp','mp4','mov','avi','mkv','mp3','ogg','wav','m4a','pdf','doc','docx','xls','xlsx','ppt','pptx','txt','zip'];
  const allowedMimes = ['image/', 'video/', 'audio/', 'application/pdf', 'application/msword', 'application/vnd', 'text/', 'application/zip', 'application/octet-stream'];

  const extOk = allowedExts.includes(ext);
  const mimeOk = allowedMimes.some(m => mime.startsWith(m));

  if (extOk || mimeOk) {
    cb(null, true);
  } else {
    cb(new Error('Type de fichier non supporté: ' + mime + ' / ' + ext), false);
  }
};

const uploadMessage = multer({
  storage,
  limits: { fileSize: 50 * 1024 * 1024 }, // 50 Mo
  fileFilter: messageFilter
});

function messageUpload(req, res, next) {
  const contentType = req.headers['content-type'] || '';
  if (contentType.includes('multipart/form-data')) {
    uploadMessage.single('file')(req, res, (err) => {
      if (err) return next(err);
      next();
    });
  } else {
    next();
  }
}

module.exports = {
  upload: uploadAvatar,           // pour l'avatar (single, image)
  optionalUpload,                // pour posts (0 ou 1 média)
  multipleUpload,                // pour posts (plusieurs médias)
  uploadMultiple,               // raw multer array (si besoin)
  messageUpload 
};

