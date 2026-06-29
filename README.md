# YANSNET - Réseau Social UCAC-ICAM Yansoki

> Écosystème numérique pour les étudiants du campus UCAC-ICAM de Yansoki, Douala – Cameroun.

## Présentation

YANSNET est un réseau social local conçu pour interconnecter les étudiants, résidences (minicités) et services du campus UCAC-ICAM via un serveur central. Le projet comprend :

- **Application mobile** (Flutter) — réseau social étudiant (iOS & Android)
- **Backend API** (Node.js / Express) — API REST + WebSocket temps réel
- **Site d'administration** (en cours de développement) — dashboard de gestion et modération
- **Base de données** PostgreSQL

## Équipe — Groupe Projet 15

| Nom | Rôle |
|---|---|
| MAKONGNE DEFFO July Merveille | Développeur |
| NANKAP NDIZEU Loïc Aurel | Développeur |
| NKOULOU Joseph Emmanuel | Développeur |
| NOUNGOUA NOUNGOUA Teddy Steven | Développeur |
| TOFA DEFFO Lionel Junior | Développeur |

**Promotion X2027** — Projet ETSIA X4

## Structure du projet

```
.
├── APPLICATION & BASE DE DONNES/
│   ├── yansnet/
│   │   ├── frontend/          # App mobile Flutter
│   │   └── backend/           # API Node.js / Express
│   ├── yansnet_backup.sql     # Dump de la base PostgreSQL
│   └── Commandes de lancement.txt
│
└── site-admin/
    ├── frontend/              # Dashboard admin (à venir)
    ├── backend/               # API admin (à venir)
    └── web-app/               # Application web admin
```

## Stack technique

### Application mobile (Frontend)

| Technologie | Usage |
|---|---|
| **Flutter** (SDK ≥ 3.0.0) | Framework UI cross-platform |
| **Provider** | Gestion d'état |
| **Dio** | Client HTTP |
| **Socket.IO Client** | Messagerie temps réel |
| **flutter_secure_storage** | Stockage sécurisé JWT |
| **image_picker / file_picker** | Upload de médias et documents |
| **video_player / photo_view** | Lecture multimédia |

### Backend API

| Technologie | Usage |
|---|---|
| **Node.js / Express 5** | Serveur HTTP |
| **PostgreSQL** (pg) | Base de données relationnelle |
| **Socket.IO** | WebSocket temps réel |
| **JWT** (jsonwebtoken) | Authentification |
| **bcryptjs** | Hachage des mots de passe |
| **Multer** | Upload de fichiers |
| **Helmet / CORS** | Sécurité HTTP |
| **bad-words** | Filtre de contenu |

### Charte graphique UCAC-ICAM

| Couleur | Hex | Usage |
|---|---|---|
| Rouge Bordeaux | `#9E1B22` | Couleur primaire |
| Vert Sapin | `#006838` | Couleur secondaire |
| Orange | `#F39200` | Couleur d'accent |

## Fonctionnalités

### Validées et fonctionnelles (MVP)

