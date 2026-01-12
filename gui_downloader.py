#!/usr/bin/env python3
"""
ViDL – Téléchargeur YouTube / YouTube Downloader
© 2025
"""

import os
import re
import sys
import subprocess
import threading
import platform
import io
import json
import time
import datetime
import requests
from PIL import Image, ImageTk, ImageDraw, ImageFont
import tkinter as tk
import tkinter.font as tkFont
import tkinter.filedialog as filedialog
import ttkbootstrap as ttk
from ttkbootstrap.constants import *
from tkinter import messagebox

# ---------------------------------------------------------
# Utility functions
# ---------------------------------------------------------
def sanitize_filename(filename):
    """
    Supprime les caractères interdits pour les noms de fichiers sur la plupart des OS.
    """
    return re.sub(r'[\\/*?:"<>|]', "", filename)

def validate_url(url):
    """
    Vérifie que l'URL commence par http:// ou https://.
    """
    return url.startswith("http://") or url.startswith("https://")

def format_duration(duration):
    """
    Convertit une durée (en secondes) en format mm:ss ou hh:mm:ss.
    """
    try:
        duration = int(float(duration))
    except Exception:
        return str(duration)
    hours = duration // 3600
    minutes = (duration % 3600) // 60
    seconds = duration % 60
    if hours > 0:
        return f"{hours:02d}:{minutes:02d}:{seconds:02d}"
    else:
        return f"{minutes:02d}:{seconds:02d}"

# ---------------------------------------------------------
# UI strings dictionary generator
# ---------------------------------------------------------
def get_ui_strings(language):
    if language == "fr":
        return {
            "title": "ViDL - Téléchargeur Universel",
            "about": "À propos",
            "quit": "Quitter",
            "options": "Options",
            "change_theme": "Changer de thème",
            "download_tab": "Téléchargement",
            "history_tab": "Historique",
            "conversion_tab": "Conversion",
            "video_analysis": "Analyse de la vidéo",
            "download_labelframe": "Téléchargement",
            "url": "URL :",
            "url_placeholder": "Entrez l'URL de la vidéo…",
            "paste_tooltip": "Collez l'URL depuis le presse-papiers",
            "analyze": "🔍 Analyser",
            "analyze_tooltip": "Analyser la vidéo",
            "analyzing": "Analyse en cours…",
            "no_format_found": "Aucun format exploitable trouvé.",
            "export_mp4": "Exporter en mp4",
            "export_mp3": "Exporter en mp3",
            "source_format": "Format d'origine :",
            "choose_folder": "Choisir dossier…",
            "choose_folder_tooltip": "Sélectionnez le dossier de téléchargement",
            "open_folder_after_download": "Ouvrir le dossier à la fin",
            "download_button": "📥 Télécharger",
            "download_button_tooltip": "Démarrer le téléchargement",
            "cancel": "✖️ Annuler",
            "cancel_tooltip": "Annuler le téléchargement",
            "reencode_mp4": "Re‑encoder MP4",
            "waiting": "En attente...",
            "download_in_progress": "Téléchargement en cours…",
            "download_stopped": "Le téléchargement a été arrêté.",
            "download_failed": "Échec du téléchargement.",
            "mp4_optimize": "Cliquez sur 'Re‑encoder MP4' pour optimiser l'import dans Final Cut Pro.",
            "download_complete": "Téléchargement terminé",
            "search": "Recherche :",
            "clear_history": "Effacer l'historique",
            "copy_url": "Copier l'URL",
            "delete": "Supprimer",
            "copy_copied": "URL copiée dans le presse-papiers !",
            "confirm_delete": "Êtes-vous sûr de vouloir supprimer cet élément de l'historique ?",
            "confirm_clear_history": "Êtes-vous sûr de vouloir effacer tout l'historique ?",
            "clear_history_title": "Effacer l'historique",
            "language": "Langue",
            "english": "Anglais",
            "french": "Français",
            "reencode_in_progress": "Ré‑encodage en cours",
            "invalid_url": "URL invalide. Veuillez entrer une URL valide (commençant par http:// ou https://).",
            # Onglet Conversion
            "file_conversion": "Conversion de fichier",
            "choose_file": "Choisir un fichier…",
            "select_format": "Format d'export :",
            "start_conversion": "Démarrer la conversion",
            "conversion_in_progress": "Conversion en cours...",
            "conversion_complete": "Conversion terminée",
            "conversion_failed": "La conversion a échoué",
            "estimated_size": "Taille estimée :",
            "advanced_settings": "Paramètres avancés",
            # Nouveaux textes pour la miniature
            "download_thumbnail": "Télécharger l'image",
            "download_thumbnail_tooltip": "Télécharger la miniature en haute résolution",
            "audio_language": "Langue audio :",
            "auto": "Auto"
        }
    else:
        return {
            "title": "ViDL - Universal Downloader",
            "about": "About",
            "quit": "Quit",
            "options": "Options",
            "change_theme": "Change Theme",
            "download_tab": "Download",
            "history_tab": "History",
            "conversion_tab": "Conversion",
            "video_analysis": "Video Analysis",
            "download_labelframe": "Download",
            "url": "URL:",
            "url_placeholder": "Enter the video URL…",
            "paste_tooltip": "Paste the URL from the clipboard",
            "analyze": "🔍 Analyze",
            "analyze_tooltip": "Analyze the video",
            "analyzing": "Analyzing…",
            "no_format_found": "No usable formats found.",
            "export_mp4": "Export as MP4",
            "export_mp3": "Export as MP3",
            "source_format": "Source format:",
            "choose_folder": "Choose folder...",
            "choose_folder_tooltip": "Select the download folder",
            "open_folder_after_download": "Open folder after download",
            "download_button": "📥 Download",
            "download_button_tooltip": "Start downloading",
            "cancel": "✖️ Cancel",
            "cancel_tooltip": "Cancel the download",
            "reencode_mp4": "Re‑encode MP4",
            "waiting": "Waiting...",
            "download_in_progress": "Downloading…",
            "download_stopped": "Download has been stopped.",
            "download_failed": "Download failed.",
            "mp4_optimize": "Click 'Re‑encode MP4' to optimize for Final Cut Pro.",
            "download_complete": "Download complete",
            "search": "Search:",
            "clear_history": "Clear History",
            "copy_url": "Copy URL",
            "delete": "Delete",
            "copy_copied": "URL copied to clipboard!",
            "confirm_delete": "Are you sure you want to delete this history entry?",
            "confirm_clear_history": "Are you sure you want to clear the entire history?",
            "clear_history_title": "Clear History",
            "language": "Language",
            "english": "English",
            "french": "French",
            "reencode_in_progress": "Re‑encoding",
            "invalid_url": "Invalid URL. Please enter a valid URL (starting with http:// or https://).",
            # Conversion tab strings
            "file_conversion": "File Conversion",
            "choose_file": "Choose a file...",
            "select_format": "Output format:",
            "start_conversion": "Start Conversion",
            "conversion_in_progress": "Conversion in progress...",
            "conversion_complete": "Conversion complete",
            "conversion_failed": "Conversion failed",
            "estimated_size": "Estimated size:",
            "advanced_settings": "Advanced Settings",
            # Nouveaux textes pour la miniature
            "download_thumbnail": "Download Thumbnail",
            "download_thumbnail_tooltip": "Download the thumbnail in high resolution",
            "audio_language": "Audio language:",
            "auto": "Auto"
        }

# ---------------------------------------------------------
# Small utility class for tooltips
# ---------------------------------------------------------
class CreateToolTip(object):
    def __init__(self, widget, text='widget info'):
        self.waittime = 500
        self.wraplength = 180
        self.widget = widget
        self.text = text
        self.widget.bind("<Enter>", self.enter)
        self.widget.bind("<Leave>", self.leave)
        self.widget.bind("<ButtonPress>", self.leave)
        self.id = None
        self.tw = None

    def enter(self, event=None):
        self.schedule()

    def leave(self, event=None):
        self.unschedule()
        self.hidetip()

    def schedule(self):
        self.unschedule()
        self.id = self.widget.after(self.waittime, self.showtip)

    def unschedule(self):
        id_ = self.id
        self.id = None
        if id_:
            self.widget.after_cancel(id_)

    def showtip(self, event=None):
        x, y, cx, cy = self.widget.bbox("insert")
        x = x + self.widget.winfo_rootx() + 25
        y = y + cy + self.widget.winfo_rooty() + 20
        self.tw = tk.Toplevel(self.widget)
        self.tw.wm_overrideredirect(True)
        self.tw.wm_geometry("+%d+%d" % (x, y))
        label = ttk.Label(self.tw, text=self.text, justify='left',
                          relief='solid', borderwidth=1,
                          wraplength=self.wraplength,
                          padding=(5,3))
        label.pack(ipadx=1)

    def hidetip(self):
        tw = self.tw
        self.tw = None
        if tw:
            tw.destroy()

# ---------------------------------------------------------
# Functions for video analysis and information retrieval
# ---------------------------------------------------------
def parse_available_formats(video_url):
    try:
        cmd = ["yt-dlp", "-F", video_url]
        output = run_info_command_with_age_retry(cmd, video_url)
        if output is None:
            return [], []
    except subprocess.CalledProcessError:
        return [], []

    lines = output.splitlines()
    resolution_regex = re.compile(r"(\d+)x(\d+)")
    tbr_regex = re.compile(r"(\d+)k")
    fps_regex = re.compile(r"(\d+)x(\d+)\s+(\d+)\s")

    best_audio_any = (None, None, -1)
    best_audio_mp4 = (None, None, -1)
    mux_dict = {}
    video_only_dict = {}
    audio_only_list = []
    skip_keywords = ["storyboard", "mhtml"]

    for line in lines:
        match = re.match(r"^(\S+)\s+(.*)$", line)
        if not match:
            continue
        fmt_id = match.group(1).strip()
        rest   = match.group(2).strip()

        if fmt_id.lower() in ["id", "format"]:
            continue

        lower_rest = rest.lower()
        if any(sk in lower_rest for sk in skip_keywords):
            continue

        tokens = rest.split()
        if len(tokens) < 2:
            continue
        ext = tokens[0]
        tbr_matches = tbr_regex.findall(rest)
        tbr_kbps = max(int(x) for x in tbr_matches) if tbr_matches else 0

        if "audio only" in lower_rest:
            audio_only_list.append((fmt_id, f"{fmt_id} | {rest}"))
            if ext in ["mp4", "m4a"] and tbr_kbps > best_audio_mp4[2]:
                best_audio_mp4 = (fmt_id, rest, tbr_kbps)
            if tbr_kbps > best_audio_any[2]:
                best_audio_any = (fmt_id, rest, tbr_kbps)
        else:
            mres = resolution_regex.search(rest)
            if not mres:
                continue
            w, h = map(int, mres.groups())
            fps_match = fps_regex.search(line)
            if fps_match:
                try:
                    fps_val = int(fps_match.group(3))
                except:
                    fps_val = 0
            else:
                if " 60 " in rest or "60fps" in lower_rest:
                    fps_val = 60
                else:
                    fps_val = 30
            if ext != "mp4":
                continue
            if "video only" in lower_rest:
                current = video_only_dict.get((w, h, fps_val), (None, None, -1))
                if tbr_kbps > current[2]:
                    video_only_dict[(w, h, fps_val)] = (fmt_id, rest, tbr_kbps)
            else:
                current = mux_dict.get((w, h, fps_val), (None, None, -1))
                if tbr_kbps > current[2]:
                    mux_dict[(w, h, fps_val)] = (fmt_id, rest, tbr_kbps)

    if best_audio_mp4[0]:
        best_audio = best_audio_mp4
    else:
        best_audio = best_audio_any
    best_audio_id, best_audio_desc, best_audio_abr = best_audio

    video_format_list = []
    def sort_key(k):
        w, h, f = k
        return (min(w, h), f)
    all_keys = set(video_only_dict.keys()) | set(mux_dict.keys())
    for whf in sorted(all_keys, key=sort_key):
        w, h, fps_val = whf
        mux_fid, mux_desc, mux_tbr = mux_dict.get(whf, (None, None, 0))
        vid_fid, vid_desc, vid_tbr = video_only_dict.get(whf, (None, None, 0))
        combo_tbr = 0
        combo_id = None
        if vid_fid and best_audio_id:
            combo_tbr = vid_tbr + best_audio_abr
            combo_id = f"{vid_fid}+{best_audio_id}"
        if combo_tbr > mux_tbr:
            chosen_id = combo_id
            chosen_tbr = combo_tbr
        else:
            chosen_id = mux_fid
            chosen_tbr = mux_tbr
        if chosen_id:
            video_format_list.append({
                "id": chosen_id,
                "width": w,
                "height": h,
                "fps": fps_val,
                "tbr": chosen_tbr
            })
    return video_format_list, audio_only_list

