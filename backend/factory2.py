import os
import subprocess
import shutil
import sys
import syncedlyrics

# --- CONFIGURATION ---
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SONGS_DIR = os.path.join(BASE_DIR, "songs")

# URL de test
TEST_URL = "https://www.youtube.com/watch?v=4NRXx6U8ABQ"

def check_dependencies():
    """Vérifie si FFmpeg est bien accessible"""
    try:
        subprocess.run(["ffmpeg", "-version"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print("✅ FFmpeg est détecté.")
    except FileNotFoundError:
        print("❌ ERREUR CRITIQUE : FFmpeg n'est pas trouvé. Vérifie ton installation.")
        sys.exit(1)

def run_factory(url):
    print(f"--- 🏭 Démarrage de l'usine Karaorkey (Moteur: Demucs) ---")
    check_dependencies()

    if not os.path.exists(SONGS_DIR):
        os.makedirs(SONGS_DIR)

    # 1. Télécharger l'audio (yt-dlp)
    print("\n--- 1. Téléchargement YouTube ---")
    try:
        from yt_dlp import YoutubeDL
        
        # On télécharge temporairement à la racine pour traiter
        temp_filename = os.path.join(SONGS_DIR, "temp_download") 
        
        ydl_opts = {
            'format': 'bestaudio/best',
            'outtmpl': temp_filename + '.%(ext)s',
            'postprocessors': [{
                'key': 'FFmpegExtractAudio',
                'preferredcodec': 'mp3',
                'preferredquality': '320', # Qualité max
            }],
            'quiet': True
        }
        
        with YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=True)
            video_title = info['title']
            # Nettoyage du titre pour éviter les caractères bizarres dans les dossiers
            safe_title = "".join([c for c in video_title if c.isalnum() or c in (' ', '-', '_')]).strip()
            
            # yt-dlp a créé un mp3, on récupère son chemin exact
            mp3_source = temp_filename + ".mp3"
            print(f"✅ Téléchargé : {safe_title}")

    except Exception as e:
        print(f"❌ Erreur téléchargement : {e}")
        return

    # 2. Séparation avec DEMUCS (Le changement est ici)
    print("\n--- 2. Séparation Haute Qualité (Demucs) ---")
    print("Cela peut prendre un peu plus de temps que Spleeter, mais la qualité sera meilleure...")
    
    try:
        # Commande Demucs :
        # -n htdemucs : Utilise le dernier modèle (Hybrid Transformer)
        # --two-stems=vocals : Sépare en 2 pistes : "vocals" et "no_vocals" (l'instru)
        subprocess.run([
            "demucs",
            "-n", "htdemucs", 
            "--two-stems=vocals",
            "-o", SONGS_DIR, # Dossier de sortie global
            mp3_source
        ], check=True)
        
        # Demucs crée une structure complexe : songs/htdemucs/temp_download/vocals.wav
        # Nous allons ranger ça proprement dans : songs/Titre_Chanson/
        
        demucs_output_folder = os.path.join(SONGS_DIR, "htdemucs", "temp_download")
        final_song_folder = os.path.join(SONGS_DIR, safe_title)
        
        if not os.path.exists(final_song_folder):
            os.makedirs(final_song_folder)
            
        # Déplacer et renommer les fichiers
        shutil.move(os.path.join(demucs_output_folder, "no_vocals.wav"), os.path.join(final_song_folder, "accompaniment.wav"))
        shutil.move(os.path.join(demucs_output_folder, "vocals.wav"), os.path.join(final_song_folder, "vocals.wav"))
        
        # Nettoyage des dossiers temporaires Demucs
        shutil.rmtree(os.path.join(SONGS_DIR, "htdemucs"))
        os.remove(mp3_source)
        
        print(f"✅ Audio traité et rangé dans : {final_song_folder}")

    except Exception as e:
        print(f"❌ Erreur Demucs : {e}")
        return

    # 3. Récupérer les paroles
    print("\n--- 3. Recherche des paroles ---")
    try:
        lrc_content = syncedlyrics.search(video_title)
        if lrc_content:
            lrc_path = os.path.join(final_song_folder, "lyrics.lrc")
            with open(lrc_path, "w", encoding="utf-8") as f:
                f.write(lrc_content)
            print("✅ Paroles trouvées et synchronisées.")
        else:
            print("⚠️ Paroles non trouvées automatiquement.")
    except Exception as e:
        print(f"⚠️ Erreur paroles : {e}")

    print(f"\n🎉 TERMINE ! Prêt à chanter : {safe_title}")

if __name__ == "__main__":
    # Tu pourras changer l'URL ici pour tes prochaines chansons
    run_factory(TEST_URL)