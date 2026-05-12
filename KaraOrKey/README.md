# KaraOrKey

Application karaoké réseau en temps réel. Une TV affiche les paroles et joue la musique pour le public ; chaque chanteur utilise son téléphone comme micro et monitor personnel — zéro latence.

## Fonctionnalités

- **Séparation de stems par IA** — télécharge depuis YouTube via `yt-dlp` et utilise [Demucs](https://github.com/facebookresearch/demucs) pour isoler les voix et produire une piste instrumentale propre
- **Paroles synchronisées** — récupérées via l'API [LRCLIB](https://lrclib.net), avec romanisation phonétique pour les scripts non-latins (K-Pop, japonais, etc.)
- **Monitor chanteur** — le téléphone DJ joue la piste d'accompagnement localement en même temps que la TV ; le chanteur entend la musique + sa propre voix sans aucune latence réseau
- **Multi-salles** — créez des salles publiques ou protégées par mot de passe ; une TV par salle, DJ illimités
- **Sync temps réel** — file d'attente, état de lecture et paroles partagés via WebSocket (Socket.IO)
- **Gestion de la bibliothèque** — ajout, suppression de chansons ; persistance des salles entre redémarrages
- **Cross-platform** — interface Flutter compilée en WebAssembly, accessible depuis n'importe quel navigateur

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
   # Puis copier le résultat dans KaraOrKey/web/
   xcopy /E /Y build\web\* ..\KaraOrKey\web\
   ```

4. **Lancer l'application**

   Double-cliquer sur `KaraOrKey/start.bat` ou l'exécuter depuis un terminal :

   ```cmd
   start.bat
   ```

   Au premier lancement, le script :
   - Crée un environnement virtuel Python dans `backend/venv/`
   - Installe toutes les dépendances Python
   - Démarre le serveur backend sur `http://localhost:5000`
   - Démarre l'interface web sur `http://localhost:8080`

5. **Connecter les appareils**

   - Ouvrir `http://localhost:8080` sur la TV / l'écran principal
   - Sur les téléphones, ouvrir l'application Flutter et entrer l'IP locale du PC (ex: `192.168.1.45`)

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

La séparation est intensive en CPU et prend typiquement 1 à 3 minutes par chanson.

### Architecture monitor chanteur

```
Téléphone DJ ──► backing track (local, 0 ms de latence)
              ──► micro       (local, 0 ms de latence)
              ──► commandes WebSocket ──► Serveur Flask-SocketIO ──► TV
                                                                    (backing track + paroles)
```

Le téléphone du DJ joue la musique et les paroles en local — le chanteur a son propre retour scène. La TV diffuse la même piste pour le public et affiche les paroles en grand.

### Architecture multi-salles

```
Téléphone DJ  ──┐
Téléphone DJ  ──┼──► Serveur Flask-SocketIO ──► TV (Écran)
Téléphone DJ  ──┘        (localhost:5000)
```

## API

| Méthode | Endpoint | Description |
|---------|----------|-------------|
| GET | `/api/rooms` | Liste des salles |
| POST | `/api/create_room` | Créer une salle (mot de passe optionnel) |
| POST | `/api/delete_room` | Supprimer une salle |
| GET | `/api/songs` | Liste des chansons traitées |
| GET | `/api/search?q=` | Recherche YouTube |
| POST | `/api/add_youtube` | Ajouter une URL YouTube à la file de traitement |
| POST | `/api/cancel` | Annuler un téléchargement en cours |
| POST | `/api/delete_song` | Supprimer une chanson de la bibliothèque |
| GET | `/api/play/<song_id>/<file_type>` | Streamer un fichier audio ou les paroles |

### Événements WebSocket

| Événement | Description |
|-----------|-------------|
| `join_karaoke_room` | Rejoindre une salle (TV ou DJ) |
| `command_play` / `command_stop` | Contrôler la lecture |
| `start_song` / `stop_song` | Déclenché vers tous les clients de la salle |
| `add_to_queue` / `remove_from_queue` / `reorder_queue` | Gérer la file |
| `play_next` | Passer au titre suivant |
| `sync_state` | Diffuse l'état complet de la salle |
| `rooms_updated` | Notifie les clients d'un changement de liste de salles |

## Structure du projet

```
KaraOrKey/
├── start.bat                   # Lanceur Windows
├── backend/
│   ├── server.py               # Serveur Flask + Socket.IO
│   ├── factory.py              # Pipeline de traitement des chansons
│   ├── requirements.txt        # Dépendances Python
│   ├── rooms.json              # État des salles (généré au runtime, gitignored)
│   ├── songs/                  # Bibliothèque de chansons (gitignored)
│   └── temp/                   # Fichiers temporaires (gitignored)
└── web/                        # Build Flutter WebAssembly (static)
    ├── index.html
    ├── main.dart.js / *.wasm   # Générés par flutter build web (gitignored)
    └── ...

app/                            # Sources Flutter
├── lib/
│   ├── main.dart               # Point d'entrée de l'application
│   ├── config.dart             # URL du serveur (variable globale)
│   ├── models/
│   │   └── lyric_line.dart     # Modèle d'une ligne de paroles
│   ├── screens/
│   │   ├── server_setup_screen.dart    # Connexion au serveur
│   │   ├── role_selection_screen.dart  # Choix DJ / TV
│   │   ├── room_selection_screen.dart  # Liste et gestion des salles
│   │   ├── mic_remote_screen.dart      # Panneau DJ + monitor chanteur
│   │   └── tv_player_screen.dart       # Écran TV (paroles + progression)
│   └── widgets/
│       └── youtube_search_dialog.dart  # Recherche et ajout YouTube
└── pubspec.yaml
```

## Licence

MIT
