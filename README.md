# KaraOrKey

A networked, AI-powered karaoke system that lets you host a karaoke party over your local Wi-Fi. One screen acts as the TV display; any number of phones or laptops connect as DJ remotes.

## How it works

1. A DJ searches YouTube and adds songs to the queue.
2. The backend downloads the audio, separates vocals from the instrumental using **Demucs** (Facebook Research AI), and fetches synchronized lyrics from **LRCLIB**.
3. The TV screen plays the instrumental track with scrolling, highlighted lyrics in real time.
4. Multiple rooms can run simultaneously, each with an optional password.

## Features

- YouTube search and one-click song import
- AI vocal/instrumental stem separation (Demucs HTDemucs model)
- Synchronized scrolling lyrics with phonetic romanization for K-Pop, Japanese, etc.
- Public or password-protected rooms
- Real-time queue management (add, remove, reorder) via WebSocket
- Multi-device sync — TV display + unlimited DJ clients
- Works on any browser (desktop, mobile, tablet)

## Tech stack

| Layer | Technology |
|---|---|
| Backend | Python 3.8+, Flask, Flask-SocketIO, Eventlet |
| Audio processing | Demucs, FFmpeg, yt-dlp |
| Lyrics | LRCLIB API, Unidecode |
| Frontend | Flutter (compiled to WebAssembly) |
| Realtime | Socket.IO |

## Prerequisites

- **Python 3.8+**
- **FFmpeg** — must be available in your system `PATH`
- **Flutter SDK** — required to rebuild the web UI after cloning (see below)
- **Windows** (the launcher script is `.bat`; manual setup works cross-platform)

## Setup after cloning

The compiled Flutter web assets are not stored in this repository (they are too large). You need to build them once before running the app.

**1. Build the Flutter web app**

```bash
cd app
flutter pub get
flutter build web --release
```

**2. Copy the build output into the distribution folder**

```bash
# Windows (PowerShell)
Copy-Item -Recurse -Force app\build\web\* KaraOrKey\web\

# Linux / macOS
cp -r app/build/web/* KaraOrKey/web/
```

**3. Run the app**

```bat
KaraOrKey\start.bat
```

The script will:
1. Create a Python virtual environment on first run
2. Install all dependencies automatically
3. Start the Flask backend on `http://localhost:5000`
4. Serve the web UI on `http://localhost:8080`
5. Print your local network IP

Open `http://localhost:8080` on the TV screen. Other devices connect using `http://<your-local-ip>:8080`.

## Manual backend setup (cross-platform)

```bash
cd KaraOrKey/backend
python -m venv venv

# Windows
venv\Scripts\activate.bat
# Linux / macOS
source venv/bin/activate

pip install -r requirements.txt
python server.py
```

In a second terminal:

```bash
cd KaraOrKey/web
python -m http.server 8080
```

## Project structure

```
KaraOrKey-repo/
├── app/                    # Flutter app source code
│   ├── lib/main.dart       # Full Flutter UI (TV mode, DJ mode, queue, playback)
│   └── pubspec.yaml        # Flutter dependencies
├── backend/                # Python backend source code
│   ├── server.py           # Flask + Socket.IO server, room management
│   └── factory.py          # Song processing pipeline
└── KaraOrKey/              # Ready-to-run distribution folder
    ├── start.bat           # Windows launcher
    ├── backend/            # Backend copy with requirements.txt
    └── web/                # Serves the Flutter web app (populated after build)
```

> `pretrained_models/` (Demucs weights) and song libraries are not committed — they are generated at runtime or downloaded automatically by Demucs on first use.

## API reference

### HTTP

| Method | Route | Description |
|---|---|---|
| GET | `/api/rooms` | List all rooms |
| POST | `/api/create_room` | Create a room (optional password) |
| POST | `/api/delete_room` | Delete a room |
| GET | `/api/songs` | List processed songs |
| GET | `/api/search?q=` | Search YouTube |
| POST | `/api/add_youtube` | Queue a YouTube URL for processing |
| POST | `/api/cancel` | Cancel the active processing job |
| GET | `/api/play/<song_id>/<file>` | Stream audio or lyrics |

### WebSocket events

| Event | Direction | Description |
|---|---|---|
| `join_karaoke_room` | Client → Server | Join a room as TV or DJ |
| `command_play` / `command_stop` | DJ → Server → TV | Playback control |
| `add_to_queue` / `remove_from_queue` / `reorder_queue` | DJ → Server | Queue management |
| `play_next` | DJ → Server | Skip to next song |
| `sync_state` | Server → All | Broadcast room state |

## Song processing pipeline

```
YouTube URL
    → yt-dlp (download best audio)
    → FFmpeg (convert to WAV)
    → Demucs (AI stem separation: vocals + instrumental)
    → LRCLIB API (fetch timed lyrics)
    → Unidecode (add phonetic romanization)
    → KaraOrKey/backend/songs/{Artist - Track}/
          accompaniment.wav
          vocals.wav
          lyrics.lrc
```

Processing takes roughly 1–3 minutes per song depending on hardware.

## License

MIT
