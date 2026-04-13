# KaraOrKey

A networked karaoke application that turns any screen into a karaoke stage. A TV display syncs in real-time with DJ/singer clients on mobile devices — all over your local network.

## Features

- **AI-powered stem separation** — Downloads songs from YouTube and uses [Demucs](https://github.com/facebookresearch/demucs) to strip vocals and produce a clean instrumental backing track
- **Synchronized lyrics** — Fetches `.lrc` timed lyrics via the LRCLIB API, with phonetic romanization for non-Latin scripts (K-Pop, Japanese, etc.)
- **Multi-room support** — Create public or password-protected karaoke rooms; one TV display per room, unlimited singers
- **Real-time sync** — All connected clients see the same queue, playback state, and lyrics via WebSocket (Socket.IO)
- **Queue management** — Add, remove, and reorder songs; auto-play next track
- **Cross-platform** — Flutter web UI runs on any browser; connect from phones, tablets, or laptops

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Backend | Python 3, Flask, Flask-SocketIO, Eventlet |
| Frontend | Flutter (compiled to WebAssembly) |
| Audio download | yt-dlp |
| Stem separation | Demucs (Hybrid Transformer) |
| Audio processing | FFmpeg |
| Lyrics | LRCLIB API |
| Phonetics | Unidecode |

## Requirements

- Python 3.8+
- [FFmpeg](https://ffmpeg.org/download.html) — must be available in your system `PATH`
- Windows (the included launcher is a `.bat` script)

## Getting Started

1. **Clone the repository**

   ```bash
   git clone https://github.com/your-username/KaraOrKey.git
   cd KaraOrKey
   ```

2. **Install FFmpeg** and ensure it is in your system `PATH`.

3. **Run the launcher**

   Double-click `start.bat` or run it from a terminal:

   ```cmd
   start.bat
   ```

   On first run, this will:
   - Create a Python virtual environment under `backend/venv/`
   - Install all Python dependencies from `backend/requirements.txt`
   - Start the backend server on `http://localhost:5000`
   - Start the web UI on `http://localhost:8080`
   - Print your local network IP so other devices can connect

4. **Connect devices**

   - Open `http://localhost:8080` on the TV/main screen
   - On phones or other devices, open `http://<your-local-ip>:8080`

## How It Works

### Song Processing Pipeline

```
YouTube URL
    → yt-dlp         (download best audio)
    → FFmpeg          (convert to WAV)
    → Demucs          (AI stem separation)
    → LRCLIB API      (fetch synchronized lyrics)
    → songs/{Artist - Track}/
          accompaniment.wav   (instrumental backing track)
          vocals.wav          (extracted vocals)
          lyrics.lrc          (timed lyrics with phonetics)
```

Stem separation is CPU-intensive and typically takes 1–3 minutes per song.

### Room Architecture

```
Mobile DJ/Singer  ──┐
Mobile DJ/Singer  ──┼──▶  Flask-SocketIO Server  ──▶  TV Display
Mobile DJ/Singer  ──┘         (localhost:5000)
```

All playback commands, queue changes, and state updates are broadcast in real-time to every client in the room.

## API Reference

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/rooms` | List all rooms |
| POST | `/api/create_room` | Create a room (optional password) |
| POST | `/api/delete_room` | Delete a room |
| GET | `/api/songs` | List processed songs |
| GET | `/api/search?q=` | Search YouTube |
| POST | `/api/add_youtube` | Add a YouTube URL to the processing queue |
| POST | `/api/cancel` | Cancel an active download/processing job |
| GET | `/api/play/<song_id>/<file_type>` | Stream audio or lyrics file |

### WebSocket Events

| Event | Description |
|-------|-------------|
| `join_karaoke_room` | Join a room as TV or DJ |
| `command_play` / `command_stop` | Control playback |
| `add_to_queue` / `remove_from_queue` / `reorder_queue` | Manage song queue |
| `play_next` | Skip to next song |
| `sync_state` | Broadcast room state to all clients |
| `rooms_updated` | Notify clients of room list changes |

## Project Structure

```
KaraOrKey/
├── start.bat               # Windows launcher
├── backend/
│   ├── server.py           # Flask + Socket.IO server
│   ├── factory.py          # Song processing pipeline
│   ├── requirements.txt    # Python dependencies
│   ├── songs/              # Processed song library
│   └── temp/               # Temporary processing files
└── web/                    # Flutter web build (static)
    ├── index.html
    ├── main.dart.js
    └── ...
```

## License

MIT
