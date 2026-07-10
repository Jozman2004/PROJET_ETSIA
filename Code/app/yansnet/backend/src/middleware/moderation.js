// middleware/moderation.js
const axios = require('axios');
const FormData = require('form-data');
const fs = require('fs');
const path = require('path');

const MODERATION_URL = process.env.MODERATION_URL || 'http://localhost:5001/moderate';

module.exports = async (req, res, next) => {
  // 1. Récupérer le texte
  let text = '';
  if (req.body.content) text += req.body.content + ' ';
  if (req.body.comment) text += req.body.comment + ' ';
  if (req.body.message) text += req.body.message + ' ';
  text = text.trim();

  // 2. Récupérer les fichiers
  let files = [];
  if (req.files) {
    files = Array.isArray(req.files) ? req.files : Object.values(req.files);
  }
  if (req.file) files.push(req.file);
  files = files.filter(f => f && f.size > 0);

  // 3. Si ni texte ni fichiers, on passe
  if (!text && files.length === 0) {
    console.log('📝 [moderation] Aucun contenu à modérer, passage.');
    return next();
  }

  try {
    // 4. Modération du texte (si présent)
    if (text) {
      const formDataText = new FormData();
      formDataText.append('text', text);
      const textResponse = await axios.post(MODERATION_URL, formDataText, {
        headers: { ...formDataText.getHeaders() },
        timeout: 15000,
      });
      const textData = textResponse.data;
      if (textData.allowed === false) {
        return res.status(400).json({
          error: textData.reason || 'Texte inapproprié',
          suggestion: textData.suggestion || 'Veuillez reformuler votre message.',
        });
      }
    }

    // 5. Modération des fichiers (un par un)
    const refusedFiles = [];
    const acceptedFiles = [];

    for (const file of files) {
      let fileBuffer = file.buffer;
      if (!fileBuffer && file.path) {
        fileBuffer = fs.readFileSync(file.path);
      }
      if (!fileBuffer) {
        console.warn(`⚠️ [moderation] Fichier ignoré (buffer manquant) : ${file.originalname}`);
        continue;
      }

      // Déterminer le type de fichier
      const mimetype = file.mimetype || '';
      const ext = path.extname(file.originalname || file.path || '').toLowerCase();
      let fieldname = 'images';
      if (mimetype.startsWith('video/') || ['.mp4', '.mov', '.avi', '.mkv', '.webm'].includes(ext)) {
        fieldname = 'videos';
      } else if (mimetype.startsWith('image/') || ['.jpg', '.jpeg', '.png', '.gif', '.webp'].includes(ext)) {
        fieldname = 'images';
      }

      console.log(`📎 [moderation] Analyse fichier : ${file.originalname} (type: ${fieldname})`);

      const formDataFile = new FormData();
      const filename = file.originalname || path.basename(file.path) || 'file';
      formDataFile.append(fieldname, fileBuffer, {
        filename: filename,
        contentType: mimetype,
      });

      try {
        const fileResponse = await axios.post(MODERATION_URL, formDataFile, {
          headers: { ...formDataFile.getHeaders() },
          timeout: 30000,
        });
        const fileData = fileResponse.data;
        if (fileData.allowed === false) {
          refusedFiles.push({
            filename,
            reason: fileData.reason || 'Contenu inapproprié',
            suggestion: fileData.suggestion || '',
          });
        } else {
          acceptedFiles.push(file);
        }
      } catch (err) {
        // ✅ Distinguer les erreurs de contenu (400) des erreurs réseau
        if (err.response && err.response.status === 400) {
          // Le service Python a refusé le contenu
          const errorData = err.response.data || {};
          refusedFiles.push({
            filename,
            reason: errorData.reason || errorData.error || 'Contenu inapproprié',
            suggestion: errorData.suggestion || '',
          });
        } else {
          // Erreur réseau, timeout, etc. → on accepte pour ne pas bloquer
          console.error(`❌ [moderation] Erreur réseau fichier ${filename}:`, err.message);
          acceptedFiles.push(file);
        }
      }
    }

    // 6. Si tous les fichiers sont refusés et qu'il n'y a pas de texte, on bloque
    if (acceptedFiles.length === 0 && !text) {
      return res.status(400).json({
        error: 'Tous les fichiers ont été refusés par la modération.',
        details: refusedFiles,
      });
    }

    // 7. Remplacer req.files par les fichiers acceptés
    req.files = acceptedFiles;

    // 8. Ajouter les refus dans la requête pour le contrôleur
    req.refusedFiles = refusedFiles;

    // 9. S'il y a des refus, ajouter un avertissement
    if (refusedFiles.length > 0) {
      req.moderationWarning = {
        message: `${refusedFiles.length} fichier(s) ont été refusés et ne seront pas publiés.`,
        details: refusedFiles,
      };
    }

    next();
  } catch (err) {
    console.error('❌ [moderation] Erreur globale:', err.message);
    if (err.code === 'ECONNREFUSED' || err.code === 'ETIMEDOUT') {
      console.warn('⚠️ [moderation] Service de modération indisponible, publication autorisée.');
      return next();
    }
    return res.status(500).json({
      error: 'Erreur interne du serveur lors de la modération',
      details: err.message,
    });
  }
};