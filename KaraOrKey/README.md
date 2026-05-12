# KaraOrKey

Application karaoké réseau en temps réel. Une TV affiche les paroles et joue la musique pour le public ; chaque chanteur utilise son téléphone comme micro et monitor personnel — zéro latence.

## Fonctionnalités

- **Séparation de stems par IA** — télécharge depuis YouTube via `yt-dlp` et utilise [Demucs](https://github.com/facebookresearch/demucs) pour isoler les voix et produire une piste instrumentale propre
- **Paroles synchronisées** — récupérées via l'API [LRCLIB](https://lrclib.net), avec romanisation phonétique pour les scripts non-latins (K-Pop, japonais, etc.)
- **Monitor chanteur** — le téléphone DJ joue la piste d'accompagnement localement avec les paroles en temps réel ; latence zéro, pas de streaming réseau
- **Mode "Je chante"** — chaque DJ choisit s'il est le chanteur actif (lecture locale + paroles) ou simplement opérateur de queue (sans audio)
- **Contrôle complet** — lecture, pause, reprise, stop, chanson suivante, déplacement dans la piste (seek)
- **Multi-salles** — salles publiques ou protégées par mot de passe, persistées entre redémarrages ; une TV par salle, DJ illimités
- **Sync temps réel** — queue, état de lecture et paroles partagés via WebSocket (Socket.IO) avec reconnexion automatique
- **Correction de drift** — la TV émet sa position toutes les 5 s ; les téléphones DJ se resynchronisent automatiquement si l'écart dépasse 500 ms
- **Bibliothèque** — triée alphabétiquement, avec ajout et suppression de chansons

## Stack technique

| Couche | Technologie |
|--------|-------------|
| Backend | Python 3, Flask, Flask-SocketIO, Eventlet |
| Frontend | Flutter (compilé en WebAssembly) |
| Téléchargement audio | yt-dlp |
| Séparation de stems | Demucs (Hybrid Transformer) |
| Traitement audio | FFmpeg |
| Paroles | LRCLIB API |
| Phonétique | Unidecode |

## Prérequis

- Python 3.8+
- [FFmpeg](https://ffmpeg.org/download.html) — doit être accessible dans le `PATH` système
- Windows (le lanceur fourni est un script `.bat`)

## Démarrage

1. **Cloner le dépôt**

   ```bash
   git clone https://github.com/MarcVo00/KaraOrKey.git
   cd KaraOrKey
   ```

2. **Installer FFmpeg** et s'assurer qu'il est dans le `PATH`.

3. **Construire l'interface Flutter** (nécessaire après un clone, les fichiers `.wasm` et `main.dart.js` sont dans le `.gitignore`)

   ```bash
   cd app
   flutter build web --wasm
   xcopy /E /Y build\web\* ..\KaraOrKey\web\
   ```

4. **Lancer l'application**

   Double-cliquer sur `KaraOrKey/start.bat` ou l'exécuter depuis un terminal :

   ```cmd
   start.bat
   ```

   Le script crée l'environnement Python, installe les dépendances, démarre les deux serveurs et **affiche l'adresse IP locale** à utiliser sur les téléphones.

5. **Connecter les appareils**

   - Ouvrir `http://localhost:8080` sur la TV / l'écran principal
   - Sur les téléphones, lancer l'app Flutter et entrer l'IP affichée par `start.bat`

## Comment ça marche

### Pipeline de traitement d'une chanson

```
URL YouTube
    → yt-dlp          (téléchargement audio)
    → FFmpeg           (conversion en WAV)
    → Demucs           (séparation IA voix/instru)
    → LRCLIB API       (paroles synchronisées + phonétique)
    → songs/{Artiste - Titre}/
          accompaniment.wav   (piste instrumentale)
          vocals.wav          (voix extraites)
          lyrics.lrc          (paroles horodatées)
```

La séparation prend typiquement 1 à 3 minutes par chanson.

### Architecture monitor chanteur

```
Téléphone DJ ──► backing track (local, 0 ms latence) + paroles sync
              ──► micro        (local, 0 ms latence)
              ──► commandes WebSocket ──► Serveur ──► TV (backing track + paroles + queue)
```

Le téléphone joue la musique et affiche les paroles en local — le chanteur a son propre retour. La TV diffuse la même piste pour le public.

### Correction de drift

```
TV ──► position_sync (toutes les 5s) ──► Serveur ──► DJ phones
                                                        └── |drift| > 500ms ? seek()
```

### Architecture multi-salles

```
Téléphone DJ  ──┐
Téléphone DJ  ──┼──► Serveur Flask-SocketIO ──► TV (Écran)
Téléphone DJ  ──┘        (localhost:5000)
```

## Utilisation

### Panneau DJ

| Action | Geste |
|--------|-------|
| Lancer une chanson | Appuyer sur ✚ dans la liste |
| Mettre en file d'attente | Appuyer sur ✚ quand une chanson joue déjà |
| Réordonner la queue | Maintenir appuyé puis glisser |
| Pause / Reprise | Bouton ⏸ / ▶ dans la barre de statut |
| Arrêter | Bouton ⏹ (confirmation demandée) |
| Chanson suivante | Bouton ⏭ |
| Se déplacer dans la piste | Glisser la barre de progression |
| Activer le micro | Appuyer sur le bouton micro |
| Volume musique | Icône 🎵 → slider |
| Mode "Je chante" | Toggle dans l'AppBar |

### Écran TV

| Action | Geste |
|--------|-------|
| Régler le volume | Appuyer sur l'écran → slider |
| Se déplacer dans la piste | Glisser la barre de progression |
| Quitter la salle | Bouton retour → confirmation |

## API

| Méthode | Endpoint | Description |
|---------|----------|-------------|
| GET | `/api/rooms` | Liste des salles |
| POST | `/api/create_room` | Créer une salle (mot de passe optionnel) |
| POST | `/api/delete_room` | Supprimer une salle |
| GET | `/api/songs` | Liste des chansons (triée alphabétiquement) |
| GET | `/api/search?q=` | Recherche YouTube |
| POST | `/api/add_youtube` | Ajouter une URL YouTube à la file de traitement |
| POST | `/api/cancel` | Annuler un téléchargement en cours |
| POST | `/api/delete_song` | Supprimer une chanson de la bibliothèque |
| GET | `/api/play/<song_id>/<file_type>` | Streamer un fichier audio ou les paroles |

### Événements WebSocket

| Événement | Direction | Description |
|-----------|-----------|-------------|
| `join_karaoke_room` | Client → Serveur | Rejoindre une salle (TV ou DJ) |
| `command_play` | DJ → Serveur | Lancer une chanson |
| `command_stop` | DJ → Serveur | Arrêter la lecture |
| `command_pause` | DJ → Serveur | Mettre en pause |
| `command_resume` | DJ → Serveur | Reprendre |
| `command_seek` | DJ/TV → Serveur | Se déplacer dans la piste |
| `play_next` | DJ/TV → Serveur | Passer au titre suivant |
| `add_to_queue` / `remove_from_queue` / `reorder_queue` | DJ → Serveur | Gérer la file |
| `start_song` / `stop_song` | Serveur → Salle | Déclenché vers tous les clients |
| `pause_song` / `resume_song` | Serveur → Salle | Pause / reprise vers tous |
| `seek_to` | Serveur → Salle | Position cible vers tous |
| `sync_state` | Serveur → Client | État complet de la salle |
| `position_sync` | TV → Serveur → DJs | Position TV pour correction drift |
| `rooms_updated` | Serveur → Tous | Changement de liste de salles |

## Structure du projet

```
KaraOrKey/
├── start.bat                   # Lanceur Windows (affiche l'IP locale)
├── backend/
│   ├── server.py               # Serveur Flask + Socket.IO
│   ├── factory.py              # Pipeline de traitement des chansons
│   ├── requirements.txt        # Dépendances Python
│   ├── rooms.json              # État des salles (généré au runtime, gitignored)
│   ├── songs/                  # Bibliothèque de chansons (gitignored)
│   └── temp/                   # Fichiers temporaires (gitignored)
└── web/                        # Build Flutter WebAssembly (static)
    └── ...                     # Généré par flutter build web (partiellement gitignored)

app/                            # Sources Flutter
├── lib/
│   ├── main.dart               # Point d'entrée
│   ├── config.dart             # URL du serveur
│   ├── models/
│   │   └── lyric_line.dart
│   ├── screens/
│   │   ├── server_setup_screen.dart
│   │   ├── role_selection_screen.dart
│   │   ├── room_selection_screen.dart
│   │   ├── mic_remote_screen.dart      # Panneau DJ
│   │   └── tv_player_screen.dart       # Écran TV
│   └── widgets/
│       └── youtube_search_dialog.dart
└── pubspec.yaml
```

## Licence

MIT
