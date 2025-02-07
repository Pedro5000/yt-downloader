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
from PIL import Image, ImageTk
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
        duration = int(duration)
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
    """
    Returns a dictionary with all UI strings for the specified language.
    Pour le français (language=="fr"), les termes sont en français.
    """
    if language == "fr":
        return {
            "title": "ViDL - Téléchargeur Universel",
            "about": "À propos",
            "quit": "Quitter",
            "options": "Options",
            "change_theme": "Changer de thème",
            "download_tab": "Téléchargement",
            "history_tab": "Historique",
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
            "invalid_url": "URL invalide. Veuillez entrer une URL valide (commençant par http:// ou https://)."
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
            "invalid_url": "Invalid URL. Please enter a valid URL (starting with http:// or https://)."
        }

# ---------------------------------------------------------
# Small utility class for tooltips
# (Inspired by https://stackoverflow.com/a/36221216)
# ---------------------------------------------------------
class CreateToolTip(object):
    """
    Creates a tooltip for a given widget.
    """
    def __init__(self, widget, text='widget info'):
        self.waittime = 500     # milliseconds before showing the tooltip
        self.wraplength = 180   # maximum width of the tooltip in pixels
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
        self.tw.wm_overrideredirect(True)  # Remove window border and title bar
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
    """
    Parses available formats and returns:
      - video_format_list: a list of dicts with keys:
            "id": format identifier,
            "width": width in pixels,
            "height": height in pixels,
            "fps": frames per second,
            "tbr": total bitrate in kbps
      - audio_format_list: [(id, description), ...]
    Uses yt-dlp with the -F option to list formats and then filters them.
    """
    try:
        cmd = ["yt-dlp", "-F", video_url]
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        output = result.stdout
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
    """
    Retrieves the thumbnail URL using yt-dlp.
    """
    try:
        cmd = ["yt-dlp", "--get-thumbnail", video_url]
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        thumb_url = result.stdout.strip()
        return thumb_url if thumb_url else None
    except subprocess.CalledProcessError:
        return None

