# YANSNET — Réseau Social UCAC-ICAM Yansoki

> Écosystème numérique pour les étudiants et le personnel du campus UCAC-ICAM de Yansoki, Douala – Cameroun.

## Présentation

YANSNET est un réseau social local conçu pour interconnecter la communauté du campus UCAC-ICAM. Le projet comprend **quatre composants** :

| Composant | Stack |
|---|---|---|
| **Application mobile** | Flutter (iOS & Android) |
| **Backend API** | Node.js / Express 5 + PostgreSQL |
| **Site d'administration** | React (Vite + Tailwind) + NestJS + Prisma |
| **Backend de modération IA** | Python / Flask + Transformers (HuggingFace) |

---

## Équipe — Groupe Projet 15

| Nom | Rôle |
|---|---|
| MAKONGNE DEFFO July Merveille | Développeur |
| NANKAP NDIZEU Loïc Aurel | Développeur |
| NKOULOU Joseph Emmanuel | Développeur |
| NOUNGOUA NOUNGOUA Teddy Steven | Développeur |
| TOFA DEFFO Lionel Junior | Développeur |

**Promotion X2027 — Projet ETSIA X4 — UCAC-ICAM Douala**

---

## Structure du dépôt

```
PROJET_ETSIA/
│
├── PARTIE 1 - SPECIFICATION DES EXIGENCES/
│   ├── DOSSIER D'ANALYSE ET DE CONCEPTION/
│   │   ├── DOCUMENT DE SPECIFICATIONS (SRS).pdf
│   │   ├── BILAN MVP.pdf
│   │   ├── BPMN Yansnet.png
│   │   ├── Dataflow.png
│   │   └── Workflow.png
│   └── DOSSIER DE QUALITE ET DE GESTION/
│       ├── CHECKLIST.pdf
│       ├── MATRICE DE TRACABILITE DES EXIGENCES.xlsx
│       ├── PLAN DE TESTS.pdf
│       └── Jira Timeline.jpeg / Jira Timeline 2.jpeg
│
├── PARTIE 2 - PLAN PROJET/
│   ├── Gestion de la durée/         ← Gantt (.mpp) + planning.png
│   ├── Gestion de la portée/        ← Gestion de la Portee.pdf
│   ├── Gestion des couts/           ← Budget (.xlsx + .pdf) + BUSINESS PLAN.pdf
│   ├── Gestion des risques/         ← Gestion des Risques.xlsx
│   ├── Gestion des ressources humaines/   ← Matrice RACI + Organigramme
│   ├── Gestion des parties prenantes/     ← Gestion des parties prenantes.xlsx
│   ├── Gestion de la communication/       ← Matrice de communication.xlsx
│   ├── Gestion de l'approvisionnement/    ← Gestion du changement et intégration.pdf
│   ├── Présentation ETSIA.pptx
│   └── PRESENTATION YANSNET.mp4
│
└── PARTIE 3 - PHASE DE REALISATION/
    ├── 1 - PHASE DE REALISATION/
    │   ├── Code/
    │   │   ├── app/
    │   │   │   ├── yansnet/
    │   │   │   │   ├── frontend/       ← App mobile Flutter
    │   │   │   │   ├── backend/        ← API Node.js / Express
    │   │   │   │   ├── yansnet_backup.sql
    │   │   │   │   └── migration_group_messages.sql
    │   │   │   └── moderation_backend/ ← Microservice IA (Python/Flask)
    │   │   └── site-admin/
    │   │       └── web-app/
    │   │           ├── frontend/       ← Dashboard React / Vite / Tailwind
    │   │           └── backend/        ← API NestJS / Prisma / PostgreSQL
    │   ├── App Screenshots/            ← feed, login, messages, groupes…
    │   ├── Documentation API - YANSNET Groupe 15.pdf
    │   └── INSTRUCTIONS D'INSTALLATION ET DE CONFIGURATION.pdf
    │
    ├── 2 - PHASE DE TESTS FONCTIONNELS/
    │   ├── Stratégie de tests - YANSNET Groupe 15.pdf
    │   ├── MATRICE DE TRACABILITE - YANSNET GROUPE 15.xlsx
    │   └── Tests 1.png / Tests 2.png
    │
    ├── 3 - PHASE DE RETOURS UTILISATEURS/
    │   ├── Retours Utilisateurs - YANSNET Groupe 15.pdf
    │   └── Vidéo Commerciale - Yansnet GROUPE 15.mp4
    │
    └── 4 - PHASE DE GESTION DE PROJET/
        ├── Sprint 1/   ← Backlog + captures Jira + Sprint1.xlsx
        ├── Sprint 2/   ← Backlog + timeline + Sprint2.xlsx + Vidéo Sprint 1.mp4
        ├── Bilan de Projet - YANSNET GROUPE 15.pdf
        ├── Registre des Risques - YANSNET GROUPE 15.pdf
        ├── Budget - YANSNET Groupe 15.xlsx
        └── Planning Réel - YANSNET GROUPE 15.mpp
```

