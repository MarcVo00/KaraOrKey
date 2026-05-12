import eventlet
eventlet.monkey_patch()

from flask import Flask, jsonify, send_from_directory, request
from flask_cors import CORS
from flask_socketio import SocketIO, emit, join_room, leave_room
import os
import uuid
import time
import shutil
import logging
import json

logging.basicConfig(level=logging.INFO, format='[%(asctime)s] %(levelname)s %(message)s', datefmt='%H:%M:%S')

app = Flask(__name__)
CORS(app)
socketio = SocketIO(app, cors_allowed_origins="*", async_mode='eventlet')

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SONGS_DIR = os.path.join(BASE_DIR, "songs")
ROOMS_FILE = os.path.join(BASE_DIR, "rooms.json")
active_downloads = {}
clients = {}

def _empty_room(password=''):
    return {'current_song': None, 'queue': [], 'tv_sid': None, 'dj_sids': [], 'password': password, 'paused': False}

def _load_rooms():
    if os.path.exists(ROOMS_FILE):
        try:
            with open(ROOMS_FILE, 'r', encoding='utf-8') as f:
                saved = json.load(f)
            for name, r in saved.items():
                saved[name] = _empty_room(r.get('password', ''))
            logging.info(f"{len(saved)} salle(s) chargée(s) depuis {ROOMS_FILE}")
            return saved
        except Exception as e:
            logging.error(f"Impossible de lire rooms.json : {e}")
    return {"Salle Publique": _empty_room()}

def _save_rooms():
    try:
        to_save = {name: {'password': data['password']} for name, data in rooms_state.items()}
        with open(ROOMS_FILE, 'w', encoding='utf-8') as f:
            json.dump(to_save, f, ensure_ascii=False, indent=2)
    except Exception as e:
        logging.error(f"Impossible d'écrire rooms.json : {e}")

rooms_state = _load_rooms()

@app.route('/')
def home(): return "<h1>Serveur Karaorkey en ligne ! 🎤</h1>"

# ==========================================
# ROUTES DES SALLES
# ==========================================

@app.route('/api/rooms', methods=['GET'])
def get_rooms():
    return jsonify([{
        'name': name,
        'has_tv': data['tv_sid'] is not None,
        'dj_count': len(data['dj_sids']),
        'is_private': bool(data['password']),
    } for name, data in rooms_state.items()])

@app.route('/api/create_room', methods=['POST'])
def create_room():
    data = request.json
    name = data.get('name', '').strip()
    pwd = data.get('password', '').strip()
    if not name: return jsonify({"error": "Le nom de la salle est requis."}), 400
    if name in rooms_state: return jsonify({"error": "Une salle porte déjà ce nom."}), 400
    rooms_state[name] = _empty_room(pwd)
    _save_rooms()
    socketio.emit('rooms_updated', broadcast=True)
    return jsonify({"message": "Salle créée !"})

@app.route('/api/delete_room', methods=['POST'])
def delete_room():
    data = request.json
    name = data.get('name')
    pwd = data.get('password', '')
    if name not in rooms_state:
        return jsonify({"error": "Salle introuvable."}), 404
    if rooms_state[name]['password'] and rooms_state[name]['password'] != pwd:
        return jsonify({"error": "Mot de passe incorrect !"}), 403
    socketio.emit('room_deleted', to=name)
    del rooms_state[name]
    _save_rooms()
    socketio.emit('rooms_updated', broadcast=True)
    return jsonify({"message": "Salle supprimée."})

# ==========================================
# ROUTES DES MUSIQUES
# ==========================================

@app.route('/api/delete_song', methods=['POST'])
def delete_song():
    song_id = request.json.get('song_id', '').strip()
    if not song_id or '..' in song_id or '/' in song_id or '\\' in song_id:
        return jsonify({"error": "Identifiant invalide."}), 400
    folder_path = os.path.join(SONGS_DIR, song_id)
    if not os.path.isdir(folder_path):
        return jsonify({"error": "Chanson introuvable."}), 404
    try:
        shutil.rmtree(folder_path)
        logging.info(f"Chanson supprimée : {song_id}")
        socketio.emit('library_updated', broadcast=True)
        return jsonify({"message": "Chanson supprimée."})
    except Exception as e:
        logging.error(f"Erreur suppression chanson {song_id}: {e}")
        return jsonify({"error": "Impossible de supprimer la chanson."}), 500

@app.route('/api/songs', methods=['GET'])
def get_songs():
    if not os.path.exists(SONGS_DIR): return jsonify([])
    songs_list = []
    for item in os.listdir(SONGS_DIR):
        folder_path = os.path.join(SONGS_DIR, item)
        if os.path.isdir(folder_path) and os.path.exists(os.path.join(folder_path, "accompaniment.wav")):
            songs_list.append({"id": item, "title": item,
                                "has_lyrics": os.path.exists(os.path.join(folder_path, "lyrics.lrc"))})
    songs_list.sort(key=lambda x: x['title'].lower())
    return jsonify(songs_list)

