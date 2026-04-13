import os
import subprocess
import urllib.request
import urllib.parse
import json
import re
from yt_dlp import YoutubeDL

try:
    from unidecode import unidecode
except ImportError:
    unidecode = None

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SONGS_DIR = os.path.join(BASE_DIR, "songs")
TEMP_DIR = os.path.join(BASE_DIR, "temp")

os.makedirs(SONGS_DIR, exist_ok=True)
os.makedirs(TEMP_DIR, exist_ok=True)

active_processes = {}

def cancel_factory(task_id):
    if task_id in active_processes:
        try: active_processes[task_id].kill()
        except: pass
        del active_processes[task_id]

def sanitize_filename(name):
    safe_name = re.sub(r'[\\/*?:"<>|]', ' ', name)
    return re.sub(r'\s+', ' ', safe_name).strip()

def clean_title(title):
    if not title: return ""
    # 1. On enlève les parenthèses et crochets
    title = re.sub(r'\(.*?\)|\[.*?\]', '', title)
    
    # 2. On coupe tout ce qui se trouve après un "ft.", "feat", ou "|"
    # Ex: "W/n - id 072019 | 3107 ft 267" devient "W/n - id 072019 "
    title = re.split(r'\||\b[Ff][Tt]\b|\b[Ff][Ee][Aa][Tt]\b', title)[0]
    
    # 3. On enlève les mots parasites
    parasites = ["official audio", "official video", "lyrics", "lyric video", "hd", "mv", "music video"]
    for p in parasites:
        title = re.compile(re.escape(p), re.IGNORECASE).sub('', title)
        
    return title.strip(' -_')

def add_phonetics(lrc_text):
    if not unidecode: return lrc_text
    new_lines = []
    for line in lrc_text.split('\n'):
        match = re.match(r'^(\[\d+:\d+\.\d+\])(.*)', line)
        if match:
            timestamp, text = match.group(1), match.group(2).strip()
            if text:
                romanized = unidecode(text).strip()
                if romanized and text.lower() != romanized.lower() and any(ord(c) > 127 for c in text):
                    line = f"{timestamp}{text}  ({romanized})"
                else:
                    line = f"{timestamp}{text}"
            else:
                line = f"{timestamp}"
        new_lines.append(line)
    return '\n'.join(new_lines)

def normalize_words(text):
    """ Transforme un texte en liste de mots. """
    if not text: return set()
    clean = re.sub(r'[^a-z0-9\s]', ' ', text.lower())
    # CORRECTION : On garde même les mots d'une lettre (important pour des artistes comme W/N ou la K-Pop)
    return set([w for w in clean.split() if len(w) > 0])

def fetch_lyrics_and_metadata(youtube_title, youtube_channel, yt_duration):
    """ Utilise LRCLIB et vérifie le delta de temps pour éviter les décalages """
    
    clean_search_query = clean_title(youtube_title)
    print(f"📖 Recherche LRCLIB pour : {clean_search_query}")
    
    validation_text = f"{youtube_channel} {youtube_title}"
    validation_words = normalize_words(validation_text)
    
    found_but_bad_duration = False
    
    try:
        url = f"https://lrclib.net/api/search?q={urllib.parse.quote(clean_search_query)}"
        req = urllib.request.Request(url, headers={'User-Agent': 'Karaorkey/1.0'})
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode())
            
            for track in data:
                if track.get('syncedLyrics'):
                    api_track_words = normalize_words(track.get('trackName', ''))
                    api_artist_words = normalize_words(track.get('artistName', ''))
                    
                    track_match = len(validation_words.intersection(api_track_words)) > 0
                    artist_match = len(validation_words.intersection(api_artist_words)) > 0
                    
                    if track_match and artist_match:
                        # --- VÉRIFICATION DU TIMING ---
                        # On récupère la vraie durée de la chanson selon LRCLIB
                        track_duration = track.get('duration', 0)
                        
                        # On calcule la différence avec la vidéo YouTube
                        time_diff = abs(yt_duration - track_duration) if yt_duration and track_duration else 0
                        
                        # Tolérance de 15 secondes maximum (pour les petits silences de fin/début)
                        if time_diff <= 15:
                            print(f"✅ Vraies infos trouvées : {track.get('artistName')} - {track.get('trackName')} (Différence temps: {time_diff}s)")
                            final_lrc = add_phonetics(track['syncedLyrics'])
                            return final_lrc, track.get('artistName'), track.get('trackName')
                        else:
                            print(f"⚠️ Rejeté : Décalage temporel trop grand ({time_diff}s de différence).")
                            found_but_bad_duration = True
                            
    except Exception as e:
        print(f"❌ Erreur API : {e}")
        
    if found_but_bad_duration:
        # On lance l'erreur spécifique qu'on a créée dans server.py
        raise ValueError("BAD_DURATION")
        
    print("❌ Aucune correspondance avec des paroles synchronisées.")
    return False

def run_factory(youtube_url, task_id=None):
    ydl_opts = {
        'format': 'bestaudio/best',
        'outtmpl': os.path.join(TEMP_DIR, '%(id)s.%(ext)s'),
        'postprocessors': [{'key': 'FFmpegExtractAudio', 'preferredcodec': 'wav', 'preferredquality': '192'}],
        'quiet': True, 'no_warnings': True
    }
    
    with YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(youtube_url, download=True)
        video_id = info['id'] 
        raw_title = info.get('title', 'Titre Inconnu')
        uploader = info.get('uploader', '')
        # --- NOUVEAU : On récupère la durée de la vidéo YouTube ! ---
        yt_duration = info.get('duration', 0)
        
    temp_audio_path = os.path.join(TEMP_DIR, f"{video_id}.wav")
    
    try:
        # On passe le temps youtube à la fonction de recherche
        result = fetch_lyrics_and_metadata(raw_title, uploader, yt_duration)
        if not result:
            raise ValueError("NO_LYRICS")
    except ValueError as e:
        # Si ça plante (Bad Duration ou No Lyrics), on supprime l'audio brut pour ne pas polluer le PC
        if os.path.exists(temp_audio_path): os.remove(temp_audio_path)
        raise e
        
    lrc_content, real_artist, real_track = result
    
    folder_name = sanitize_filename(f"{real_artist} - {real_track}")
    final_song_folder = os.path.join(SONGS_DIR, folder_name)
    os.makedirs(final_song_folder, exist_ok=True)
    
    with open(os.path.join(final_song_folder, "lyrics.lrc"), "w", encoding="utf-8") as f:
        f.write(lrc_content)
    
    print(f"🪄 Lancement de Demucs pour : {folder_name}")
    cmd = ["demucs", "--two-stems=vocals", "-n", "htdemucs", "-o", TEMP_DIR, temp_audio_path]
    
    process = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if task_id:
        active_processes[task_id] = process
        
    process.wait() 
    
    if task_id in active_processes:
        del active_processes[task_id]
        
    if process.returncode != 0:
        raise Exception("Demucs a été annulé par l'utilisateur.")
    
    demucs_output_folder = os.path.join(TEMP_DIR, "htdemucs", video_id)
    accompaniment_src = os.path.join(demucs_output_folder, "no_vocals.wav")
    
    if os.path.exists(accompaniment_src):
        os.rename(accompaniment_src, os.path.join(final_song_folder, "accompaniment.wav"))
        vocals_src = os.path.join(demucs_output_folder, "vocals.wav")
        if os.path.exists(vocals_src):
            os.rename(vocals_src, os.path.join(final_song_folder, "vocals.wav"))
            
    if os.path.exists(temp_audio_path):
        os.remove(temp_audio_path)