def get_thumbnail_url(video_url):
    try:
        cmd = ["yt-dlp", "--get-thumbnail", video_url]
        stdout = run_info_command_with_age_retry(cmd, video_url)
        if not stdout:
            return None
        thumb_url = stdout.strip()
        return thumb_url if thumb_url else None
    except subprocess.CalledProcessError:
        return None

def get_video_info(video_url):
    try:
        cmd = ["yt-dlp", "-j", video_url]
        stdout = run_info_command_with_age_retry(cmd, video_url)
        if stdout is None:
            return None, None, None, None, None, None, None
        data = json.loads(stdout)
        title = data.get("title")
        uploader = data.get("uploader")
        upload_date = data.get("upload_date")
        if upload_date and len(upload_date) == 8:
            upload_date = f"{upload_date[:4]}-{upload_date[4:6]}-{upload_date[6:]}"
        view_count = data.get("view_count")
        like_count = data.get("like_count")
        comment_count = data.get("comment_count")
        duration = data.get("duration")
        return title, uploader, upload_date, view_count, like_count, comment_count, duration
    except Exception as e:
        print("Error retrieving video info:", e)
        return None, None, None, None, None, None, None

# ---------------------------------------------------------
# Shared helper to retry yt-dlp info commands with cookies
# ---------------------------------------------------------
def run_info_command_with_age_retry(cmd, url):
    """
    Runs a lightweight yt-dlp info command and retries with Firefox cookies
    if age restriction is detected.
    """
    def needs_age_retry(output_text):
        if not output_text:
            return False
        lower = output_text.lower()
        return "sign in to confirm your age" in lower or "age-restricted" in lower

    try:
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            return result.stdout
        combined = f"{result.stdout}\n{result.stderr}"
        if needs_age_retry(combined):
            cmd_with_cookies = cmd.copy()
            if "--cookies-from-browser" not in cmd_with_cookies:
                cmd_with_cookies.insert(1, "--cookies-from-browser")
                cmd_with_cookies.insert(2, "firefox")
            retry = subprocess.run(cmd_with_cookies, capture_output=True, text=True)
            if retry.returncode == 0:
                return retry.stdout
        return None
    except Exception as e:
        print("Error running info command:", e)
        return None

# =========================================================
# Intelligent yt-dlp execution with age restriction support
# =========================================================
def run_yt_dlp_command(app, cmd, url):
    """
    Run yt-dlp once, detect age-restriction errors, then retry automatically
    with Firefox cookies if needed.
    """
    download_regex = re.compile(r'^\[download\].*?([\d\.]+)%')
    destination_regex = re.compile(r'^\[download\]\s+Destination:\s+(.+)$')
    merger_regex = re.compile(r'^\[Merger\]\s+Merging formats into\s+"(.+)"$')
    age_restricted = False

    def stream_process(process):
        nonlocal age_restricted
        for line in process.stdout:
            line = line.strip()
            print(line)
            if "Sign in to confirm your age" in line or "age-restricted" in line.lower():
                age_restricted = True
            match = download_regex.search(line)
            if match:
                try:
                    val_float = float(match.group(1))
                except ValueError:
                    val_float = 0.0
                if app.skip_first_progress_value:
                    app.skip_first_progress_value = False
                    continue
                app.after(0, app.set_smooth_target, val_float)
            dest_match = destination_regex.match(line)
            if dest_match:
                app.downloaded_file_path = dest_match.group(1).strip()
            merger_match = merger_regex.match(line)
            if merger_match:
                app.downloaded_file_path = merger_match.group(1).strip()
        process.wait()
        return process.returncode

    process = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        universal_newlines=True
    )
    app.download_process = process
    retcode = stream_process(process)

    if app.cancelled:
        return retcode

    if retcode != 0 and age_restricted:
        def show_age_notice():
            app.status_var.set("Vidéo restreinte par âge → utilisation des cookies Firefox…")
            if not getattr(app, "age_restriction_notice_shown", False):
                app.age_restriction_notice_shown = True
                messagebox.showinfo(
                    "Vidéo restreinte",
                    "Cette vidéo nécessite une connexion pour confirmer l'âge.\n"
                    "Vos cookies Firefox seront utilisés. Assurez-vous d'être connecté à YouTube dans Firefox.",
                    parent=app
                )

        app.after(0, show_age_notice)
        app.skip_first_progress_value = True
        cmd_with_cookies = cmd.copy()
        if "--cookies-from-browser" not in cmd_with_cookies:
            cmd_with_cookies.insert(1, "--cookies-from-browser")
            cmd_with_cookies.insert(2, "firefox")
        process2 = subprocess.Popen(
            cmd_with_cookies,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            universal_newlines=True
        )
        app.download_process = process2
        retcode = stream_process(process2)

    return retcode

