# ViDL

Application macOS de téléchargement de vidéos (yt-dlp) avec interface graphique : export MP4/MP3, historique, conversion de fichiers locaux (ffmpeg).

## Prérequis

- Python 3 avec tkinter
- Outils en ligne de commande : `brew install yt-dlp ffmpeg`

## Installation

```sh
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

## Lancement

- Double-clic sur `ViDL.app` (launcher macOS — pointe vers le venv du projet), ou
- `./.venv/bin/python gui_downloader.py`

Le bundle `ViDL.app` contient des chemins absolus vers ce dossier : si le projet est déplacé, mettre à jour `ViDL.app/Contents/MacOS/ViDL`.

## Notes

- L'historique des téléchargements est stocké dans `~/Library/Application Support/ViDL/history.json`.
- Pour les vidéos avec restriction d'âge, l'application réessaie automatiquement avec les cookies Firefox (`--cookies-from-browser firefox`) : il faut être connecté à YouTube dans Firefox.