@app.route('/api/play/<song_id>/<file_type>', methods=['GET'])
def serve_file(song_id, file_type):
    folder_path = os.path.join(SONGS_DIR, song_id)
    if file_type == "audio": return send_from_directory(folder_path, "accompaniment.wav")
    if file_type == "lyrics": return send_from_directory(folder_path, "lyrics.lrc")
    return "Fichier inconnu", 404

@app.route('/api/search', methods=['GET'])
def search_youtube():
    query = request.args.get('q', '')
    if not query: return jsonify([])
    try:
        from yt_dlp import YoutubeDL
        ydl_opts = {'extract_flat': True, 'quiet': True, 'no_warnings': True}
        with YoutubeDL(ydl_opts) as ydl:
            # On cherche plus large pour avoir assez d'options après filtrage
            info = ydl.extract_info(f"ytsearch20:{query}", download=False)
            forbidden = ["karaoke", "acoustic", "official video", "live", "cover", "instrumental", "clip", "m/v", " mv "]
            preferred, other = [], []
            for entry in info.get('entries', []):
                title_lower = entry.get('title', '').lower()
                if any(w in title_lower for w in forbidden):
                    continue
                item = {
                    'id': entry.get('id'),
                    'title': entry.get('title'),
                    'url': f"https://www.youtube.com/watch?v={entry.get('id')}",
                }
                # Les versions "audio" ont moins de post-traitement vidéo → timing plus fiable
                if 'audio' in title_lower:
                    preferred.append(item)
                else:
                    other.append(item)
            return jsonify((preferred + other)[:5])
    except Exception:
        return jsonify({"error": "Erreur"}), 500

@app.route('/api/cancel', methods=['POST'])
def cancel_download():
    task_id = request.json.get('task_id')
    if task_id in active_downloads:
        del active_downloads[task_id]
        import factory
        factory.cancel_factory(task_id)
        socketio.emit('download_progress', list(active_downloads.values()))
    return jsonify({"message": "Annulé"})

@app.route('/api/add_youtube', methods=['POST'])
def add_youtube():
    data = request.json
    url = data.get('url')
    title = data.get('title', 'Musique inconnue')
    if not url: return jsonify({"error": "URL manquante"}), 400

    task_id = str(uuid.uuid4())
    active_downloads[task_id] = {"id": task_id, "title": title}
    socketio.emit('download_progress', list(active_downloads.values()))

    def background_task(task_id, youtube_url, song_title):
        import factory
        try:
            factory.run_factory(youtube_url, task_id)
            socketio.emit('library_updated')
        except ValueError as e:
            if str(e) == "NO_LYRICS":
                socketio.emit('download_error', {"message": f"❌ Aucune parole trouvée pour '{song_title}'."})
            elif str(e) == "BAD_DURATION":
                socketio.emit('download_error', {"message": f"⏱️ Décalage temporel ! Cherchez une version 'Audio' !"})
        except Exception as e:
            logging.error(f"Erreur inattendue pour '{song_title}': {e}")
        finally:
            if task_id in active_downloads:
                del active_downloads[task_id]
                socketio.emit('download_progress', list(active_downloads.values()))

    eventlet.spawn(background_task, task_id, url, title)
    return jsonify({"message": "Usine lancée !"})

# ==========================================
# SOCKETS : CONNEXION / DÉCONNEXION
# ==========================================

@socketio.on('connect')
def handle_connect(): pass

@socketio.on('disconnect')
def handle_disconnect():
    sid = request.sid
    if sid in clients:
        room = clients[sid]['room']
        role = clients[sid]['role']
        if room in rooms_state:
            if role == 'tv': rooms_state[room]['tv_sid'] = None
            if role == 'dj' and sid in rooms_state[room]['dj_sids']:
                rooms_state[room]['dj_sids'].remove(sid)
        del clients[sid]
        emit('rooms_updated', broadcast=True)

@socketio.on('join_karaoke_room')
def on_join_room(data):
    room = data.get('room')
    role = data.get('role')
    pwd  = data.get('password', '')
    sid  = request.sid

    if room not in rooms_state:
        emit('join_error', {'message': "Cette salle n'existe plus !"})
        return
    if rooms_state[room]['password'] and rooms_state[room]['password'] != pwd:
        emit('join_error', {'message': "Mot de passe de salle incorrect !"})
        return
    if role == 'tv' and rooms_state[room]['tv_sid'] is not None:
        emit('join_error', {'message': 'Cette salle possède déjà un Écran TV !'})
        return

    join_room(room)
    clients[sid] = {'room': room, 'role': role}
    if role == 'tv': rooms_state[room]['tv_sid'] = sid
    if role == 'dj': rooms_state[room]['dj_sids'].append(sid)

    emit('rooms_updated', broadcast=True)
    emit('sync_state', rooms_state[room])
    emit('download_progress', list(active_downloads.values()))