---

## Stack technique détaillée

### Application mobile — Flutter (`app/yansnet/frontend/`)

| Technologie | Version | Usage |
|---|---|---|
| Flutter | ≥ 3.10.0 | Framework UI cross-platform (iOS, Android) |
| Provider | ^6.1.2 | Gestion d'état |
| Dio | ^5.4.3 | Client HTTP |
| Socket.IO Client | ^2.0.3 | Messagerie temps réel |
| firebase_core / firebase_messaging | ^3.0.0 / ^15.0.2 | Notifications push |
| flutter_secure_storage | — | Stockage sécurisé JWT |
| image_picker / file_picker | — | Upload de médias et documents |
| video_player / video_compress | — | Lecture et compression vidéo |

### Backend API — Node.js (`app/yansnet/backend/`)

| Technologie | Version | Usage |
|---|---|---|
| Node.js / Express | ≥ 18 / ^5.2.1 | Serveur HTTP |
| PostgreSQL (pg) | ^8.20.0 | Base de données relationnelle |
| Socket.IO | ^4.8.3 | WebSocket temps réel |
| JWT (jsonwebtoken) | ^9.0.3 | Authentification (sessions 30 jours) |
| bcryptjs | ^3.0.3 | Hachage des mots de passe |
| Multer | ^2.1.1 | Upload de fichiers |
| firebase-admin | ^11.11.1 | Envoi de notifications push |
| Helmet / CORS | — | Sécurité HTTP |
| bad-words | ^4.0.0 | Filtre de contenu textuel |
| express-rate-limit | ^8.5.2 | Limitation de débit |
| axios | ^1.18.1 | Appels vers le microservice de modération IA |

### Backend de modération IA (`app/moderation_backend/`)

| Technologie | Usage |
|---|---|
| Python / Flask | Microservice HTTP |
| Flask-CORS | Autorisation des appels cross-origin |
| Transformers (HuggingFace) | Modèle de classification de contenu |
| PyTorch | Inférence du modèle |
| Pillow | Traitement des images soumises à modération |

### Site d'administration (`site-admin/web-app/`)

**Frontend**

| Technologie | Version | Usage |
|---|---|---|
| React + Vite | — | Interface utilisateur / bundler |
| Tailwind CSS v4 | ^4.3.0 | Styles |
| shadcn/ui + Base UI | — | Composants UI |
| TanStack Table | ^8.21.3 | Tableaux de données |
| Lucide React | — | Icônes |
| next-themes | ^0.4.6 | Gestion dark / light mode |

**Backend**

| Technologie | Version | Usage |
|---|---|---|
| NestJS | ^11.0.1 | Framework Node.js structuré |
| Prisma | ^6.19.3 | ORM + migrations PostgreSQL |
| @nestjs/jwt | ^11.0.2 | Authentification JWT |

---

## Fonctionnalités livrées (MVP)

