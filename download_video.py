#!/usr/bin/env python3

import subprocess
import sys
import os

def download_video(video_url, output_format="mp4"):
    """
    Télécharge une vidéo (ou un audio) YouTube à l'aide de yt-dlp.
    """
    # Détermine les options selon le format
    if output_format == "mp3":
        # Extraire l'audio et convertir en mp3
        cmd = [
            "yt-dlp",
            "--extract-audio",
            "--audio-format", "mp3",
            "-o", "%(title)s.%(ext)s",  # Nom de fichier basé sur le titre
            video_url
        ]
    else:
        # Par défaut on télécharge la vidéo au format mp4
        # -f mp4 (ou "best[ext=mp4]" pour s'assurer du mp4)
        cmd = [
            "yt-dlp",
            "-f", "mp4",
            "-o", "%(title)s.%(ext)s",
            video_url
        ]
    
    try:
        # Lancer la commande et afficher la sortie en direct
        subprocess.run(cmd, check=True)
        print("Téléchargement terminé !")
    except subprocess.CalledProcessError as e:
        print("Erreur lors du téléchargement :", e)

def main():
    if len(sys.argv) < 2:
        print("Utilisation : python3 download_video.py <URL> [mp3/mp4]")
        sys.exit(1)
    
    video_url = sys.argv[1]
    # Format facultatif, par défaut mp4
    output_format = sys.argv[2] if len(sys.argv) > 2 else "mp4"
    
    download_video(video_url, output_format)

if __name__ == "__main__":
    main()
