// src/middleware/spamCheck.js
// Surveillance de la fréquence d'actions par utilisateur
// Développé par l'équipe Data — Groupe 15

const dataApi = require('../services/dataApiService');

// Compteurs en mémoire : { userId: { posts, likes, dm, comments, follows, cibles } }
const compteurs = new Map();

function obtenirCompteur(userId) {
  if (!compteurs.has(userId)) {
    compteurs.set(userId, {
      posts: 0, likes: 0, dm: 0, comments: 0, follows: 0, cibles: new Set(),
    });
  }
  return compteurs.get(userId);
}

// Middleware : incrémente le compteur d'une action
// Usage : trackerAction('posts'), trackerAction('likes'), etc.
function trackerAction(typeAction) {
  return (req, res, next) => {
    // 🔒 Vérification de sécurité : utilisateur authentifié
    if (!req.user || !req.user.userId) {
      return next();
    }

    const compteur = obtenirCompteur(req.user.userId);
    compteur[typeAction] = (compteur[typeAction] || 0) + 1;

    // 🔒 Sécurisation de l'accès à req.body
    const body = req.body || {};
    // Récupération de la cible (postId, userId, receiver_id)
    const cible = req.params.postId || req.params.userId || body.receiver_id;
    if (cible) {
      compteur.cibles.add(cible);
    }

    next();
  };
}

// Lance la vérification périodique toutes les 60s
// onSpamDetecte(userId, resultat) est appelé si spam détecté
function lancerVerificationPeriodique(onSpamDetecte) {
  setInterval(async () => {
    for (const [userId, compteur] of compteurs.entries()) {
      const total = compteur.posts + compteur.likes + compteur.dm + compteur.comments + compteur.follows;

      if (total === 0) {
        compteurs.delete(userId);
        continue;
      }

      const ratioUniques = compteur.cibles.size / total;

      try {
        const resultat = await dataApi.detecterSpam(userId, {
          posts_par_min    : compteur.posts,
          likes_par_min    : compteur.likes,
          dm_par_min       : compteur.dm,
          comments_par_min : compteur.comments,
          follows_par_min  : compteur.follows,
          ratio_actions_uniques: ratioUniques,
        });

        if (resultat && resultat.est_spam && onSpamDetecte) {
          onSpamDetecte(userId, resultat);
        }
      } catch (error) {
        // En cas d'erreur du service Data, on loggue mais on continue
        console.error(`❌ Erreur lors de la vérification spam pour ${userId}:`, error.message);
      }

      // Reset pour la prochaine minute
      compteurs.set(userId, {
        posts: 0, likes: 0, dm: 0, comments: 0, follows: 0, cibles: new Set(),
      });
    }
  }, 60 * 1000);
}

module.exports = { trackerAction, lancerVerificationPeriodique };