- Inscription / Connexion / Déconnexion (JWT, session 30 jours, session unique par appareil)
- Modification du profil (avatar, bio, nom d'usage)
- Publication de photos (≤ 3 Mo) avec légendes et tags `^tag`
- Fil d'actualité avec pagination infinie
- Likes (bouton dédié ou triple tap), commentaires (≤ 500 caractères)
- Signalements avec file de modération (suspension auto au 3e signalement)
- **Modération automatique du contenu via IA** (microservice Flask + Transformers)
- Système de follow / unfollow avec notifications push (Firebase)
- Messagerie directe (DM) avec édition, suppression, citation et épinglage
- Groupes de discussion : création, invitation, administration, partage de fichiers (≤ 50 Mo)
- Canaux par promotion, résidence et filière
- Publications officielles UCAC-ICAM
- Dashboard d'administration (gestion des signalements, des rôles, des utilisateurs)

---

## Base de données — PostgreSQL

| Table | Description |
|---|---|
| `roles` | Matrice des droits (étudiant, modérateur, admin, alumni, concierge) |
| `users` | Comptes utilisateurs (UUID, email, profil) |
| `sessions` | Refresh tokens |
| `posts` | Publications (texte, image, vidéo) |
| `likes` | Likes sur les publications |
| `comments` | Commentaires |
| `reports` | Signalements |
| `follows` | Abonnements |
| `direct_messages` | Messages directs |
| `groups` | Groupes (promotion, résidence, filière, custom) |
| `group_members` | Membres des groupes |
| `group_messages` | Messages de groupe avec fichiers joints |

> Dump complet : `app/yansnet_backup.sql`  
> Migration messages de groupe : `app/yansnet/migration_group_messages.sql`

---

## Rôles utilisateurs

| Rôle | Permissions clés |
|---|---|
| **Étudiant** | Publier, liker, commenter, suivre, DM, créer des groupes |
| **Modérateur** | Idem + supprimer tout post, bannir des utilisateurs |
| **Admin** | Idem + assigner des rôles, accès dashboard |
| **Alumni** | Mêmes droits qu'étudiant |
| **Concierge** | Consultation des incidents uniquement |

---

## Installation et lancement

> Instructions complètes et détaillées dans `1 - PHASE DE REALISATION/INSTRUCTIONS D'INSTALLATION ET DE CONFIGURATION.pdf`.

### Prérequis

- **Node.js** ≥ 18
- **PostgreSQL** ≥ 14
- **Flutter SDK** ≥ 3.10.0
- **Python** ≥ 3.10 (microservice de modération)
- **Android Studio** (avec émulateur) ou appareil physique Android

### 1. Base de données

```bash
createdb yansnet_db
psql -U postgres -d yansnet_db -f app/yansnet_backup.sql
psql -U postgres -d yansnet_db -f app/yansnet/migration_group_messages.sql
```

### 2. Backend API

```bash
cd app/yansnet/backend
npm install
```

Créer le fichier `.env` :

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
npm run dev    # développement (hot reload via nodemon)
npm start      # production
```

Serveur disponible sur `http://localhost:5000`.

### 3. Microservice de modération IA

```bash
cd app/moderation_backend
python -m venv venv
venv\Scripts\activate       # Windows
pip install -r requirements.txt
python app.py
```

### 4. Application mobile Flutter

```bash
cd app/yansnet/frontend
flutter pub get
flutter run
```

> **Émulateur Android** : remplacer `localhost` par `10.0.2.2` dans `lib/utils/constants.dart` pour atteindre le backend depuis l'émulateur.

### 5. Site d'administration — backend NestJS

```bash
cd site-admin/web-app/backend
npm install
npx prisma generate
npm run start:dev
```

### 6. Site d'administration — frontend React

```bash
cd site-admin/web-app/frontend
npm install
npm run dev
```

---

## Principales routes API

| Route | Description |
|---|---|
| `POST /api/auth/login` | Connexion |
| `POST /api/auth/register` | Inscription |
| `GET /api/posts/feed` | Fil d'actualité (paginé) |
| `/api/posts` | CRUD publications |
| `/api/users` | Gestion des profils |
| `/api/messages` | Messages directs |
| `/api/groups` | Groupes de discussion |
| `/api/comments` | Commentaires |
| `/api/notifications` | Notifications |
| `/api/reports` | Signalements |
| `/api/admin` | Administration |
| `GET /uploads/:filename` | Fichiers médias (inline) |
| `GET /download/:filename` | Téléchargement forcé |

Documentation complète : `1 - PHASE DE REALISATION/Documentation API - YANSNET Groupe 15.pdf`

---

## Résultats

| Indicateur | Valeur |
|---|---|
| Tests unitaires exécutés | 39 |
| Tests réussis | 38 (97,4 %) |
| Bugs bloquants signalés | 0 |
| Répondants (retours utilisateurs) | 27 |
| Note de satisfaction moyenne | 4,13 / 5 |
| Taux de recommandation | 88,9 % |

---

## Points en cours / Roadmap V2

### À finaliser avant production

- Récupération de mot de passe par email (EF-004)
- Intégration SSO Google + Active Directory (EF-001)
- Matrice des droits par rôle formalisée (EF-007)
- Chiffrement des données au repos (ES-002)
- Archivage des conversations après réinstallation (EF-020)
- Politique de rétention des données / suppression de compte (EF-005)
- Optimisation des temps de chargement sous charge (ET-001)

### Roadmap V2

- Tests de charge à 125 000 utilisateurs simultanés
- Mode dégradé offline / LAN
- Mises à jour OTA via réseau de l'institut
- Module Alumni (activités COCFET)
- Analyse sentimentale pour détection de détresse étudiante
- Mécanisme d'alerte rapide
- Connexion multi-appareils
- Géolocalisation des publications

---

## Contexte académique

Projet réalisé dans le cadre du module **ETSIA X4** à l'UCAC-ICAM (Douala).  
Méthodologie Agile — 2 sprints — suivi Jira.

| Phase | Livrables |
|---|---|
| Phase 1 | SRS, BPMN, Dataflow, Checklist, Matrice de traçabilité |
| Phase 2 | Gantt, RACI, Budget, Registre des risques, Business plan, Présentation |
| Phase 3 | Code, tests (39 cas), retours utilisateurs (27 répondants), bilan de projet |

---

*Projet académique — UCAC-ICAM Douala, Promotion X2027.*