- Inscription / Connexion / Déconnexion (session 30 jours, JWT)
- Modification du profil (avatar, bio, nom d'usage)
- Session unique par appareil
- Publication de photos (≤ 3 Mo) avec légendes et tags `^tag`
- Fil d'actualité
- Likes (bouton dédié ou triple tap), commentaires (≤ 500 caractères)
- Signalements avec file de modération (suspension auto au 3e signalement)
- Système de follow / unfollow avec notifications
- Messagerie directe chiffrée (DM) avec édition / suppression
- Groupes de discussion (création, invitation, administration)
- Canaux privés par promotion, résidence et filière
- Partage de fichiers dans les groupes (≤ 50 Mo)
- Publications officielles UCAC-ICAM

### À corriger avant production

- Intégration SSO Google + Active Directory (EF-001)
- Matrice des droits par rôle formalisée (EF-007)
- Modèle de censure automatique des contenus (EF-011)
- Chiffrement des données au repos (ES-002)
- Archivage des conversations après réinstallation (EF-020)
- Politique de rétention des données / suppression de compte (EF-005)
- Optimisation des temps de chargement sous charge (ET-001)

### Roadmap V2

- Publications globales prioritaires avec marqueur visuel
- Mises à jour OTA via réseau de l'institut
- Tests de charge à 125 000 utilisateurs simultanés
- Mode dégradé offline / LAN
- Module Alumni (activités COCFET)
- Analyse sentimentale pour détection de détresse
- Mécanisme d'alerte rapide
- Connexion multi-appareils
- Géolocalisation des publications

## Base de données

PostgreSQL avec les tables principales :

| Table | Description |
|---|---|
| `roles` | Matrice des droits (étudiant, modérateur, admin, alumni, concierge) |
| `users` | Comptes utilisateurs (UUID, email, SSO Google/AD, profil) |
| `sessions` | Refresh tokens |
| `posts` | Publications (texte, image, vidéo) |
| `likes` | Likes sur les publications |
| `comments` | Commentaires |
| `reports` | Signalements |
| `follows` | Abonnements |
| `direct_messages` | Messages directs chiffrés |
| `groups` | Groupes (promotion, résidence, filière, custom) |
| `group_members` | Membres des groupes |
| `group_messages` | Messages de groupe avec fichiers joints |

## Rôles utilisateurs

| Rôle | Permissions clés |
|---|---|
| **Étudiant** | Publier, liker, commenter, suivre, DM, créer des groupes |
| **Modérateur** | Idem + supprimer tout post, bannir des utilisateurs |
| **Admin** | Idem + assigner des rôles |
| **Alumni** | Mêmes droits qu'étudiant |
| **Concierge** | Consultation des incidents uniquement |

## Installation et lancement

### Prérequis

- **Node.js** ≥ 18
- **PostgreSQL** ≥ 14
- **Flutter SDK** ≥ 3.0.0
- **Android Studio** (avec émulateur) ou appareil physique

### 1. Base de données

```bash
# Créer la base
createdb yansnet_db

# Importer le dump
psql -U postgres -d yansnet_db -f "APPLICATION & BASE DE DONNES/yansnet_backup.sql"
```

### 2. Backend

```bash
cd "APPLICATION & BASE DE DONNES/yansnet/backend"
npm install
```

Configurer le fichier `.env` :

```env
PORT=5000
NODE_ENV=development
DB_HOST=localhost
DB_PORT=5432
DB_NAME=yansnet_db
DB_USER=postgres
DB_PASSWORD=votre_mot_de_passe
JWT_SECRET=votre_secret_jwt
JWT_EXPIRES_IN=30d
MAX_PHOTO_SIZE=3145728
MAX_VIDEO_SIZE=20971520
MAX_FILE_SIZE=52428800
```

```bash
# Lancer le serveur
npm start

# Ou en mode développement (hot reload)
npm run dev
```

Le serveur démarre sur `http://localhost:5000`.

### 3. Application mobile

```bash
cd "APPLICATION & BASE DE DONNES/yansnet/frontend"
flutter pub get
flutter run
```

> **Note pour l'émulateur Android** : L'app utilise `localhost:5000` comme URL backend. Sur l'émulateur Android, `localhost` pointe vers l'émulateur lui-même. Il faut remplacer par `10.0.2.2:5000` dans `lib/utils/constants.dart` pour atteindre le serveur hôte.

## Routes API

| Préfixe | Description |
|---|---|
| `POST /api/auth/login` | Connexion |
| `POST /api/auth/register` | Inscription |
| `GET /api/posts/feed` | Fil d'actualité |
| `/api/posts` | CRUD publications |
| `/api/users` | Gestion des profils |
| `/api/messages` | Messages directs |
| `/api/groups` | Groupes de discussion |
| `/api/comments` | Commentaires |
| `/api/replies` | Réponses |
| `/api/notifications` | Notifications |
| `/api/reports` | Signalements |
| `/api/admin` | Administration |
| `GET /uploads/:filename` | Fichiers médias (inline ou téléchargement) |
| `GET /download/:filename` | Téléchargement forcé |

## Contexte académique

Ce projet est réalisé dans le cadre du module **ETSIA** (Projets X4) à l'Institut UCAC-ICAM. Il suit une méthodologie Agile avec :

- **Phase 1** : Ingénierie des exigences & Plan Projet
- **Phase 2** : Réalisation (sprints hebdomadaires avec Sprint Planning, Daily, Démonstration)
- **Suivi** : Jira pour le backlog et les sprints

### Indicateurs cibles

| Indicateur | Cible |
|---|---|
| Taux d'adoption | ≥ 60 % de l'effectif étudiant sous 3 mois |
| Durée d'utilisation | ≥ 15 min/semaine par utilisateur |
| Disponibilité | > 97 % |

## Licence

Projet académique — UCAC-ICAM, Promotion X2027.