def get_video_info(video_url):
    """
    Retrieves video information (title, uploader, upload date, view count, like count,
    comment count, and duration in seconds) using yt-dlp.
    """
    try:
        cmd = ["yt-dlp", "-j", video_url]
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        data = json.loads(result.stdout)
        title = data.get("title")
        uploader = data.get("uploader")
        upload_date = data.get("upload_date")
        if upload_date and len(upload_date) == 8:
            upload_date = f"{upload_date[:4]}-{upload_date[4:6]}-{upload_date[6:]}"
        view_count = data.get("view_count")
        like_count = data.get("like_count")
        comment_count = data.get("comment_count")
        duration = data.get("duration")  # duration in seconds
        return title, uploader, upload_date, view_count, like_count, comment_count, duration
    except Exception as e:
        print("Error retrieving video info:", e)
        return None, None, None, None, None, None, None

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
        # Élargissement de la fenêtre de 20px (de 800 à 840)
        self.center_window(840, 705)
        try:
            icon_img = tk.PhotoImage(file="/Users/pierredv/Coding/yt-downloader/icon.png")
            self.iconphoto(False, icon_img)
        except:
            pass
        self.lift()
        self.attributes("-topmost", True)
        self.after(10, lambda: self.attributes("-topmost", False))
        # --- Transparence de la fenêtre sur MacOS (alpha à 0.98) ---
        if sys.platform == "darwin":
            self.attributes("-alpha", 0.98)
        default_font = tkFont.Font(family="Segoe UI", size=12)
        self.option_add("*Font", default_font)
        self.style.configure("Card.TFrame", background=self.style.colors.get("light"), padding=10, relief="flat")
        self.style.configure("Card.TLabel", background=self.style.colors.get("light"))
        self.progress_style_name = "download.Horizontal.TProgressbar"
        self.style.configure(self.progress_style_name, thickness=20, borderwidth=0, relief="flat")
        self.style.configure("Analyze.Horizontal.TProgressbar",
                             thickness=10,
                             troughcolor=self.style.colors.get("dark"),
                             background=self.style.colors.get("info"),
                             borderwidth=0)
        # Configuration d'un style pour les boutons dans l'historique (aspect plus compact et flat, à la MacOS)
        self.style.configure("History.TButton", padding=2, font=("Helvetica", 10))
        # Lists to store available formats
        self.video_format_list = []  # list of dicts for video formats
        self.audio_format_list = []  # list of tuples for audio formats
        self.video_format_options = []  # parallel list for combo box selection (for MP4)
        self.url_var = ttk.StringVar()
        self.export_type_var = ttk.StringVar(value="mp4")
        self.selected_format = ttk.StringVar()
        self.status_var = ttk.StringVar(value=self.ui_strings["waiting"])
        self.progress_val = ttk.DoubleVar(value=0.0)
        self.download_target = 0.0
        self.animation_in_progress = False
        self.skip_first_progress_value = True
        self.cancelled = False
        self.open_folder_var = ttk.BooleanVar(value=True)
        self.output_dir = os.path.join(os.path.expanduser("~"), "Downloads")
        self.thumb_image_tk = None
        self.downloaded_file_path = None
        self.download_process = None
        # Variables pour le ré‑encodage
        self.encoding = False
        self.reencode_process = None
        self.cancel_reencode = False
        placeholder_img = Image.new("RGB", (240, 135), (50, 50, 50))
        self.placeholder_tk = ImageTk.PhotoImage(placeholder_img)
        self.url_placeholder = self.ui_strings["url_placeholder"]
        self.url_var.set(self.url_placeholder)
        self.current_video_info = {}
        self.video_duration = None  # duration in seconds
        self.history = []
        self.history_images = {}
        self.history_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), "history.json")
        self.load_history()
        self.build_menu()
        self.build_ui()

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
        # Conserver le nom de l'app en dur : "ViDL"
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
        if self.url_var.get() == "" or self.url_var.get() in [get_ui_strings("en")["url_placeholder"], get_ui_strings("fr")["url_placeholder"]]:
            self.url_var.set(self.url_placeholder)
        self.update_ui_texts()

    def update_ui_texts(self):
        self.title(self.ui_strings["title"])
        self.build_menu()
        self.notebook.tab(self.tab_download, text=self.ui_strings["download_tab"])
        self.notebook.tab(self.tab_history, text=self.ui_strings["history_tab"])
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
        self.lbl_search.config(text=self.ui_strings["search"])
        self.btn_clear_history.config(text=self.ui_strings["clear_history"])

    def build_ui(self):
        container = ttk.Frame(self, padding=15)
        container.pack(fill=tk.BOTH, expand=True)
        self.notebook = ttk.Notebook(container, padding=10)
        self.notebook.pack(fill=tk.BOTH, expand=True)
        self.tab_download = ttk.Frame(self.notebook)
        self.tab_history = ttk.Frame(self.notebook)
        self.notebook.add(self.tab_download, text=self.ui_strings["download_tab"])
        self.notebook.add(self.tab_history, text=self.ui_strings["history_tab"])
        self.build_download_tab()
        self.build_history_tab()

    def build_download_tab(self):
        self.tab_download.columnconfigure(0, weight=1)
        self.title_label = ttk.Label(self.tab_download, text=self.ui_strings["title"],
                                     font=("Helvetica", 24, "bold"), anchor="center", justify="center")
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
        self.analyze_progress = ttk.Progressbar(frm_status, style="Analyze.Horizontal.TProgressbar",
                                                orient=tk.HORIZONTAL, mode='indeterminate')
        self.analyze_progress.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=5, pady=5)
        self.analyze_progress.pack_forget()
        frm_thumbinfo = ttk.Frame(self.frm_analyze)
        frm_thumbinfo.pack(fill=tk.X, pady=10)
        card_frame = ttk.Frame(frm_thumbinfo, style="Card.TFrame")
        card_frame.pack(fill=tk.X, padx=5, pady=5)
        # Affichage de la miniature et des infos associées avec un espacement resserré
        self.lbl_thumbnail = ttk.Label(card_frame, image=self.placeholder_tk)
        self.lbl_thumbnail.grid(row=0, column=0, rowspan=7, padx=10, pady=5)
        self.lbl_video_title = ttk.Label(card_frame, text="Titre :", style="Card.TLabel", font=("Helvetica", 16, "bold"))
        self.lbl_video_title.grid(row=0, column=1, sticky="w", padx=5, pady=(3,1))
        self.lbl_video_channel = ttk.Label(card_frame, text="Chaîne :", style="Card.TLabel", font=("Helvetica", 12))
        self.lbl_video_channel.grid(row=1, column=1, sticky="w", padx=5, pady=1)
        self.lbl_video_date = ttk.Label(card_frame, text="Date :", style="Card.TLabel", font=("Helvetica", 12))
        self.lbl_video_date.grid(row=2, column=1, sticky="w", padx=5, pady=1)
        # Utilisation de la fonction format_duration pour afficher la durée au format mm:ss ou hh:mm:ss
        self.lbl_video_duration = ttk.Label(card_frame, text="Durée :", style="Card.TLabel", font=("Helvetica", 12))
        self.lbl_video_duration.grid(row=3, column=1, sticky="w", padx=5, pady=1)
        self.lbl_video_views = ttk.Label(card_frame, text="Vues :", style="Card.TLabel", font=("Helvetica", 12))
        self.lbl_video_views.grid(row=4, column=1, sticky="w", padx=5, pady=1)
        self.lbl_video_likes = ttk.Label(card_frame, text="Likes :", style="Card.TLabel", font=("Helvetica", 12))
        self.lbl_video_likes.grid(row=5, column=1, sticky="w", padx=5, pady=1)
        self.lbl_video_comments = ttk.Label(card_frame, text="Commentaires :", style="Card.TLabel", font=("Helvetica", 12))
        self.lbl_video_comments.grid(row=6, column=1, sticky="w", padx=5, pady=1)
        card_frame.grid_columnconfigure(1, weight=1)
        self.frm_download = ttk.Labelframe(self.tab_download, text=self.ui_strings["download_labelframe"], padding=15)
        self.frm_download.grid(row=2, column=0, padx=10, pady=10, sticky="ew")
        for col_index in range(4):
            self.frm_download.columnconfigure(col_index, weight=1)
        self.radio_mp4 = ttk.Radiobutton(self.frm_download, text=self.ui_strings["export_mp4"],
                                         variable=self.export_type_var, value="mp4", command=self.update_format_list)
        self.radio_mp4.grid(row=0, column=0, padx=5, pady=5, sticky=tk.W)
        self.radio_mp3 = ttk.Radiobutton(self.frm_download, text=self.ui_strings["export_mp3"],
                                         variable=self.export_type_var, value="mp3", command=self.update_format_list)
        self.radio_mp3.grid(row=0, column=1, padx=5, pady=5, sticky=tk.W)
        self.lbl_format = ttk.Label(self.frm_download, text=self.ui_strings["source_format"])
        self.lbl_format.grid(row=0, column=2, sticky=tk.E, padx=5, pady=5)
        self.combo_format = ttk.Combobox(self.frm_download, textvariable=self.selected_format,
                                         width=40, state="readonly")
        self.combo_format.grid(row=0, column=3, sticky=(tk.W, tk.E), padx=5, pady=5)
        # Pour l'export MP4, on affiche : résolution, fps, bitrate, format et taille estimée (si durée connue)
        # Exemple : "1920x1080, 60fps, 4500 kbps, MP4, ~120.3 MB"
        self.btn_choose_folder = ttk.Button(self.frm_download, text=self.ui_strings["choose_folder"],
                                            bootstyle="secondary", command=self.choose_download_folder)
        self.btn_choose_folder.grid(row=1, column=0, padx=5, pady=5, sticky=tk.W)
        CreateToolTip(self.btn_choose_folder, self.ui_strings["choose_folder_tooltip"])
        btn_frame = ttk.Frame(self.frm_download)
        btn_frame.grid(row=1, column=2, columnspan=2, sticky=tk.E, padx=5, pady=5)
        self.btn_cancel = ttk.Button(btn_frame, text=self.ui_strings["cancel"],
                                     bootstyle="danger-outline", command=self.cancel_download, state="disabled")
        self.btn_cancel.pack(side=tk.LEFT, padx=(0,5))
        CreateToolTip(self.btn_cancel, self.ui_strings["cancel_tooltip"])
        self.btn_download = ttk.Button(btn_frame, text=self.ui_strings["download_button"],
                                       bootstyle="success", command=self.download_video)
        self.btn_download.pack(side=tk.LEFT)
        CreateToolTip(self.btn_download, self.ui_strings["download_button_tooltip"])
        self.chk_open_folder = ttk.Checkbutton(self.frm_download, text=self.ui_strings["open_folder_after_download"],
                                                variable=self.open_folder_var, bootstyle="round-toggle")
        self.chk_open_folder.grid(row=2, column=0, columnspan=4, sticky=tk.W, padx=5, pady=5)
        self.progress_bar = ttk.Progressbar(self.frm_download, style=self.progress_style_name,
                                            orient=tk.HORIZONTAL, mode='determinate',
                                            variable=self.progress_val)
        self.progress_bar.grid(row=3, column=0, columnspan=4, pady=10, sticky="we")
        status_frame = ttk.Frame(self.frm_download)
        status_frame.grid(row=4, column=0, columnspan=4, sticky="we", pady=5)
        self.lbl_status = ttk.Label(status_frame, textvariable=self.status_var, foreground="#aaa")
        self.lbl_status.pack(side=tk.LEFT, fill=tk.X, expand=True)
        # Le même bouton est utilisé pour lancer le ré‑encodage et, pendant l'opération, pour l'arrêter.
        self.btn_reencode = ttk.Button(status_frame, text=self.ui_strings["reencode_mp4"],
                                       bootstyle="primary", command=self.reencode_mp4)
        self.btn_reencode.pack_forget()

    def build_history_tab(self):
        """Builds the history tab where downloaded videos are listed in a scrollable container."""
        search_frame = ttk.Frame(self.tab_history)
        search_frame.pack(fill=tk.X, padx=5, pady=5)
        self.lbl_search = ttk.Label(search_frame, text=self.ui_strings["search"])
        self.lbl_search.pack(side=tk.LEFT, padx=5)
        self.search_var = ttk.StringVar()
        self.ent_search = ttk.Entry(search_frame, textvariable=self.search_var)
        self.ent_search.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=5)
        self.ent_search.bind("<KeyRelease>", self.update_history_view)
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
        self.btn_clear_history = ttk.Button(self.tab_history, text=self.ui_strings["clear_history"],
                                            bootstyle="danger", command=self.clear_history)
        self.btn_clear_history.pack(pady=5)
        self.update_history_view()

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
            messagebox.showwarning(self.ui_strings["about"],
                                   "Veuillez saisir une URL." if self.language=="fr" else "Please enter a URL.")
            return
        if not validate_url(url):
            messagebox.showwarning(self.ui_strings["about"],
                self.ui_strings["invalid_url"])
            return

        self.video_format_list.clear()
        self.audio_format_list.clear()
        self.selected_format.set('')
        self.lbl_analyze_info.config(text=self.ui_strings["analyzing"])
        self.lbl_thumbnail.config(image=self.placeholder_tk)
        self.lbl_video_title.config(text="Titre :" if self.language=="fr" else "Title:")
        self.lbl_video_channel.config(text="Chaîne :" if self.language=="fr" else "Channel:")
        self.lbl_video_date.config(text="Date :" if self.language=="fr" else "Date:")
        # Affichage de la durée en format mm:ss ou hh:mm:ss
        self.lbl_video_duration.config(text="Durée :" if self.language=="fr" else "Duration:")
        self.lbl_video_views.config(text="Vues :" if self.language=="fr" else "Views:")
        self.lbl_video_likes.config(text="Likes :" if self.language=="fr" else "Likes:")
        self.lbl_video_comments.config(text="Commentaires :" if self.language=="fr" else "Comments:")
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
                messagebox.showerror("Error" if self.language=="en" else "Erreur", self.ui_strings["no_format_found"])
                self.lbl_analyze_info.config(text=self.ui_strings["no_format_found"])
                return
            self.video_format_list = v_list
            self.audio_format_list = a_list
            self.update_format_list()
            info_txt = f"{len(v_list)} formats vidéo, {len(a_list)} formats audio." if self.language=="fr" else f"{len(v_list)} video formats, {len(a_list)} audio formats."
            self.lbl_analyze_info.config(text=info_txt)
            if thumb_image:
                self.thumb_image_tk = thumb_image
                self.lbl_thumbnail.config(image=self.thumb_image_tk, text='')
            else:
                self.lbl_thumbnail.config(image='', text="Pas de miniature" if self.language=="fr" else "No thumbnail")
            if video_title:
                self.lbl_video_title.config(text=f"{'Titre' if self.language=='fr' else 'Title'}: {video_title}")
            if video_channel:
                self.lbl_video_channel.config(text=f"{'Chaîne' if self.language=='fr' else 'Channel'}: {video_channel}")
            if video_pubdate:
                self.lbl_video_date.config(text=f"{'Date' if self.language=='fr' else 'Date'}: {video_pubdate}")
            if duration is not None:
                # Affichage de la durée au format mm:ss ou hh:mm:ss
                self.lbl_video_duration.config(text=f"{'Durée' if self.language=='fr' else 'Duration'}: {format_duration(duration)}")
            if view_count is not None:
                self.lbl_video_views.config(text=f"{'Vues' if self.language=='fr' else 'Views'}: {view_count:,}")
            if like_count is not None:
                self.lbl_video_likes.config(text=f"{'Likes' if self.language=='fr' else 'Likes'}: {like_count:,}")
            if comment_count is not None:
                self.lbl_video_comments.config(text=f"{'Commentaires' if self.language=='fr' else 'Comments'}: {comment_count:,}")
            self.current_video_info = {
                "title": video_title,
                "url": url,
                "thumbnail_url": thumb_url
            }
        self.after(0, on_finish)

    def update_format_list(self):
        """
        For export MP4: rebuilds the display strings using resolution, fps, bitrate, file format and,
        if available, the estimated file size.
        """
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
                    est_size = (tbr * self.video_duration) / 8192  # MB
                    display += f", ~{est_size:.1f} MB"
                options.append(fmt)
                display_values.append(display)
            self.video_format_options = options
            self.combo_format['values'] = display_values
            if display_values:
                self.combo_format.current(0)
            # Attacher (ou créer) un tooltip dynamique sur le combobox
            if not hasattr(self, "combo_tooltip"):
                self.combo_tooltip = CreateToolTip(self.combo_format, text="")
            self.combo_format.bind("<<ComboboxSelected>>", self.update_combo_tooltip)
            self.update_combo_tooltip()
        else:
            combo_values = [item[1] for item in self.audio_format_list]
            self.combo_format['values'] = combo_values
            if combo_values:
                self.combo_format.current(0)

    def update_combo_tooltip(self, event=None):
        """Updates the tooltip text for the combobox based on the selected video format."""
        idx = self.combo_format.current()
        if idx < 0:
            text = ""
        else:
            fmt = self.video_format_options[idx]
            w = fmt["width"]
            h = fmt["height"]
            fps = fmt["fps"]
            tbr = fmt["tbr"]
            text = (f"Résolution : {w}x{h}\n"
                    f"FPS : {fps}\n"
                    f"Bitrate : {tbr} kbps\n"
                    f"Format : MP4")
            if self.video_duration:
                est_size = (tbr * self.video_duration) / 8192
                text += f"\nDurée : {self.video_duration} sec\nEst. taille : ~{est_size:.1f} MB\n(Cette taille est approximative)"
        self.combo_tooltip.text = text

    def download_video(self):
        url = self.url_var.get().strip()
        if not url or url == self.url_placeholder:
            messagebox.showwarning("Warning" if self.language=="en" else "Attention", 
                                   "Missing URL." if self.language=="en" else "URL manquante.")
            return
        if not validate_url(url):
            messagebox.showwarning(self.ui_strings["about"],
                self.ui_strings["invalid_url"])
            return

        chosen_export = self.export_type_var.get()
        if chosen_export == "mp4":
            if not self.video_format_list:
                messagebox.showwarning("Warning" if self.language=="en" else "Attention", 
                                       "Please analyze the video first (or no format found)." if self.language=="en" else
                                       "Veuillez analyser la vidéo d'abord (ou aucun format trouvé).")
                return
            idx = self.combo_format.current()
            if idx < 0:
                messagebox.showwarning("Warning" if self.language=="en" else "Attention", 
                                       "No format selected." if self.language=="en" else "Aucun format sélectionné.")
                return
            combo_id = self.video_format_options[idx]["id"]
        else:
            if not self.audio_format_list:
                messagebox.showwarning("Warning" if self.language=="en" else "Attention", 
                                       "Please analyze the video first (or no format found)." if self.language=="en" else
                                       "Veuillez analyser la vidéo d'abord (ou aucun format trouvé).")
                return
            current_val = self.selected_format.get().strip()
            if not current_val:
                messagebox.showwarning("Warning" if self.language=="en" else "Attention", 
                                       "No format selected." if self.language=="en" else "Aucun format sélectionné.")
                return
            combo_id = current_val.split("|")[0].strip()

        self.downloaded_file_path = None
        # Génération d'un nom de fichier unique en utilisant le titre (si disponible) et en normalisant l'URL
        if "title" in self.current_video_info and self.current_video_info["title"]:
            base = sanitize_filename(self.current_video_info["title"])
        else:
            base = "video"
        ext = "mp4" if chosen_export == "mp4" else "mp3"
        candidate = os.path.join(self.output_dir, f"{base}.{ext}")
        i = 1
        while os.path.exists(candidate):
            candidate = os.path.join(self.output_dir, f"{base} ({i}).{ext}")
            i += 1
        output_template = candidate

        if chosen_export == "mp4":
            cmd = [
                "yt-dlp",
                "-f", combo_id,
                "--merge-output-format", "mp4",
                "--newline",
                "-o", output_template,
                url
            ]
        else:
            cmd = [
                "yt-dlp",
                "-f", combo_id,
                "--extract-audio",
                "--audio-format", "mp3",
                "--newline",
                "-o", output_template,
                url
            ]
        self.progress_val.set(0.0)
        self.download_target = 0.0
        self.status_var.set(self.ui_strings["download_in_progress"] + " 0.0%")
        self.skip_first_progress_value = True
        self.btn_reencode.pack_forget()
        self.cancelled = False
        self.btn_cancel.config(state="normal")
        threading.Thread(target=self.run_download_thread, args=(cmd,), daemon=True).start()

    def run_download_thread(self, cmd):
        download_regex = re.compile(r'^\[download\]\s+([\d\.]+)%')
        destination_regex = re.compile(r'^\[download\]\s+Destination:\s+(.+)$')
        merger_regex = re.compile(r'^\[Merger\]\s+Merging formats into\s+"(.+)"$')
        process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   text=True, universal_newlines=True)
        self.download_process = process
        for line in process.stdout:
            line = line.strip()
            match = download_regex.match(line)
            if match:
                try:
                    val_float = float(match.group(1))
                except ValueError:
                    val_float = 0.0
                if self.skip_first_progress_value:
                    self.skip_first_progress_value = False
                    continue
                current_v = self.progress_val.get()
                new_val = max(current_v, val_float)
                self.after(0, self.set_smooth_target, new_val)
            match_dest = destination_regex.match(line)
            if match_dest:
                self.downloaded_file_path = match_dest.group(1).strip()
            match_merger = merger_regex.match(line)
            if match_merger:
                final_merged = match_merger.group(1).strip()
                self.downloaded_file_path = final_merged
        process.wait()
        retcode = process.returncode
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
                messagebox.showerror("Error" if self.language=="en" else "Erreur", self.ui_strings["download_failed"])

    def update_encoding_progress(self, percent):
        self.progress_val.set(percent)
        self.update_idletasks()

    def reencode_mp4(self):
        """
        Lance le ré‑encodage du fichier MP4 et affiche la progression via la barre de progression.
        Si le ré‑encodage est en cours, le bouton permet de l'arrêter.
        """
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
                        # Lecture de la sortie de ffmpeg ligne par ligne pour mettre à jour la progression
                        while True:
                            line = self.reencode_process.stdout.readline()
                            if not line:
                                break
                            line = line.strip()
                            # Exemple de ligne : "frame= 5078 fps=197 q=24.0 size=   33024KiB time=00:02:49.36 bitrate=1597.3kbits/s speed=6.58x"
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
                                self.after(0, self.status_var.set, f"{self.ui_strings['reencode_in_progress']} {progress_percentage:.1f}%")
                            if self.cancel_reencode:
                                self.reencode_process.terminate()
                                break
                        self.reencode_process.wait()
                        if self.cancel_reencode:
                            if os.path.exists(reencoded_file):
                                os.remove(reencoded_file)
                            self.after(0, self.status_var.set, "Re‑encoding cancelled." if self.language=="en" else "Ré‑encodage annulé.")
                        else:
                            os.replace(reencoded_file, self.downloaded_file_path)
                            self.after(0, self.status_var.set, "MP4 file re‑encoded and optimized." if self.language=="en" else "Fichier MP4 ré‑encodé et optimisé.")
                            self.after(0, self.progress_val.set, 100)
                    except Exception as e:
                        print("Error during MP4 re‑encoding:", e)
                        self.after(0, self.status_var.set, "Error during re‑encoding." if self.language=="en" else "Erreur lors du ré‑encodage.")
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
                    self.status_var.set("Stopping re‑encoding..." if self.language=="en" else "Arrêt du ré‑encodage en cours...")
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
        for idx, entry in enumerate(self.history):
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
            else:
                try:
                    r = requests.get(thumb_url, timeout=5)
                    r.raise_for_status()
                    img_data = r.content
                    pil_img = Image.open(io.BytesIO(img_data))
                    # Redimensionner à une taille plus petite pour un aspect élégant et MacOS-ish
                    pil_img = pil_img.resize((60, 34), Image.Resampling.LANCZOS)
                    photo = ImageTk.PhotoImage(pil_img)
                except:
                    photo = self.placeholder_tk
                self.history_images[thumb_url] = photo
            lbl_thumbnail = ttk.Label(item_frame, image=photo)
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
            btn_copy = ttk.Button(btn_frame, text="📋", bootstyle="flat", style="History.TButton", padding=2,
                                  command=lambda url=url: self.copy_history_url(url))
            CreateToolTip(btn_copy, self.ui_strings["copy_url"])
            btn_copy.pack(side=tk.LEFT, padx=2, pady=2)
            btn_delete = ttk.Button(btn_frame, text="🗑", bootstyle="flat", style="History.TButton", padding=2,
                                    command=lambda idx=idx: self.delete_history_item(idx))
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
        messagebox.showinfo("Info", self.ui_strings["copy_copied"])

    def delete_history_item(self, idx):
        confirm = messagebox.askyesno(self.ui_strings["delete"], self.ui_strings["confirm_delete"])
        if confirm:
            try:
                del self.history[idx]
                self.save_history()
                self.update_history_view()
            except Exception as e:
                messagebox.showerror("Error", f"An error occurred while deleting the entry:\n{e}")

    def clear_history(self):
        confirm = messagebox.askyesno(self.ui_strings["clear_history"], self.ui_strings["confirm_clear_history"])
        if confirm:
            self.history = []
            self.save_history()
            self.update_history_view()

if __name__ == "__main__":
    app = YoutubeDownloaderApp()
    app.mainloop()