# ---------------------------------------------------------
# Main application class for ViDL
# ---------------------------------------------------------
class YoutubeDownloaderApp(ttk.Window):
    def __init__(self, *args, **kwargs):
        kwargs["themename"] = kwargs.get("themename", "darkly")
        super().__init__(*args, **kwargs)
        self.language = "fr"
        self.ui_strings = get_ui_strings(self.language)
        self.title(self.ui_strings["title"])
        sys.argv[0] = "ViDL"
        self.center_window(840, 705)
        try:
            icon_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "icon.png")
            icon_img = tk.PhotoImage(file=icon_path)
            self.iconphoto(False, icon_img)
        except Exception:
            pass
        self.lift()
        self.attributes("-topmost", True)
        self.after(10, lambda: self.attributes("-topmost", False))
        if sys.platform == "darwin":
            self.attributes("-alpha", 0.98)
        default_font = tkFont.Font(family="Segoe UI", size=12)
        self.option_add("*Font", default_font)

        self.style.configure("Card.TFrame", background=self.style.colors.get("light"), padding=10, relief="flat")
        self.style.configure("Card.TLabel", background=self.style.colors.get("light"))
        self.progress_style_name = "download.Horizontal.TProgressbar"
        self.progress_style_success = "success.Horizontal.TProgressbar"
        self.style.configure(self.progress_style_name, thickness=20, borderwidth=0, relief="flat")
        self.style.configure(self.progress_style_success, thickness=20, borderwidth=0, relief="flat",
                             background="#28a745")
        self.style.configure("Analyze.Horizontal.TProgressbar",
                             thickness=10,
                             troughcolor=self.style.colors.get("dark"),
                             background=self.style.colors.get("info"),
                             borderwidth=0)
        self.style.configure("History.TButton", padding=2, font=("Helvetica", 10))

        self.video_format_list = []
        self.audio_format_list = []
        self.video_format_options = []

        self.url_var = ttk.StringVar()
        self.export_type_var = ttk.StringVar(value="mp4")
        self.selected_format = ttk.StringVar()
        self.audio_language_var = ttk.StringVar(value="Auto")  # "Auto", "en", "pl", "fr", ...
        self.status_var = ttk.StringVar(value=self.ui_strings["waiting"])
        self.progress_val = ttk.DoubleVar(value=0.0)
        self.download_target = 0.0
        self.animation_in_progress = False
        self.skip_first_progress_value = True
        self.cancelled = False
        self.age_restriction_notice_shown = False
        self.open_folder_var = ttk.BooleanVar(value=True)
        self.output_dir = os.path.join(os.path.expanduser("~"), "Downloads")
        self.downloaded_file_path = None
        self.download_process = None

        self.encoding = False
        self.reencode_process = None
        self.cancel_reencode = False

        self.placeholder_tk = self.create_placeholder_image()
        self.placeholder_history_tk = self.create_placeholder_image(60, 34)

        self.url_placeholder = self.ui_strings["url_placeholder"]
        self.url_var.set(self.url_placeholder)

        self.current_video_info = {}
        self.video_duration = None

        self.history = []
        self.history_images = {}
        self.history_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), "history.json")
        self.load_history()

        # Variables pour les options d'export et avancées
        self.video_encoder_var = ttk.StringVar(value="libx264")
        self.video_resolution_var = ttk.StringVar(value="Original")
        self.video_bitrate_var = ttk.StringVar(value="1000k")
        self.video_framerate_var = ttk.StringVar(value="Original")
        # Nouvelle variable pour le préréglage vidéo
        self.video_preset_var = ttk.StringVar(value="medium")
        self.audio_encoder_var = ttk.StringVar(value="aac")
        self.audio_sample_rate_var = ttk.StringVar(value="44100")
        self.audio_channels_var = ttk.StringVar(value="Stereo")
        self.audio_bitrate_var = ttk.StringVar(value="128k")
        self.optimize_var = tk.BooleanVar(value=False)

        self.conversion_file_path = None
        self.conversion_duration = None
        self.conversion_process = None
        self.conversion_cancelled = False
        self.conversion_progress_val = tk.DoubleVar(value=0.0)
        self.conversion_output_file = None
        self.conversion_cmd = None

        self.build_menu()
        self.build_ui()

    def create_placeholder_image(self, width=240, height=135):
        placeholder_img = Image.new("RGB", (width, height), (50, 50, 50))
        draw = ImageDraw.Draw(placeholder_img)
        triangle_size = min(width, height) // 2
        center_x, center_y = width // 2, height // 2
        half_size = triangle_size // 2
        triangle_coords = [
            (center_x - half_size, center_y - half_size),
            (center_x - half_size, center_y + half_size),
            (center_x + half_size, center_y)
        ]
        draw.polygon(triangle_coords, fill=(230, 230, 230))
        return ImageTk.PhotoImage(placeholder_img)

    def center_window(self, width, height):
        sw = self.winfo_screenwidth()
        sh = self.winfo_screenheight()
        x = (sw // 2) - (width // 2)
        y = (sh // 2) - (height // 2)
        self.geometry(f"{width}x{height}+{x}+{y}")

    def build_menu(self):
        menubar = ttk.Menu(self)
        menu_vidl = ttk.Menu(menubar, tearoff=False)
        menu_vidl.add_command(label=self.ui_strings["about"], command=self.show_about)
        menu_vidl.add_separator()
        menu_vidl.add_command(label=self.ui_strings["quit"], command=self.quit)
        menubar.add_cascade(label="ViDL", menu=menu_vidl)

        menu_options = ttk.Menu(menubar, tearoff=False)
        menu_themes = ttk.Menu(menu_options, tearoff=False)
        theme_list = ["darkly", "flatly", "litera", "journal", "cyborg", "minty"]
        for theme_name in theme_list:
            menu_themes.add_command(label=theme_name, command=lambda t=theme_name: self.change_theme(t))
        menu_options.add_cascade(label=self.ui_strings["change_theme"], menu=menu_themes)
        menubar.add_cascade(label=self.ui_strings["options"], menu=menu_options)

        menu_language = ttk.Menu(menubar, tearoff=False)
        menu_language.add_command(label=self.ui_strings["french"], command=lambda: self.change_language("fr"))
        menu_language.add_command(label=self.ui_strings["english"], command=lambda: self.change_language("en"))
        menubar.add_cascade(label=self.ui_strings["language"], menu=menu_language)

        self.config(menu=menubar)

    def show_about(self):
        messagebox.showinfo(self.ui_strings["about"], f"{self.ui_strings['title']}\n© 2025")

    def change_theme(self, theme_name):
        self.style.theme_use(theme_name)

    def change_language(self, new_lang):
        self.language = new_lang
        self.ui_strings = get_ui_strings(new_lang)
        self.url_placeholder = self.ui_strings["url_placeholder"]
        old_en_placeholder = get_ui_strings("en")["url_placeholder"]
        old_fr_placeholder = get_ui_strings("fr")["url_placeholder"]
        if self.url_var.get() == "" or self.url_var.get() in [old_en_placeholder, old_fr_placeholder]:
            self.url_var.set(self.url_placeholder)
        self.update_ui_texts()

    def update_ui_texts(self):
        self.title(self.ui_strings["title"])
        self.build_menu()
        self.notebook.tab(self.tab_download, text=self.ui_strings["download_tab"])
        self.notebook.tab(self.tab_history, text=self.ui_strings["history_tab"])
        self.notebook.tab(self.tab_convert, text=self.ui_strings["conversion_tab"])

        self.title_label.config(text=self.ui_strings["title"])
        self.frm_analyze.config(text=self.ui_strings["video_analysis"])
        self.frm_download.config(text=self.ui_strings["download_labelframe"])
        self.lbl_url.config(text=self.ui_strings["url"])
        self.btn_analyze.config(text=self.ui_strings["analyze"])
        self.radio_mp4.config(text=self.ui_strings["export_mp4"])
        self.radio_mp3.config(text=self.ui_strings["export_mp3"])
        self.lbl_format.config(text=self.ui_strings["source_format"])
        self.btn_choose_folder.config(text=self.ui_strings["choose_folder"])
        self.chk_open_folder.config(text=self.ui_strings["open_folder_after_download"])
        self.btn_cancel.config(text=self.ui_strings["cancel"])
        self.btn_download.config(text=self.ui_strings["download_button"])
        self.btn_reencode.config(text=self.ui_strings["reencode_mp4"])
        self.lbl_audio_lang.config(text=self.ui_strings["audio_language"])
        # Remet "Auto" localisé si nécessaire
        if self.audio_language_var.get().lower() in ["auto", self.ui_strings.get("auto", "Auto").lower()]:
            self.audio_language_var.set(self.ui_strings.get("auto", "Auto"))
        self.lbl_search.config(text=self.ui_strings["search"])
        self.btn_clear_history.config(text=self.ui_strings["clear_history"])

        self.lbl_conversion_title.config(text=self.ui_strings["file_conversion"])
        self.btn_choose_file.config(text=self.ui_strings["choose_file"])
        self.lbl_select_format.config(text=self.ui_strings["select_format"])
        self.btn_start_conversion.config(text=self.ui_strings["start_conversion"])
        self.btn_cancel_conversion.config(text=self.ui_strings["cancel"])
        self.lbl_conversion_status.config(text="")
        self.lbl_estimated_size.config(text=self.ui_strings["estimated_size"] + " N/A")
        self.btn_advanced.config(text=self.ui_strings.get("advanced_settings", "Advanced Settings"))

    def build_ui(self):
        container = ttk.Frame(self, padding=15)
        container.pack(fill=tk.BOTH, expand=True)
        self.notebook = ttk.Notebook(container, padding=10)
        self.notebook.pack(fill=tk.BOTH, expand=True)
        self.tab_download = ttk.Frame(self.notebook)
        self.tab_history = ttk.Frame(self.notebook)
        self.tab_convert = ttk.Frame(self.notebook)
        self.notebook.add(self.tab_download, text=self.ui_strings["download_tab"])
        self.notebook.add(self.tab_history, text=self.ui_strings["history_tab"])
        self.notebook.add(self.tab_convert, text=self.ui_strings["conversion_tab"])
        self.build_download_tab()
        self.build_history_tab()
        self.build_conversion_tab()

    def build_download_tab(self):
        # (Code inchangé pour l'onglet Téléchargement)
        self.tab_download.columnconfigure(0, weight=1)
        self.title_label = ttk.Label(
            self.tab_download,
            text=self.ui_strings["title"],
            font=("Helvetica", 24, "bold"),
            anchor="center",
            justify="center"
        )
        self.title_label.grid(row=0, column=0, pady=(10,10), sticky="ew")
        self.frm_analyze = ttk.Labelframe(self.tab_download, text=self.ui_strings["video_analysis"], padding=15)
        self.frm_analyze.grid(row=1, column=0, padx=10, pady=10, sticky="ew")
        frm_search = ttk.Frame(self.frm_analyze)
        frm_search.pack(fill=tk.X, padx=5, pady=5)
        self.lbl_url = ttk.Label(frm_search, text=self.ui_strings["url"])
        self.lbl_url.pack(side=tk.LEFT, padx=5, pady=5)
        self.ent_url = ttk.Entry(frm_search, textvariable=self.url_var, width=60)
        self.ent_url.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=5, pady=5)
        self.ent_url.bind("<FocusIn>", self.clear_url_placeholder)
        self.ent_url.bind("<FocusOut>", self.add_url_placeholder)
        self.ent_url.bind("<Return>", lambda e: self.analyze_video())
        btn_paste = ttk.Button(frm_search, text="📋", bootstyle="secondary", command=self.paste_url)
        btn_paste.pack(side=tk.LEFT, padx=5, pady=5)
        CreateToolTip(btn_paste, self.ui_strings["paste_tooltip"])
        self.btn_analyze = ttk.Button(frm_search, text=self.ui_strings["analyze"], bootstyle="primary", command=self.analyze_video)
        self.btn_analyze.pack(side=tk.LEFT, padx=5, pady=5)
        CreateToolTip(self.btn_analyze, self.ui_strings["analyze_tooltip"])
        frm_status = ttk.Frame(self.frm_analyze)
        frm_status.pack(fill=tk.X, padx=5, pady=(0,5))
        self.lbl_analyze_info = ttk.Label(frm_status, text="", foreground="#aaa")
        self.lbl_analyze_info.pack(side=tk.LEFT, padx=5, pady=5)
        self.analyze_progress = ttk.Progressbar(
            frm_status,
            style="Analyze.Horizontal.TProgressbar",
            orient=tk.HORIZONTAL,
            mode='indeterminate'
        )
        self.analyze_progress.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=5, pady=5)
        self.analyze_progress.pack_forget()
        self.frm_thumbinfo = ttk.Frame(self.frm_analyze)
        self.frm_thumbinfo.pack(fill=tk.X, pady=10)
        self.card_frame = ttk.Frame(self.frm_thumbinfo, style="Card.TFrame")
        self.card_frame.pack(fill=tk.X, padx=5, pady=5)
        self.lbl_thumbnail = ttk.Label(self.card_frame, image=self.placeholder_tk)
        self.lbl_thumbnail.grid(row=0, column=0, rowspan=7, padx=10, pady=5)
        # Modification : le clic sur l'image de la vidéo se gère désormais en simple clic
        self.lbl_thumbnail.bind("<Button-1>", self.on_thumbnail_click)
        # Nouveau bouton pour télécharger la miniature, positionné en bas à droite du thumbnail
        self.btn_download_thumbnail = ttk.Button(self.card_frame, text=self.ui_strings["download_thumbnail"], command=self.download_thumbnail)
        self.btn_download_thumbnail.place(in_=self.lbl_thumbnail, relx=1.0, rely=1.0, anchor="se", x=-5, y=-5)
        CreateToolTip(self.btn_download_thumbnail, self.ui_strings["download_thumbnail_tooltip"])
        # Informations sur la vidéo
        self.lbl_video_title = ttk.Label(self.card_frame, style="Card.TLabel", font=("Helvetica", 16, "bold"))
        self.lbl_video_channel = ttk.Label(self.card_frame, style="Card.TLabel", font=("Helvetica", 12))
        self.lbl_video_date = ttk.Label(self.card_frame, style="Card.TLabel", font=("Helvetica", 12))
        self.lbl_video_duration = ttk.Label(self.card_frame, style="Card.TLabel", font=("Helvetica", 12))
        self.lbl_video_views = ttk.Label(self.card_frame, style="Card.TLabel", font=("Helvetica", 12))
        self.lbl_video_likes = ttk.Label(self.card_frame, style="Card.TLabel", font=("Helvetica", 12))
        self.lbl_video_comments = ttk.Label(self.card_frame, style="Card.TLabel", font=("Helvetica", 12))
        self.frm_download = ttk.Labelframe(self.tab_download, text=self.ui_strings["download_labelframe"], padding=15)
        self.frm_download.grid(row=2, column=0, padx=10, pady=10, sticky="ew")
        for col_index in range(4):
            self.frm_download.columnconfigure(col_index, weight=1)
        self.radio_mp4 = ttk.Radiobutton(
            self.frm_download,
            text=self.ui_strings["export_mp4"],
            variable=self.export_type_var,
            value="mp4",
            command=self.update_format_list
        )
        self.radio_mp4.grid(row=0, column=0, padx=5, pady=5, sticky=tk.W)
        self.radio_mp3 = ttk.Radiobutton(
            self.frm_download,
            text=self.ui_strings["export_mp3"],
            variable=self.export_type_var,
            value="mp3",
            command=self.update_format_list
        )
        self.radio_mp3.grid(row=0, column=1, padx=5, pady=5, sticky=tk.W)
        self.lbl_format = ttk.Label(self.frm_download, text=self.ui_strings["source_format"])
        self.lbl_format.grid(row=0, column=2, sticky=tk.E, padx=5, pady=5)
        self.combo_format = ttk.Combobox(self.frm_download, textvariable=self.selected_format, width=40, state="readonly")
        self.combo_format.grid(row=0, column=3, sticky=(tk.W, tk.E), padx=5, pady=5)

        # --- Choix de la langue audio ---
        self.lbl_audio_lang = ttk.Label(self.frm_download, text=self.ui_strings["audio_language"])
        self.lbl_audio_lang.grid(row=1, column=1, sticky=tk.E, padx=5, pady=5)

        # Valeurs: code langues + "Auto"
        audio_lang_values = [
            "Auto", "en", "pl", "fr", "de", "es", "it", "pt", "ja", "ko", "zh-Hans", "zh-Hant"
        ]
        self.combo_audio_lang = ttk.Combobox(
            self.frm_download, textvariable=self.audio_language_var,
            state="readonly", values=audio_lang_values, width=12
        )
        self.combo_audio_lang.grid(row=1, column=2, sticky=(tk.W), padx=5, pady=5)
        self.btn_choose_folder = ttk.Button(
            self.frm_download,
            text=self.ui_strings["choose_folder"],
            bootstyle="secondary",
            command=self.choose_download_folder
        )
        self.btn_choose_folder.grid(row=1, column=0, padx=5, pady=5, sticky=tk.W)
        CreateToolTip(self.btn_choose_folder, self.ui_strings["choose_folder_tooltip"])
        btn_frame = ttk.Frame(self.frm_download)
        btn_frame.grid(row=1, column=2, columnspan=2, sticky=tk.E, padx=5, pady=5)
        self.btn_cancel = ttk.Button(
            btn_frame,
            text=self.ui_strings["cancel"],
            bootstyle="danger-outline",
            command=self.cancel_download,
            state="disabled"
        )
        self.btn_cancel.pack(side=tk.LEFT, padx=(0,5))
        CreateToolTip(self.btn_cancel, self.ui_strings["cancel_tooltip"])
        self.btn_download = ttk.Button(
            btn_frame,
            text=self.ui_strings["download_button"],
            bootstyle="success",
            command=self.download_video
        )
        self.btn_download.pack(side=tk.LEFT)
        CreateToolTip(self.btn_download, self.ui_strings["download_button_tooltip"])
        self.chk_open_folder = ttk.Checkbutton(
            self.frm_download,
            text=self.ui_strings["open_folder_after_download"],
            variable=self.open_folder_var,
            bootstyle="round-toggle"
        )
        self.chk_open_folder.grid(row=2, column=0, columnspan=4, sticky=tk.W, padx=5, pady=5)
        self.progress_bar = ttk.Progressbar(
            self.frm_download,
            style=self.progress_style_name,
            orient=tk.HORIZONTAL,
            mode='determinate',
            variable=self.progress_val
        )
        self.progress_bar.grid(row=3, column=0, columnspan=4, pady=10, sticky="we")
        status_frame = ttk.Frame(self.frm_download)
        status_frame.grid(row=4, column=0, columnspan=4, sticky="we", pady=5)
        self.lbl_status = ttk.Label(status_frame, textvariable=self.status_var, foreground="#aaa")
        self.lbl_status.pack(side=tk.LEFT, fill=tk.X, expand=True)
        self.btn_reencode = ttk.Button(
            status_frame,
            text=self.ui_strings["reencode_mp4"],
            bootstyle="primary",
            command=self.reencode_mp4
        )
        self.btn_reencode.pack_forget()

    def build_history_tab(self):
        # (Code inchangé pour l'onglet Historique)
        search_frame = ttk.Frame(self.tab_history)
        search_frame.pack(fill=tk.X, padx=5, pady=5)
        self.lbl_search = ttk.Label(search_frame, text=self.ui_strings["search"])
        self.lbl_search.pack(side=tk.LEFT, padx=5)
        self.search_var = ttk.StringVar()
        self.ent_search = ttk.Entry(search_frame, textvariable=self.search_var)
        self.ent_search.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=5)
        self.ent_search.bind("<KeyRelease>", self.update_history_view)
        self.lbl_copy_feedback = ttk.Label(search_frame, text="", foreground="#28a745")
        self.lbl_copy_feedback.pack(side=tk.RIGHT, padx=5)
        container_frame = ttk.Frame(self.tab_history)
        container_frame.pack(fill=tk.BOTH, expand=True, padx=5, pady=5)
        canvas = tk.Canvas(container_frame)
        scrollbar = ttk.Scrollbar(container_frame, orient="vertical", command=canvas.yview)
        canvas.configure(yscrollcommand=scrollbar.set)
        canvas.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")
        self.history_frame = ttk.Frame(canvas)
        self.history_window = canvas.create_window((0, 0), window=self.history_frame, anchor="nw")
        def on_configure(event):
            canvas.configure(scrollregion=canvas.bbox("all"))
            canvas.itemconfig(self.history_window, width=canvas.winfo_width())
        canvas.bind("<Configure>", on_configure)
        def _on_mousewheel(event):
            if sys.platform == 'darwin':
                canvas.yview_scroll(-1 * event.delta, "units")
            else:
                canvas.yview_scroll(-1 * int(event.delta / 120), "units")
        canvas.bind("<Enter>", lambda e: canvas.bind_all("<MouseWheel>", _on_mousewheel))
        canvas.bind("<Leave>", lambda e: canvas.unbind_all("<MouseWheel>"))
        self.btn_clear_history = ttk.Button(
            self.tab_history,
            text=self.ui_strings["clear_history"],
            bootstyle="danger",
            command=self.clear_history
        )
        self.btn_clear_history.pack(pady=5)
        self.update_history_view()

    def build_conversion_tab(self):
        """Construction de l'onglet Conversion"""
        self.tab_convert.columnconfigure(0, weight=1)
        self.tab_convert.rowconfigure(0, weight=1)
        self.lbl_conversion_title = ttk.Label(
            self.tab_convert,
            text=self.ui_strings["file_conversion"],
            font=("Helvetica", 20, "bold")
        )
        self.lbl_conversion_title.pack(pady=(10,10))
        conversion_frame = ttk.Frame(self.tab_convert, padding=10)
        conversion_frame.pack(fill=tk.BOTH, expand=True, padx=10, pady=5)
        conversion_frame.columnconfigure(0, weight=1)
        conversion_frame.rowconfigure(0, weight=1)
        # --- Section 1 : Import du fichier ---
        file_import_frame = ttk.Labelframe(
            conversion_frame,
            text="Fichier à convertir" if self.language=="fr" else "File to convert",
            padding=10
        )
        file_import_frame.grid(row=0, column=0, sticky="nsew", padx=5, pady=5)
        file_import_frame.columnconfigure(1, weight=1)
        self.btn_choose_file = ttk.Button(
            file_import_frame,
            text=self.ui_strings["choose_file"],
            bootstyle="secondary",
            command=self.choose_conversion_file
        )
        self.btn_choose_file.grid(row=0, column=0, sticky="w", padx=(0,10), pady=5)
        CreateToolTip(self.btn_choose_file, self.ui_strings["choose_file"])
        self.lbl_selected_file = ttk.Label(
            file_import_frame,
            text="",
            foreground=self.style.colors.get("secondary")
        )
        self.lbl_selected_file.grid(row=0, column=1, sticky="w", pady=5)
        info_frame = ttk.Frame(file_import_frame)
        info_frame.grid(row=1, column=0, columnspan=2, sticky="ew", pady=5)
        # Affichage de la miniature avec lecture (modification : on utilise un simple clic)
        self.lbl_conv_thumbnail = ttk.Label(info_frame, image=self.placeholder_tk)
        self.lbl_conv_thumbnail.grid(row=0, column=0, rowspan=5, padx=5, pady=5)
        self.lbl_conv_thumbnail.bind("<Button-1>", self.on_thumbnail_click)
        # Informations sur le fichier (5 infos)
        self.lbl_conv_file_name = ttk.Label(info_frame, text="Nom du fichier : N/A")
        self.lbl_conv_file_name.grid(row=0, column=1, sticky="w", padx=5)
        self.lbl_conv_duration = ttk.Label(info_frame, text="Durée : N/A")
        self.lbl_conv_duration.grid(row=1, column=1, sticky="w", padx=5)
        self.lbl_conv_codec = ttk.Label(info_frame, text="Format : N/A")
        self.lbl_conv_codec.grid(row=2, column=1, sticky="w", padx=5)
        self.lbl_conv_resolution = ttk.Label(info_frame, text="Résolution : N/A")
        self.lbl_conv_resolution.grid(row=3, column=1, sticky="w", padx=5)
        self.lbl_conv_format = ttk.Label(info_frame, text="Débit global : N/A")
        self.lbl_conv_format.grid(row=4, column=1, sticky="w", padx=5)
        # Masquer ces infos tant qu'on ne les a pas obtenues
        self.lbl_conv_file_name.grid_remove()
        self.lbl_conv_duration.grid_remove()
        self.lbl_conv_codec.grid_remove()
        self.lbl_conv_resolution.grid_remove()
        self.lbl_conv_format.grid_remove()

        # --- Section 2 : Options d'export ---
        export_frame = ttk.Labelframe(
            conversion_frame,
            text="Options d'export" if self.language=="fr" else "Export Options",
            padding=10
        )
        export_frame.grid(row=1, column=0, sticky="nsew", padx=5, pady=5)
        # Création de deux frames pour disposer les options en colonnes
        left_frame = ttk.Frame(export_frame)
        left_frame.grid(row=0, column=0, sticky="nsew", padx=5, pady=5)
        right_frame = ttk.Frame(export_frame)
        right_frame.grid(row=0, column=1, sticky="nsew", padx=5, pady=5)
        export_frame.columnconfigure(0, weight=1)
        export_frame.columnconfigure(1, weight=1)

        # Gauche : Format d'export et Qualité
        self.lbl_select_format = ttk.Label(left_frame, text=self.ui_strings["select_format"])
        self.lbl_select_format.grid(row=0, column=0, sticky="w", padx=(0,10), pady=5)
        self.conversion_format_var = ttk.StringVar(value="mp4")
        self.combo_conversion_format = ttk.Combobox(left_frame, textvariable=self.conversion_format_var, state="readonly",
                                                      values=["mp4", "mp3", "mkv", "avi", "mov", "flv", "wmv", "ogg", "wav"])
        self.combo_conversion_format.grid(row=0, column=1, sticky="w", pady=5)
        self.lbl_quality = ttk.Label(left_frame, text="Qualité:" if self.language=="fr" else "Quality:")
        self.lbl_quality.grid(row=1, column=0, sticky="w", padx=(0,10), pady=5)
        self.quality_var = ttk.StringVar(value="Standard")
        self.combo_quality = ttk.Combobox(left_frame, textvariable=self.quality_var, state="readonly",
                                          values=["Low", "Standard", "High", "Very High"])
        self.combo_quality.grid(row=1, column=1, sticky="w", pady=5)

        # Droite : Résolution et Échantillonnage
        lbl_resolution = ttk.Label(right_frame, text="Résolution:" if self.language=="fr" else "Resolution:")
        lbl_resolution.grid(row=0, column=0, sticky="w", padx=(0,10), pady=5)
        self.combo_resolution = ttk.Combobox(right_frame, textvariable=self.video_resolution_var, state="readonly",
                                             values=["Original", "144p", "240p", "360p", "480p", "720p", "1080p", "1440p", "2160p"])
        self.combo_resolution.grid(row=0, column=1, sticky="w", pady=5)
        lbl_sample_rate = ttk.Label(right_frame, text="Échantillonnage:" if self.language=="fr" else "Sample Rate:")
        lbl_sample_rate.grid(row=1, column=0, sticky="w", padx=(0,10), pady=5)
        self.combo_sample_rate = ttk.Combobox(right_frame, textvariable=self.audio_sample_rate_var, state="readonly",
                                              values=["8000", "11025", "16000", "22050", "32000", "44100", "48000", "88200", "96000"])
        self.combo_sample_rate.grid(row=1, column=1, sticky="w", pady=5)

        # Ligne du bas : Bouton "Paramètres avancés" (gauche) et case "Optimiser pour le streaming" (droite)
        bottom_frame = ttk.Frame(export_frame)
        bottom_frame.grid(row=1, column=0, columnspan=2, sticky="ew", padx=5, pady=5)
        bottom_frame.columnconfigure(0, weight=1)
        bottom_frame.columnconfigure(1, weight=1)
        self.btn_advanced = ttk.Button(bottom_frame, text=self.ui_strings.get("advanced_settings", "Advanced Settings"),
                                       command=self.open_advanced_settings)
        self.btn_advanced.grid(row=0, column=0, sticky="w", padx=5, pady=5)
        self.chk_optimize = ttk.Checkbutton(bottom_frame,
                                            text="Optimiser pour le streaming" if self.language=="fr" else "Optimize for streaming",
                                            variable=self.optimize_var)
        self.chk_optimize.grid(row=0, column=1, sticky="e", padx=5, pady=5)

        # Progression de la conversion
        progress_frame = ttk.Frame(export_frame)
        progress_frame.grid(row=2, column=0, columnspan=2, sticky="ew", pady=(10,0))
        self.progress_bar_conversion = ttk.Progressbar(progress_frame,
                                                       style=self.progress_style_name,
                                                       orient=tk.HORIZONTAL,
                                                       mode='determinate',
                                                       variable=self.conversion_progress_val)
        self.progress_bar_conversion.grid(row=0, column=0, sticky="ew", padx=5, pady=(0,5))
        progress_frame.columnconfigure(0, weight=1)
        self.lbl_conversion_status = ttk.Label(progress_frame, text="", foreground=self.style.colors.get("info"))
        self.lbl_conversion_status.grid(row=1, column=0, sticky="w", padx=5)
        self.lbl_estimated_size = ttk.Label(progress_frame, text=self.ui_strings["estimated_size"] + " N/A", foreground=self.style.colors.get("info"))
        self.lbl_estimated_size.grid(row=2, column=0, sticky="w", padx=5)
        # Boutons de contrôle de conversion (inversion de l'ordre)
        control_frame = ttk.Frame(export_frame)
        control_frame.grid(row=3, column=0, columnspan=2, sticky="e", pady=5)
        # D'abord le bouton "Démarrer la conversion"
        self.btn_start_conversion = ttk.Button(control_frame,
                                                 text=self.ui_strings["start_conversion"],
                                                 bootstyle="success",
                                                 command=self.start_conversion)
        self.btn_start_conversion.pack(side=tk.RIGHT, padx=5, pady=5)
        # Puis le bouton "Annuler"
        self.btn_cancel_conversion = ttk.Button(control_frame,
                                                  text=self.ui_strings["cancel"],
                                                  bootstyle="danger-outline",
                                                  command=self.cancel_conversion,
                                                  state="disabled")
        self.btn_cancel_conversion.pack(side=tk.RIGHT, padx=5, pady=5)

    def clear_url_placeholder(self, event):
        if self.url_var.get() == self.url_placeholder:
            self.url_var.set("")

    def add_url_placeholder(self, event):
        if not self.url_var.get():
            self.url_var.set(self.url_placeholder)

    def paste_url(self):
        try:
            txt = self.clipboard_get()
            if txt == self.url_placeholder:
                return
            self.url_var.set(txt)
        except tk.TclError:
            messagebox.showwarning(self.ui_strings["about"], self.ui_strings["paste_tooltip"])

    def choose_download_folder(self):
        new_dir = filedialog.askdirectory(title=self.ui_strings["choose_folder"])
        if new_dir:
            self.output_dir = new_dir
            messagebox.showinfo(self.ui_strings["choose_folder"], f"{self.ui_strings['choose_folder']}\n{self.output_dir}")

    def analyze_video(self):
        url = self.url_var.get().strip()
        if not url or url == self.url_placeholder:
            messagebox.showwarning(
                self.ui_strings["about"],
                "Veuillez saisir une URL." if self.language=="fr" else "Please enter a URL."
            )
            return
        if not validate_url(url):
            messagebox.showwarning(self.ui_strings["about"], self.ui_strings["invalid_url"])
            return

        self.video_format_list.clear()
        self.audio_format_list.clear()
        self.selected_format.set('')
        self.lbl_analyze_info.config(text=self.ui_strings["analyzing"])
        self.lbl_thumbnail.config(image=self.placeholder_tk, text='')
        for lbl in [
            self.lbl_video_title,
            self.lbl_video_channel,
            self.lbl_video_date,
            self.lbl_video_duration,
            self.lbl_video_views,
            self.lbl_video_likes,
            self.lbl_video_comments
        ]:
            lbl.grid_forget()
        self.analyze_progress.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=5, pady=5)
        self.analyze_progress.start(10)
        threading.Thread(target=self.run_analysis_thread, args=(url,), daemon=True).start()

    def run_analysis_thread(self, url):
        v_list, a_list = parse_available_formats(url)
        thumb_url = get_thumbnail_url(url)
        (video_title, video_channel, video_pubdate, view_count,
         like_count, comment_count, duration) = get_video_info(url)
        self.video_duration = duration
        thumb_image = None
        if thumb_url:
            try:
                r = requests.get(thumb_url, timeout=5)
                r.raise_for_status()
                img_data = r.content
                pil_img = Image.open(io.BytesIO(img_data))
                pil_img = pil_img.resize((240, 135), Image.Resampling.LANCZOS)
                thumb_image = ImageTk.PhotoImage(pil_img)
            except:
                pass

        def on_finish():
            self.analyze_progress.stop()
            self.analyze_progress.pack_forget()
            if not v_list and not a_list:
                messagebox.showerror(
                    "Error" if self.language=="en" else "Erreur",
                    self.ui_strings["no_format_found"]
                )
                self.lbl_analyze_info.config(text=self.ui_strings["no_format_found"])
                return

            self.video_format_list = v_list
            self.audio_format_list = a_list
            self.update_format_list()

            info_txt = (
                f"{len(v_list)} formats vidéo, {len(a_list)} formats audio."
                if self.language=="fr"
                else f"{len(v_list)} video formats, {len(a_list)} audio formats."
            )
            self.lbl_analyze_info.config(text=info_txt)

            if thumb_image:
                self.lbl_thumbnail.config(image=thumb_image, text='')
                self.lbl_thumbnail.image = thumb_image
            else:
                self.lbl_thumbnail.config(image=self.placeholder_tk, text='')

            row_index = 0
            if video_title:
                self.lbl_video_title.config(
                    text=f"{'Titre' if self.language=='fr' else 'Title'}: {video_title}"
                )
                self.lbl_video_title.grid(row=row_index, column=1, sticky="w", padx=5, pady=(3,1))
                row_index += 1
            if video_channel:
                self.lbl_video_channel.config(
                    text=f"{'Chaîne' if self.language=='fr' else 'Channel'}: {video_channel}"
                )
                self.lbl_video_channel.grid(row=row_index, column=1, sticky="w", padx=5, pady=1)
                row_index += 1
            if video_pubdate:
                self.lbl_video_date.config(
                    text=f"{'Date' if self.language=='fr' else 'Date'}: {video_pubdate}"
                )
                self.lbl_video_date.grid(row=row_index, column=1, sticky="w", padx=5, pady=1)
                row_index += 1
            if duration is not None:
                self.lbl_video_duration.config(
                    text=f"{'Durée' if self.language=='fr' else 'Duration'}: {format_duration(duration)}"
                )
                self.lbl_video_duration.grid(row=row_index, column=1, sticky="w", padx=5, pady=1)
                row_index += 1
            if view_count is not None:
                self.lbl_video_views.config(
                    text=f"{'Vues' if self.language=='fr' else 'Views'}: {view_count:,}"
                )
                self.lbl_video_views.grid(row=row_index, column=1, sticky="w", padx=5, pady=1)
                row_index += 1
            if like_count is not None:
                self.lbl_video_likes.config(
                    text=f"{'Likes' if self.language=='fr' else 'Likes'}: {like_count:,}"
                )
                self.lbl_video_likes.grid(row=row_index, column=1, sticky="w", padx=5, pady=1)
                row_index += 1
            if comment_count is not None:
                self.lbl_video_comments.config(
                    text=f"{'Commentaires' if self.language=='fr' else 'Comments'}: {comment_count:,}"
                )
                self.lbl_video_comments.grid(row=row_index, column=1, sticky="w", padx=5, pady=1)
                row_index += 1
            self.current_video_info = {
                "title": video_title,
                "url": url,
                "thumbnail_url": thumb_url
            }

        self.after(0, on_finish)

    def update_format_list(self):
        chosen_export = self.export_type_var.get()
        if chosen_export == "mp4":
            options = []
            display_values = []
            for fmt in self.video_format_list:
                w = fmt["width"]
                h = fmt["height"]
                fps = fmt["fps"]
                tbr = fmt["tbr"]
                res_str = f"{w}x{h}"
                fps_str = f"{fps}fps"
                bitrate_str = f"{tbr} kbps"
                file_format = "MP4"
                display = f"{res_str}, {fps_str}, {bitrate_str}, {file_format}"
                if self.video_duration:
                    est_size = (tbr * self.video_duration) / 8192
                    display += f", ~{est_size:.1f} MB"
                options.append(fmt)
                display_values.append(display)
            self.video_format_options = options
            self.combo_format['values'] = display_values
            if display_values:
                # Sélectionner par défaut 1080p, sinon 720p, sinon le dernier (meilleure qualité)
                default_idx = len(options) - 1  # Par défaut la meilleure qualité
                for i, fmt in enumerate(options):
                    h = min(fmt["height"], fmt["width"])  # Hauteur effective
                    if h == 1080:
                        default_idx = i
                        break
                    elif h == 720:
                        default_idx = i  # Continue à chercher 1080p
                self.combo_format.current(default_idx)
        else:
            combo_values = [item[1] for item in self.audio_format_list]
            self.combo_format['values'] = combo_values
            if combo_values:
                self.combo_format.current(0)

    def download_video(self):
        url = self.url_var.get().strip()
        if not url or url == self.url_placeholder:
            messagebox.showwarning(
                "Warning" if self.language=="en" else "Attention",
                "Missing URL." if self.language=="en" else "URL manquante."
            )
            return
        if not validate_url(url):
            messagebox.showwarning(self.ui_strings["about"], self.ui_strings["invalid_url"])
            return

        chosen_export = self.export_type_var.get()
        if chosen_export == "mp4":
            if not self.video_format_list:
                messagebox.showwarning(
                    "Warning" if self.language=="en" else "Attention",
                    "Please analyze the video first (or no format found)." if self.language=="en" else
                    "Veuillez analyser la vidéo d'abord (ou aucun format trouvé)."
                )
                return
            idx = self.combo_format.current()
            if idx < 0:
                messagebox.showwarning(
                    "Warning" if self.language=="en" else "Attention",
                    "No format selected." if self.language=="en" else "Aucun format sélectionné."
                )
                return
            combo_id = self.video_format_options[idx]["id"]
        else:
            if not self.audio_format_list:
                messagebox.showwarning(
                    "Warning" if self.language=="en" else "Attention",
                    "Please analyze the video first (or no format found)." if self.language=="en" else
                    "Veuillez analyser la vidéo d'abord (ou aucun format trouvé)."
                )
                return
            current_val = self.selected_format.get().strip()
            if not current_val:
                messagebox.showwarning(
                    "Warning" if self.language=="en" else "Attention",
                    "No format selected." if self.language=="en" else "Aucun format sélectionné."
                )
                return
            combo_id = current_val.split("|")[0].strip()

        self.downloaded_file_path = None
        title_in_info = self.current_video_info.get("title", "")
        if title_in_info:
            base = sanitize_filename(title_in_info)
        else:
            base = "video"
        ext = "mp4" if chosen_export == "mp4" else "mp3"
        candidate = os.path.join(self.output_dir, f"{base}.{ext}")
        i = 1
        while os.path.exists(candidate):
            candidate = os.path.join(self.output_dir, f"{base} ({i}).{ext}")
            i += 1
        output_template = candidate

        # --- Nouvelle construction de la commande avec préférence de langue ---
        selected_lang = self.audio_language_var.get().strip()
        is_auto_lang = (selected_lang.lower() in ["auto", self.ui_strings.get("auto", "auto").lower()])

        if chosen_export == "mp4":
            if is_auto_lang:
                # Comportement inchangé
                cmd = [
                    "yt-dlp",
                    "-f", combo_id,
                    "--merge-output-format", "mp4",
                    "--newline",
                    "-o", output_template,
                    url
                ]
            else:
                # On tente de garder la vidéo choisie + audio filtré par langue
                if "+" in combo_id:
                    # combo_id = "VID+AUD" -> on remplace juste l'audio
                    vid_id = combo_id.split("+", 1)[0].strip()
                    fmt_expr = f"{vid_id}+ba[language^={selected_lang}]/(bestvideo+bestaudio/b)"
                    cmd = [
                        "yt-dlp",
                        "-f", fmt_expr,
                        "--merge-output-format", "mp4",
                        "-S", f"lang:{selected_lang}",
                        "--newline",
                        "-o", output_template,
                        url
                    ]
                else:
                    # combo_id = un seul id (format muxé par YouTube)
                    # On ne peut pas remplacer l'audio directement : on ajoute au moins une préférence de tri
                    cmd = [
                        "yt-dlp",
                        "-f", combo_id,
                        "--merge-output-format", "mp4",
                        "-S", f"lang:{selected_lang}",
                        "--newline",
                        "-o", output_template,
                        url
                    ]
        else:
            # Extraction audio (MP3)
            if is_auto_lang:
                cmd = [
                    "yt-dlp",
                    "-f", combo_id,
                    "--extract-audio",
                    "--audio-format", "mp3",
                    "--newline",
                    "-o", output_template,
                    url
                ]
            else:
                # Forcer une piste audio dans la langue souhaitée, fallback sur bestaudio
                fmt_expr = f"ba[language^={selected_lang}]/bestaudio"
                cmd = [
                    "yt-dlp",
                    "-f", fmt_expr,
                    "--extract-audio",
                    "--audio-format", "mp3",
                    "-S", f"lang:{selected_lang}",
                    "--newline",
                    "-o", output_template,
                    url
                ]

        self.progress_val.set(0.0)
        self.download_target = 0.0
        self.progress_bar.configure(style=self.progress_style_name)
        self.status_var.set(self.ui_strings["download_in_progress"] + " 0.0%")
        self.skip_first_progress_value = True
        self.btn_reencode.pack_forget()
        self.cancelled = False
        self.btn_cancel.config(state="normal")

        threading.Thread(target=self.run_download_thread, args=(cmd,), daemon=True).start()

    def run_download_thread(self, cmd):
        clean_cmd = [arg for arg in cmd if arg not in ["--cookies-from-browser", "firefox"]]
        retcode = run_yt_dlp_command(self, clean_cmd, self.url_var.get().strip())
        self.after(0, lambda: self.btn_cancel.config(state="disabled"))
        self.download_process = None
        if retcode == 0:
            self.after(0, lambda: self.finish_progress(True))
        else:
            self.after(0, lambda: self.finish_progress(False))

    def cancel_download(self):
        if self.download_process and self.download_process.poll() is None:
            try:
                self.download_process.terminate()
                self.cancelled = True
                self.status_var.set(self.ui_strings["download_stopped"])
            except Exception as e:
                print("Error during cancellation:", e)
            self.btn_cancel.config(state="disabled")

    def set_smooth_target(self, new_target):
        cur = self.progress_val.get()
        if new_target < cur:
            return
        self.download_target = new_target
        if not self.animation_in_progress:
            self.animation_in_progress = True
            self.animate_progress()

    def animate_progress(self):
        current = self.progress_val.get()
        target = self.download_target
        if abs(target - current) < 0.5:
            self.progress_val.set(target)
            self.animation_in_progress = False
            self.status_var.set(f"{self.ui_strings['download_in_progress']} {target:.1f}%")
        else:
            step = (target - current) * 0.2
            new_val = current + step
            self.progress_val.set(new_val)
            self.status_var.set(f"{self.ui_strings['download_in_progress']} {new_val:.1f}%")
            self.after(50, self.animate_progress)

    def finish_progress(self, success):
        self.animation_in_progress = False
        if success:
            self.download_target = 100
            self.progress_val.set(100)
            self.progress_bar.configure(style=self.progress_style_success)
            file_size_msg = ""
            if self.downloaded_file_path:
                timeout = 3.0
                start_time = time.time()
                while not os.path.exists(self.downloaded_file_path) and time.time() - start_time < timeout:
                    time.sleep(0.1)
                if os.path.exists(self.downloaded_file_path):
                    try:
                        size_bytes = os.path.getsize(self.downloaded_file_path)
                        size_mb = size_bytes / (1024 * 1024)
                        file_size_msg = f" ({size_mb:.1f} MB)"
                    except Exception as e:
                        print("Error getting file size:", e)
            if self.downloaded_file_path and self.export_type_var.get() == "mp4":
                self.status_var.set(f"{self.ui_strings['download_complete']}{file_size_msg}. {self.ui_strings['mp4_optimize']}")
                self.btn_reencode.pack(side=tk.RIGHT)
            else:
                self.status_var.set(f"{self.ui_strings['download_complete']}{file_size_msg}.")
            if self.current_video_info and self.current_video_info.get("title"):
                entry = self.current_video_info.copy()
                entry["download_date"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
                self.add_to_history(entry)
            if self.open_folder_var.get():
                self.open_downloads_folder()
        else:
            self.download_target = 0
            self.progress_val.set(0)
            if self.cancelled:
                self.status_var.set(self.ui_strings["download_stopped"])
                self.cancelled = False
            else:
                self.status_var.set(self.ui_strings["download_failed"])
                messagebox.showerror(
                    "Error" if self.language=="en" else "Erreur",
                    self.ui_strings["download_failed"]
                )

    def reencode_mp4(self):
        if not self.encoding:
            if self.downloaded_file_path and os.path.exists(self.downloaded_file_path):
                self.status_var.set(self.ui_strings["reencode_in_progress"])
                self.progress_val.set(0)
                self.encoding = True
                self.cancel_reencode = False
                self.btn_reencode.config(text="Arrêter" if self.language=="fr" else "Stop")
                def reencode_task():
                    reencoded_file = self.downloaded_file_path.replace(".mp4", "_reencoded.mp4")
                    cmd = [
                        "ffmpeg", "-i", self.downloaded_file_path,
                        "-c:v", "libx264", "-preset", "slow", "-crf", "18",
                        "-c:a", "copy",
                        "-movflags", "faststart",
                        reencoded_file
                    ]
                    try:
                        self.reencode_process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
                        while True:
                            line = self.reencode_process.stdout.readline()
                            if not line:
                                break
                            line = line.strip()
                            match = re.search(r"time=(\d+):(\d+):(\d+\.\d+)", line)
                            if match and self.video_duration:
                                hours = int(match.group(1))
                                minutes = int(match.group(2))
                                seconds = float(match.group(3))
                                current_time = hours * 3600 + minutes * 60 + seconds
                                progress_percentage = (current_time / self.video_duration) * 100
                                if progress_percentage > 100:
                                    progress_percentage = 100
                                self.after(0, self.progress_val.set, progress_percentage)
                                self.after(0, self.status_var.set,
                                           f"{self.ui_strings['reencode_in_progress']} {progress_percentage:.1f}%")
                            if self.cancel_reencode:
                                self.reencode_process.terminate()
                                break
                        self.reencode_process.wait()
                        if self.cancel_reencode:
                            if os.path.exists(reencoded_file):
                                os.remove(reencoded_file)
                            self.after(0, self.status_var.set,
                                       "Re‑encoding cancelled." if self.language=="en" else "Ré‑encodage annulé.")
                        else:
                            os.replace(reencoded_file, self.downloaded_file_path)
                            self.after(0, self.status_var.set,
                                       "MP4 file re‑encoded and optimized." if self.language=="en"
                                       else "Fichier MP4 ré‑encodé et optimisé.")
                            self.after(0, self.progress_val.set, 100)
                    except Exception as e:
                        print("Error during MP4 re‑encoding:", e)
                        self.after(0, self.status_var.set,
                                   "Error during re‑encoding." if self.language=="en" else "Erreur lors du ré‑encodage.")
                    finally:
                        self.encoding = False
                        self.reencode_process = None
                        self.after(0, self.btn_reencode.config, {"text": self.ui_strings["reencode_mp4"]})
                threading.Thread(target=reencode_task, daemon=True).start()
        else:
            self.cancel_reencode = True
            if self.reencode_process and self.reencode_process.poll() is None:
                try:
                    self.reencode_process.terminate()
                    self.status_var.set(
                        "Stopping re‑encoding..." if self.language=="en" else "Arrêt du ré‑encodage en cours..."
                    )
                except Exception as e:
                    print("Error terminating re‑encoding process:", e)

    def open_downloads_folder(self):
        system = platform.system()
        if system == "Darwin":
            subprocess.run(["open", self.output_dir])
        elif system == "Windows":
            os.startfile(self.output_dir)
        else:
            subprocess.run(["xdg-open", self.output_dir])

    def load_history(self):
        if os.path.exists(self.history_file):
            try:
                with open(self.history_file, "r", encoding="utf-8") as f:
                    self.history = json.load(f)
            except Exception as e:
                print("Error loading history:", e)
                self.history = []
        else:
            self.history = []

    def save_history(self):
        try:
            with open(self.history_file, "w", encoding="utf-8") as f:
                json.dump(self.history, f, ensure_ascii=False, indent=2)
        except Exception as e:
            print("Error saving history:", e)

    def add_to_history(self, entry):
        new_date = entry.get("download_date", "")
        new_title = entry.get("title", "")
        new_url = entry.get("url", "")
        new_date_part = new_date.split()[0] if new_date else ""
        for existing in self.history:
            existing_date = existing.get("download_date", "")
            existing_date_part = existing_date.split()[0] if existing_date else ""
            if (existing.get("title") == new_title or existing.get("url") == new_url) and existing_date_part == new_date_part:
                return
        self.history.append(entry)
        self.save_history()
        self.update_history_view()

    def update_history_view(self, event=None):
        for widget in self.history_frame.winfo_children():
            widget.destroy()
        query = self.search_var.get().lower() if hasattr(self, "search_var") else ""
        for idx, entry in enumerate(reversed(self.history)):
            title = entry.get("title", "")
            url = entry.get("url", "")
            date = entry.get("download_date", "")
            if query and (query not in title.lower() and query not in url.lower()):
                continue
            item_frame = ttk.Frame(self.history_frame)
            item_frame.pack(fill=tk.X, padx=10, pady=(5,0))
            thumb_url = entry.get("thumbnail_url")
            if thumb_url in self.history_images:
                photo = self.history_images[thumb_url]
                lbl_thumbnail = ttk.Label(item_frame, image=photo)
            else:
                lbl_thumbnail = ttk.Label(item_frame, image=self.placeholder_history_tk)
                self._load_thumbnail_async(thumb_url, lbl_thumbnail)
            lbl_thumbnail.pack(side=tk.LEFT, padx=(0,10))
            text_frame = ttk.Frame(item_frame)
            text_frame.pack(side=tk.LEFT, fill=tk.X, expand=True)
            lbl_title = ttk.Label(text_frame, text=f"{title}", font=("Helvetica", 12, "bold"))
            lbl_title.pack(anchor=tk.W)
            lbl_url = ttk.Label(text_frame, text=f"{url}", font=("Helvetica", 10), foreground="#555")
            lbl_url.pack(anchor=tk.W)
            lbl_date = ttk.Label(text_frame, text=f"{date}", font=("Helvetica", 10), foreground="#888")
            lbl_date.pack(anchor=tk.W)
            item_frame.bind("<Double-1>", lambda event, url=url: self.on_history_item_double_click(url))
            for child in item_frame.winfo_children():
                child.bind("<Double-1>", lambda event, url=url: self.on_history_item_double_click(url))
            btn_frame = ttk.Frame(item_frame)
            btn_frame.pack(side=tk.RIGHT, padx=5)
            btn_copy = ttk.Button(
                btn_frame,
                text="📋",
                bootstyle="flat",
                style="History.TButton",
                padding=2,
                command=lambda url=url: self.copy_history_url(url)
            )
            CreateToolTip(btn_copy, self.ui_strings["copy_url"])
            btn_copy.pack(side=tk.LEFT, padx=2, pady=2)
            btn_delete = ttk.Button(
                btn_frame,
                text="🗑",
                bootstyle="flat",
                style="History.TButton",
                padding=2,
                command=lambda u=url: self.delete_history_item(u)
            )
            CreateToolTip(btn_delete, self.ui_strings["delete"])
            btn_delete.pack(side=tk.LEFT, padx=2, pady=2)
            sep = ttk.Separator(self.history_frame, orient="horizontal")
            sep.pack(fill=tk.X, padx=10, pady=5)

    def on_history_item_double_click(self, url):
        self.url_var.set(url)
        self.notebook.select(self.tab_download)

    def copy_history_url(self, url):
        self.clipboard_clear()
        self.clipboard_append(url)
        self.lbl_copy_feedback.config(text=self.ui_strings["copy_copied"])
        self.after(2000, lambda: self.lbl_copy_feedback.config(text=""))

    def delete_history_item(self, url):
        confirm = messagebox.askyesno(self.ui_strings["delete"], self.ui_strings["confirm_delete"])
        if confirm:
            self.history = [e for e in self.history if e.get("url") != url]
            self.save_history()
            self.update_history_view()

    def clear_history(self):
        confirm = messagebox.askyesno(self.ui_strings["clear_history"], self.ui_strings["confirm_clear_history"])
        if confirm:
            self.history = []
            self.save_history()
            self.update_history_view()

    def _load_thumbnail_async(self, thumb_url, label):
        """Charge une miniature en arrière-plan et met à jour le label."""
        def load():
            try:
                r = requests.get(thumb_url, timeout=5)
                r.raise_for_status()
                img_data = r.content
                pil_img = Image.open(io.BytesIO(img_data))
                pil_img = pil_img.resize((60, 34), Image.Resampling.LANCZOS)
                photo = ImageTk.PhotoImage(pil_img)
                self.history_images[thumb_url] = photo
                def update_label():
                    if label.winfo_exists():
                        label.config(image=photo)
                        label.image = photo
                self.after(0, update_label)
            except Exception:
                pass
        threading.Thread(target=load, daemon=True).start()

    # --- Nouvelle fonction pour télécharger la miniature ---
    def download_thumbnail(self):
        thumb_url = self.current_video_info.get("thumbnail_url")
        if not thumb_url:
            messagebox.showerror("Error", "Aucune miniature disponible." if self.language=="fr" else "No thumbnail available.")
            return
        try:
            response = requests.get(thumb_url, stream=True)
            response.raise_for_status()
            ext = os.path.splitext(thumb_url)[1]
            if not ext:
                ext = ".jpg"
            title = self.current_video_info.get("title", "thumbnail")
            default_filename = sanitize_filename(title) + ext
            file_path = filedialog.asksaveasfilename(defaultextension=ext, initialfile=default_filename,
                                                     title=("Enregistrer l'image" if self.language=="fr" else "Save Image"),
                                                     filetypes=[("Image files", "*.jpg *.jpeg *.png *.gif"), ("All files", "*.*")])
            if file_path:
                with open(file_path, "wb") as f:
                    f.write(response.content)
                messagebox.showinfo("Info", "Image téléchargée avec succès." if self.language=="fr" else "Thumbnail downloaded successfully.")
        except Exception as e:
            messagebox.showerror("Error", ("Erreur lors du téléchargement de l'image : " if self.language=="fr" else "Error downloading thumbnail: ") + str(e))

    # --- Fonctions pour l'onglet Conversion ---

    def choose_conversion_file(self):
        file_path = filedialog.askopenfilename(title=self.ui_strings["choose_file"])
        if file_path:
            self.conversion_file_path = file_path
            self.lbl_selected_file.config(text=file_path)
            # Réinitialisation des options d'export
            self.conversion_format_var.set("mp4")
            self.quality_var.set("Standard")
            self.video_resolution_var.set("Original")
            self.audio_sample_rate_var.set("44100")
            if self.combo_conversion_format['values']:
                self.combo_conversion_format.current(0)
            if self.combo_quality['values']:
                self.combo_quality.current(1)  # "Standard" index généralement 1
            if self.combo_resolution['values']:
                self.combo_resolution.current(0)
            if self.combo_sample_rate['values']:
                index = self.combo_sample_rate['values'].index("44100") if "44100" in self.combo_sample_rate['values'] else 0
                self.combo_sample_rate.current(index)
            info = self.get_conversion_file_info(file_path)
            if info:
                self.lbl_conv_file_name.config(text=f"Nom du fichier : {info.get('file_name', 'N/A')}")
                self.lbl_conv_duration.config(text=f"Durée : {format_duration(info.get('duration', 0))}")
                self.lbl_conv_codec.config(text=f"Format : {info.get('format_name', 'N/A')}")
                self.lbl_conv_resolution.config(text=f"Résolution : {info.get('video_resolution', 'N/A')}")
                self.lbl_conv_format.config(text=f"Débit global : {info.get('format_bit_rate', 'N/A')}")
                # Affichage des infos obtenues
                self.lbl_conv_file_name.grid()
                self.lbl_conv_duration.grid()
                self.lbl_conv_codec.grid()
                self.lbl_conv_resolution.grid()
                self.lbl_conv_format.grid()
            thumb = self.extract_thumbnail(file_path)
            if thumb:
                self.lbl_conv_thumbnail.config(image=thumb)
                self.lbl_conv_thumbnail.image = thumb
                self.add_play_overlay()  # Ajout de l'overlay play sur le thumbnail
            else:
                self.lbl_conv_thumbnail.config(image=self.placeholder_tk)
                self.remove_play_overlay()
        else:
            self.remove_play_overlay()

    def get_conversion_file_info(self, file_path):
        """Utilise ffprobe pour extraire des informations techniques supplémentaires."""
        try:
            cmd = [
                "ffprobe", "-v", "error",
                "-show_entries", "format=duration,format_name,bit_rate",
                "-show_streams",
                "-of", "json", file_path
            ]
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            info = json.loads(result.stdout)
            duration = float(info.get("format", {}).get("duration", 0))
            format_name = info.get("format", {}).get("format_name", "N/A")
            format_bit_rate = info.get("format", {}).get("bit_rate", "N/A")
            video_info = {}
            audio_info = {}
            for stream in info.get("streams", []):
                if stream.get("codec_type") == "video" and not video_info:
                    video_info = {
                        "codec": stream.get("codec_name", "N/A"),
                        "width": stream.get("width", "N/A"),
                        "height": stream.get("height", "N/A"),
                        "bit_rate": stream.get("bit_rate", "N/A"),
                        "frame_rate": stream.get("avg_frame_rate", "N/A")
                    }
                elif stream.get("codec_type") == "audio" and not audio_info:
                    audio_info = {
                        "codec": stream.get("codec_name", "N/A"),
                        "sample_rate": stream.get("sample_rate", "N/A"),
                        "channels": stream.get("channels", "N/A"),
                        "bit_rate": stream.get("bit_rate", "N/A")
                    }
            if video_info.get("frame_rate") and video_info.get("frame_rate") != "N/A":
                try:
                    num, den = video_info["frame_rate"].split('/')
                    video_frame_rate = round(float(num)/float(den), 2)
                except Exception:
                    video_frame_rate = "N/A"
            else:
                video_frame_rate = "N/A"
            video_resolution = f"{video_info.get('width')}x{video_info.get('height')}"
            return {
                "file_name": os.path.basename(file_path),
                "duration": duration,
                "format_name": format_name,
                "format_bit_rate": format_bit_rate,
                "video_codec": video_info.get("codec", "N/A"),
                "video_resolution": video_resolution,
                "video_bit_rate": video_info.get("bit_rate", "N/A"),
                "video_frame_rate": video_frame_rate,
                "audio_codec": audio_info.get("codec", "N/A"),
                "audio_sample_rate": audio_info.get("sample_rate", "N/A"),
                "audio_channels": audio_info.get("channels", "N/A"),
                "audio_bit_rate": audio_info.get("bit_rate", "N/A")
            }
        except Exception as e:
            print("Error getting file info:", e)
            return {}

    def extract_thumbnail(self, file_path):
        """Extrait une miniature de la vidéo à 1 seconde."""
        try:
            temp_thumb = file_path + "_thumb.jpg"
            cmd = ["ffmpeg", "-y", "-i", file_path, "-ss", "00:00:01.000", "-vframes", "1", temp_thumb]
            subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
            pil_img = Image.open(temp_thumb)
            pil_img = pil_img.resize((240, 135), Image.Resampling.LANCZOS)
            thumb_tk = ImageTk.PhotoImage(pil_img)
            os.remove(temp_thumb)
            return thumb_tk
        except Exception as e:
            print("Error extracting thumbnail:", e)
            return None

    def play_conversion_file(self):
        """Lance la lecture du fichier dans le lecteur par défaut."""
        if self.conversion_file_path and os.path.exists(self.conversion_file_path):
            system = platform.system()
            if system == "Darwin":
                subprocess.run(["open", self.conversion_file_path])
            elif system == "Windows":
                os.startfile(self.conversion_file_path)
            else:
                subprocess.run(["xdg-open", self.conversion_file_path])

    def on_thumbnail_click(self, event):
        """
        Comportement du clic sur le thumbnail de conversion.
         - Si aucun fichier n'est choisi, lance la sélection de fichier.
         - Sinon, lance la lecture du fichier.
        """
        if not self.conversion_file_path:
            self.choose_conversion_file()
        else:
            self.play_conversion_file()

    def add_play_overlay(self):
        """Ajoute en surimpression une icône play sur le thumbnail."""
        if hasattr(self, 'lbl_play_overlay'):
            self.lbl_play_overlay.destroy()
        self.lbl_play_overlay = ttk.Label(self.lbl_conv_thumbnail, text="▶", background="black", foreground="white", font=("Helvetica", 32))
        self.lbl_play_overlay.place(relx=0.5, rely=0.5, anchor="center")
        self.lbl_play_overlay.bind("<Button-1>", lambda e: self.play_conversion_file())

    def remove_play_overlay(self):
        """Supprime l'overlay play du thumbnail."""
        if hasattr(self, 'lbl_play_overlay'):
            self.lbl_play_overlay.destroy()
            self.lbl_play_overlay = None

    def start_conversion(self):
        if not self.conversion_file_path or not os.path.exists(self.conversion_file_path):
            messagebox.showerror(
                "Error",
                "Veuillez choisir un fichier valide." if self.language=="fr" else "Please choose a valid file."
            )
            return
        duration = self.get_file_duration(self.conversion_file_path)
        if duration is None:
            messagebox.showerror(
                "Error",
                "Impossible d'obtenir la durée du fichier." if self.language=="fr" else "Unable to get file duration."
            )
            return
        self.conversion_duration = duration
        output_format = self.conversion_format_var.get()
        base, ext = os.path.splitext(self.conversion_file_path)
        output_file = f"{base}_converted.{output_format}"
        i = 1
        while os.path.exists(output_file):
            output_file = f"{base}_converted({i}).{output_format}"
            i += 1
        self.conversion_output_file = output_file

        # Construction de la commande ffmpeg avec les options d'export
        cmd = ["ffmpeg", "-i", self.conversion_file_path]
        if output_format.lower() in ["mp4", "mkv", "avi", "mov", "flv", "wmv"]:
            # Vidéo
            cmd.extend(["-c:v", self.video_encoder_var.get()])
            if self.video_resolution_var.get() != "Original":
                res_value = self.video_resolution_var.get()[:-1]
                cmd.extend(["-vf", f"scale=-2:{res_value}"])
            quality_map = {"Low": "28", "Standard": "23", "High": "18", "Very High": "15"}
            cmd.extend(["-crf", quality_map.get(self.quality_var.get(), "23")])
            cmd.extend(["-b:v", self.video_bitrate_var.get()])
            # Ajout du préréglage vidéo
            cmd.extend(["-preset", self.video_preset_var.get()])
            if self.video_framerate_var.get() != "Original":
                cmd.extend(["-r", self.video_framerate_var.get()])
            # Audio
            cmd.extend(["-c:a", self.audio_encoder_var.get()])
            channels = self.audio_channels_var.get()
            if channels == "Mono":
                cmd.extend(["-ac", "1"])
            elif channels == "Stereo":
                cmd.extend(["-ac", "2"])
            cmd.extend(["-b:a", self.audio_bitrate_var.get()])
            if self.audio_sample_rate_var.get() != "44100":
                cmd.extend(["-ar", self.audio_sample_rate_var.get()])
            if self.chk_optimize.instate(["selected"]) and output_format.lower() == "mp4":
                cmd.extend(["-movflags", "faststart"])
        elif output_format.lower() in ["mp3", "ogg", "wav"]:
            cmd.append("-vn")
            cmd.extend(["-c:a", self.audio_encoder_var.get()])
            channels = self.audio_channels_var.get()
            if channels == "Mono":
                cmd.extend(["-ac", "1"])
            elif channels == "Stereo":
                cmd.extend(["-ac", "2"])
            cmd.extend(["-b:a", self.audio_bitrate_var.get()])
            if self.audio_sample_rate_var.get() != "44100":
                cmd.extend(["-ar", self.audio_sample_rate_var.get()])
        cmd.append(self.conversion_output_file)
        self.conversion_cmd = cmd
        self.conversion_progress_val.set(0)
        self.lbl_conversion_status.config(text=self.ui_strings["conversion_in_progress"])
        self.btn_start_conversion.config(state="disabled")
        self.btn_cancel_conversion.config(state="normal")
        self.conversion_cancelled = False
        threading.Thread(target=self.run_conversion_thread, daemon=True).start()

    def run_conversion_thread(self):
        cmd = self.conversion_cmd
        try:
            self.conversion_process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                universal_newlines=True
            )
            while True:
                line = self.conversion_process.stdout.readline()
                if not line:
                    break
                line = line.strip()
                match = re.search(r"time=(\d+):(\d+):(\d+\.\d+)", line)
                if match and self.conversion_duration:
                    hours = int(match.group(1))
                    minutes = int(match.group(2))
                    seconds = float(match.group(3))
                    current_time = hours * 3600 + minutes * 60 + seconds
                    progress_percentage = (current_time / self.conversion_duration) * 100
                    if progress_percentage > 100:
                        progress_percentage = 100
                    self.after(0, self.conversion_progress_val.set, progress_percentage)
                    self.after(0, self.lbl_conversion_status.config, {
                        "text": f"{self.ui_strings['conversion_in_progress']} {progress_percentage:.1f}%"
                    })
                size_match = re.search(r"size=\s*([\d\.]+)(\w+)", line)
                if size_match:
                    size_val = float(size_match.group(1))
                    unit = size_match.group(2)
                    if unit.lower().startswith("k"):
                        size_mb = size_val / 1024
                    elif unit.lower().startswith("m"):
                        size_mb = size_val
                    elif unit.lower().startswith("g"):
                        size_mb = size_val * 1024
                    else:
                        size_mb = size_val
                    self.after(0, self.lbl_estimated_size.config, {
                        "text": f"{self.ui_strings['estimated_size']} ~{size_mb:.1f} MB"
                    })
                if self.conversion_cancelled:
                    self.conversion_process.terminate()
                    break
            self.conversion_process.wait()
            retcode = self.conversion_process.returncode
            if self.conversion_cancelled:
                if os.path.exists(self.conversion_output_file):
                    os.remove(self.conversion_output_file)
                self.after(0, self.lbl_conversion_status.config, {
                    "text": "Conversion annulée." if self.language=="fr" else "Conversion cancelled."
                })
            elif retcode == 0:
                self.after(0, self.lbl_conversion_status.config, {"text": self.ui_strings["conversion_complete"]})
                if os.path.exists(self.conversion_output_file):
                    size_bytes = os.path.getsize(self.conversion_output_file)
                    size_mb = size_bytes / (1024*1024)
                    self.after(0, self.lbl_estimated_size.config, {
                        "text": f"{self.ui_strings['estimated_size']} {size_mb:.1f} MB"
                    })
            else:
                self.after(0, self.lbl_conversion_status.config, {"text": self.ui_strings["conversion_failed"]})
        except Exception as e:
            print("Error during conversion:", e)
            self.after(0, self.lbl_conversion_status.config, {"text": self.ui_strings["conversion_failed"]})
        finally:
            self.conversion_process = None
            self.after(0, self.btn_start_conversion.config, {"state": "normal"})
            self.after(0, self.btn_cancel_conversion.config, {"state": "disabled"})

    def cancel_conversion(self):
        self.conversion_cancelled = True
        if self.conversion_process and self.conversion_process.poll() is None:
            try:
                self.conversion_process.terminate()
                self.lbl_conversion_status.config(
                    text="Annulation en cours..." if self.language=="fr" else "Cancelling conversion..."
                )
            except Exception as e:
                print("Error terminating conversion process:", e)

    def get_file_duration(self, file_path):
        try:
            cmd = [
                "ffprobe",
                "-v", "error",
                "-show_entries", "format=duration",
                "-of", "default=noprint_wrappers=1:nokey=1",
                file_path
            ]
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            duration = float(result.stdout.strip())
            return duration
        except Exception as e:
            print("Error getting file duration:", e)
            return None

    def open_advanced_settings(self):
        adv_win = tk.Toplevel(self)
        adv_win.title("Paramètres avancés" if self.language=="fr" else "Advanced Settings")
        adv_win.grab_set()
        container = ttk.Frame(adv_win, padding=10)
        container.pack(fill=tk.BOTH, expand=True)
        container.columnconfigure(0, weight=1)
        container.columnconfigure(1, weight=1)
        # Disposition côte à côte des paramètres vidéo et audio
        video_params_frame = ttk.Labelframe(container, text="Paramètres vidéo" if self.language=="fr" else "Video Parameters", padding=10)
        video_params_frame.grid(row=0, column=0, padx=5, pady=5, sticky="nsew")
        lbl_video_encoder = ttk.Label(video_params_frame, text="Encodeur vidéo:" if self.language=="fr" else "Video Encoder:")
        lbl_video_encoder.grid(row=0, column=0, sticky="w", padx=5, pady=2)
        combo_video_encoder = ttk.Combobox(video_params_frame, textvariable=self.video_encoder_var, state="readonly", values=["libx264", "libx265", "mpeg4", "libvpx-vp9", "libaom-av1"])
        combo_video_encoder.grid(row=0, column=1, sticky="w", padx=5, pady=2)
        CreateToolTip(combo_video_encoder, "Sélectionner l'encodeur vidéo à utiliser" if self.language=="fr" else "Select the video encoder")
        lbl_video_bitrate = ttk.Label(video_params_frame, text="Bitrate vidéo:" if self.language=="fr" else "Video Bitrate:")
        lbl_video_bitrate.grid(row=1, column=0, sticky="w", padx=5, pady=2)
        combo_video_bitrate = ttk.Combobox(video_params_frame, textvariable=self.video_bitrate_var, state="readonly", values=["500k", "1000k", "2000k", "3000k"])
        combo_video_bitrate.grid(row=1, column=1, sticky="w", padx=5, pady=2)
        CreateToolTip(combo_video_bitrate, "Définit le débit binaire vidéo" if self.language=="fr" else "Sets the video bitrate")
        lbl_video_framerate = ttk.Label(video_params_frame, text="Cadence:" if self.language=="fr" else "Frame Rate:")
        lbl_video_framerate.grid(row=2, column=0, sticky="w", padx=5, pady=2)
        combo_video_framerate = ttk.Combobox(video_params_frame, textvariable=self.video_framerate_var, state="readonly", values=["Original", "24", "30", "60"])
        combo_video_framerate.grid(row=2, column=1, sticky="w", padx=5, pady=2)
        CreateToolTip(combo_video_framerate, "Conserver la cadence d'origine ou forcer une nouvelle cadence" if self.language=="fr" else "Keep original frame rate or set a new one")
        # Nouveau champ pour le préréglage vidéo
        lbl_video_preset = ttk.Label(video_params_frame, text="Préréglage:" if self.language=="fr" else "Preset:")
        lbl_video_preset.grid(row=3, column=0, sticky="w", padx=5, pady=2)
        combo_video_preset = ttk.Combobox(video_params_frame, textvariable=self.video_preset_var, state="readonly", values=["ultrafast", "superfast", "veryfast", "faster", "fast", "medium", "slow", "slower", "veryslow"])
        combo_video_preset.grid(row=3, column=1, sticky="w", padx=5, pady=2)
        CreateToolTip(combo_video_preset, "Sélectionner le préréglage pour l'encodage vidéo" if self.language=="fr" else "Select the preset for video encoding")
        # Paramètres audio
        audio_params_frame = ttk.Labelframe(container, text="Paramètres audio" if self.language=="fr" else "Audio Parameters", padding=10)
        audio_params_frame.grid(row=0, column=1, padx=5, pady=5, sticky="nsew")
        lbl_audio_encoder = ttk.Label(audio_params_frame, text="Encodeur audio:" if self.language=="fr" else "Audio Encoder:")
        lbl_audio_encoder.grid(row=0, column=0, sticky="w", padx=5, pady=2)
        combo_audio_encoder = ttk.Combobox(audio_params_frame, textvariable=self.audio_encoder_var, state="readonly", values=["aac", "mp3", "ac3", "opus", "flac", "pcm_s16le"])
        combo_audio_encoder.grid(row=0, column=1, sticky="w", padx=5, pady=2)
        CreateToolTip(combo_audio_encoder, "Sélectionner l'encodeur audio" if self.language=="fr" else "Select the audio encoder")
        lbl_audio_channels = ttk.Label(audio_params_frame, text="Canaux:" if self.language=="fr" else "Channels:")
        lbl_audio_channels.grid(row=1, column=0, sticky="w", padx=5, pady=2)
        combo_audio_channels = ttk.Combobox(audio_params_frame, textvariable=self.audio_channels_var, state="readonly", values=["Mono", "Stereo"])
        combo_audio_channels.grid(row=1, column=1, sticky="w", padx=5, pady=2)
        CreateToolTip(combo_audio_channels, "Sélectionner le nombre de canaux audio" if self.language=="fr" else "Select the number of audio channels")
        lbl_audio_bitrate = ttk.Label(audio_params_frame, text="Bitrate audio:" if self.language=="fr" else "Audio Bitrate:")
        lbl_audio_bitrate.grid(row=2, column=0, sticky="w", padx=5, pady=2)
        combo_audio_bitrate = ttk.Combobox(audio_params_frame, textvariable=self.audio_bitrate_var, state="readonly", values=["64k", "128k", "192k", "256k", "320k"])
        combo_audio_bitrate.grid(row=2, column=1, sticky="w", padx=5, pady=2)
        CreateToolTip(combo_audio_bitrate, "Définit le débit binaire audio" if self.language=="fr" else "Sets the audio bitrate")
        # Nouveau champ pour l'échantillonnage audio
        lbl_audio_sample_rate = ttk.Label(audio_params_frame, text="Échantillonnage:" if self.language=="fr" else "Sample Rate:")
        lbl_audio_sample_rate.grid(row=3, column=0, sticky="w", padx=5, pady=2)
        combo_audio_sample_rate = ttk.Combobox(audio_params_frame, textvariable=self.audio_sample_rate_var, state="readonly", values=["8000", "11025", "16000", "22050", "32000", "44100", "48000", "88200", "96000"])
        combo_audio_sample_rate.grid(row=3, column=1, sticky="w", padx=5, pady=2)
        CreateToolTip(combo_audio_sample_rate, "Sélectionner la fréquence d'échantillonnage audio" if self.language=="fr" else "Select the audio sample rate")
        btn_close = ttk.Button(adv_win, text="OK", command=adv_win.destroy)
        btn_close.pack(pady=5)

if __name__ == "__main__":
    app = YoutubeDownloaderApp()
    app.mainloop()
