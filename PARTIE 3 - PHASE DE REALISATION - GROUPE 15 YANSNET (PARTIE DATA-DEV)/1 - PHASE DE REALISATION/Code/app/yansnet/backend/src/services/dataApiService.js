// src/services/dataApiService.js
// Centralise tous les appels vers le serveur Python Data (port 5002)
// Développé par l'équipe Data — Groupe 15

const axios = require('axios');

const DATA_API_URL = process.env.DATA_API_URL || 'http://localhost:5002';

const client = axios.create({
  baseURL: DATA_API_URL,
  timeout: 15000,
});

// Sentiment — analyser un texte unique
async function analyserSentiment(texte) {
  try {
    const res = await client.post('/sentiment', { texte });
    return res.data;
  } catch (err) {
    console.error('[Data API] analyserSentiment:', err.message);
    return null;
  }
}

// Sentiment — analyser plusieurs posts d'un utilisateur
async function analyserSentimentUtilisateur(userId, posts) {
  try {
    const res = await client.post('/sentiment/user', { user_id: userId, posts });
    return res.data;
  } catch (err) {
    console.error('[Data API] analyserSentimentUtilisateur:', err.message);
    return null;
  }
}

// Harcèlement — analyser un commentaire
async function analyserHarcelement(texte) {
  try {
    const res = await client.post('/harcelement', { texte });
    return res.data;
  } catch (err) {
    console.error('[Data API] analyserHarcelement:', err.message);
    return null;
  }
}

// Harcèlement — analyser les commentaires d'un utilisateur vers ses cibles
async function analyserHarcelementUtilisateur(harceleurId, commentaires) {
  try {
    const res = await client.post('/harcelement/user', {
      harceleur_id: harceleurId,
      commentaires,
    });
    return res.data;
  } catch (err) {
    console.error('[Data API] analyserHarcelementUtilisateur:', err.message);
    return null;
  }
}

// Spam — détecter un comportement anormal
async function detecterSpam(userId, comportement) {
  try {
    const res = await client.post('/spam', { user_id: userId, ...comportement });
    return res.data;
  } catch (err) {
    console.error('[Data API] detecterSpam:', err.message);
    return null;
  }
}

// Recommandation — posts et utilisateurs suggérés
async function obtenirRecommandations(userId) {
  try {
    const res = await client.get(`/recommandation/${userId}`);
    return res.data;
  } catch (err) {
    console.error('[Data API] obtenirRecommandations:', err.message);
    return null;
  }
}

module.exports = {
  analyserSentiment,
  analyserSentimentUtilisateur,
  analyserHarcelement,
  analyserHarcelementUtilisateur,
  detecterSpam,
  obtenirRecommandations,
};