# ==========================================
# SOCKETS : CONTRÔLE LECTURE
# ==========================================

@socketio.on('command_play')
def handle_play_command(song):
    if request.sid not in clients: return
    room = clients[request.sid]['room']
    if room in rooms_state:
        rooms_state[room]['current_song'] = song
        rooms_state[room]['paused'] = False
        emit('start_song', song, to=room)
        emit('sync_state', rooms_state[room], to=room)

@socketio.on('command_stop')
def handle_stop_command():
    if request.sid not in clients: return
    room = clients[request.sid]['room']
    if room in rooms_state:
        rooms_state[room]['current_song'] = None
        rooms_state[room]['paused'] = False
        emit('stop_song', to=room)
        emit('sync_state', rooms_state[room], to=room)

@socketio.on('command_pause')
def handle_pause_command():
    if request.sid not in clients: return
    room = clients[request.sid]['room']
    if room in rooms_state and rooms_state[room]['current_song']:
        rooms_state[room]['paused'] = True
        emit('pause_song', to=room)
        emit('sync_state', rooms_state[room], to=room)

@socketio.on('command_resume')
def handle_resume_command():
    if request.sid not in clients: return
    room = clients[request.sid]['room']
    if room in rooms_state and rooms_state[room]['current_song']:
        rooms_state[room]['paused'] = False
        emit('resume_song', to=room)
        emit('sync_state', rooms_state[room], to=room)

@socketio.on('command_seek')
def handle_seek(data):
    if request.sid not in clients: return
    room = clients[request.sid]['room']
    if room in rooms_state and rooms_state[room]['current_song']:
        emit('seek_to', {'position_ms': int(data.get('position_ms', 0))}, to=room)

@socketio.on('play_next')
def handle_play_next():
    if request.sid not in clients: return
    room = clients[request.sid]['room']
    if room in rooms_state:
        rooms_state[room]['paused'] = False
        if rooms_state[room]['queue']:
            next_song = rooms_state[room]['queue'].pop(0)
            rooms_state[room]['current_song'] = next_song
            emit('start_song', next_song, to=room)
        else:
            rooms_state[room]['current_song'] = None
            emit('stop_song', to=room)
        emit('sync_state', rooms_state[room], to=room)

# ==========================================
# SOCKETS : FILE D'ATTENTE
# ==========================================

@socketio.on('add_to_queue')
def handle_add_to_queue(song):
    if request.sid not in clients: return
    room = clients[request.sid]['room']
    if room in rooms_state:
        song['queue_id'] = str(int(time.time() * 1000))
        rooms_state[room]['queue'].append(song)
        emit('sync_state', rooms_state[room], to=room)

@socketio.on('remove_from_queue')
def handle_remove_from_queue(data):
    if request.sid not in clients: return
    room = clients[request.sid]['room']
    if room in rooms_state:
        index = data.get('index')
        if 0 <= index < len(rooms_state[room]['queue']):
            rooms_state[room]['queue'].pop(index)
            emit('sync_state', rooms_state[room], to=room)

@socketio.on('reorder_queue')
def handle_reorder_queue(data):
    if request.sid not in clients: return
    room = clients[request.sid]['room']
    if room in rooms_state:
        old_index = data.get('oldIndex')
        new_index = data.get('newIndex')
        if old_index < new_index: new_index -= 1
        queue = rooms_state[room]['queue']
        if 0 <= old_index < len(queue) and 0 <= new_index <= len(queue):
            item = queue.pop(old_index)
            queue.insert(new_index, item)
            emit('sync_state', rooms_state[room], to=room)

# ==========================================
# SOCKETS : SYNC DE POSITION (anti-drift)
# ==========================================

@socketio.on('position_sync')
def handle_position_sync(data):
    """La TV envoie sa position toutes les 5s ; le serveur la relaie aux DJs de la salle."""
    if request.sid not in clients: return
    room = clients[request.sid]['room']
    # On exclut l'émetteur (la TV) pour ne pas créer de boucle
    for dj_sid in rooms_state.get(room, {}).get('dj_sids', []):
        emit('position_sync', data, to=dj_sid)

if __name__ == '__main__':
    socketio.run(app, host='0.0.0.0', port=5000, debug=True)
