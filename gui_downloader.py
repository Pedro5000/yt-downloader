#!/usr/bin/env python3
import os
import re
import sys
import subprocess
import threading
import platform
import io
import json
import time
import requests
from PIL import Image, ImageTk
import tkinter as tk
import tkinter.font as tkFont
import tkinter.filedialog as filedialog
import ttkbootstrap as ttk
from ttkbootstrap.constants import *
from tkinter import messagebox

# ---------------------------------------------------------
# Petite classe utilitaire pour les tooltips
# (Inspirée de https://stackoverflow.com/a/36221216)
# ---------------------------------------------------------
class CreateToolTip(object):
    """
    Crée une infobulle pour un widget donné.
    """
    def __init__(self, widget, text='widget info'):
        self.waittime = 500     # millisecondes avant affichage
        self.wraplength = 180   # largeur maximale de l'infobulle en pixels
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
        self.tw.wm_overrideredirect(True)  # Pas de bordure ni de barre de titre
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
# Fonctions d'analyse de la vidéo et récupération d'infos
# ---------------------------------------------------------
def parse_available_formats(video_url):
    """
    Analyse les formats disponibles (≥360p) et renvoie :
      - video_format_list : [(id, desc), ...]
      - audio_format_list : [(id, desc), ...]
    Utilise yt-dlp -F pour lister, puis filtre.
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
            audio_only_list.append((fmt_id, rest, tbr_kbps))
            if ext in ["mp4", "m4a"] and tbr_kbps > best_audio_mp4[2]:
                best_audio_mp4 = (fmt_id, rest, tbr_kbps)
            if tbr_kbps > best_audio_any[2]:
                best_audio_any = (fmt_id, rest, tbr_kbps)
        else:
            mres = resolution_regex.search(rest)
            if not mres:
                continue
            w, h = map(int, mres.groups())
            if min(w, h) < 360:
                continue

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
                    fps_val = 30  # par défaut

            if fps_val not in (30, 60):
                continue

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

    all_keys = set(video_only_dict.keys()) | set(mux_dict.keys())
    video_format_list = []

    def sort_key(k):
        w, h, f = k
        return (min(w, h), f)

    for whf in sorted(all_keys, key=sort_key):
        w, h, fps_val = whf
        mux_fid, mux_desc, mux_tbr = mux_dict.get(whf, (None, None, 0))
        vid_fid, vid_desc, vid_tbr = video_only_dict.get(whf, (None, None, 0))

        combo_tbr = 0
        combo_id = None
        combo_desc = None
        if vid_fid and best_audio_id:
            combo_tbr = vid_tbr + best_audio_abr
            combo_id = f"{vid_fid}+{best_audio_id}"
            combo_desc = f"{combo_id} | {w}x{h}@{fps_val}fps VIDEO: {vid_desc} + AUDIO: {best_audio_desc}"

        if combo_tbr > mux_tbr:
            if combo_id:
                video_format_list.append((combo_id, combo_desc))
        else:
            if mux_fid:
                display = f"{mux_fid} | {w}x{h}@{fps_val}fps {mux_desc}"
                video_format_list.append((mux_fid, display))

    final_video_list = [(x[0], x[1]) for x in video_format_list]

    audio_list_filtered = []
    for (fid, desc, abr) in audio_only_list:
        if ("mp4" in desc.lower()) or ("m4a" in desc.lower()):
            audio_list_filtered.append((fid, f"{fid} | {desc}"))

    if not audio_list_filtered and best_audio_any[0]:
        fid, bd, _ = best_audio_any
        audio_list_filtered = [(fid, f"{fid} | {bd}")]

    return final_video_list, audio_list_filtered

def get_thumbnail_url(video_url):
    """
    Récupère l'URL du thumbnail via : yt-dlp --get-thumbnail <URL>
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
    Récupère les informations de la vidéo via yt-dlp en mode JSON.
    Renvoie un tuple (title, uploader, upload_date, view_count, like_count, comment_count)
    ou (None, None, None, None, None, None) en cas d'erreur.
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
        return title, uploader, upload_date, view_count, like_count, comment_count
    except Exception as e:
        print("Erreur lors de la récupération des infos :", e)
        return None, None, None, None, None, None

# ---------------------------------------------------------
# Classe principale de l'application
# ---------------------------------------------------------
class YoutubeDownloaderApp(ttk.Window):
    """
    ViDL – Téléchargeur YouTube avec une interface modernisée.
    """
    def __init__(self, *args, **kwargs):
        # Utiliser Darkly par défaut
        kwargs["themename"] = kwargs.get("themename", "darkly")
        super().__init__(*args, **kwargs)

        self.title("ViDL - Téléchargeur YouTube")
        sys.argv[0] = "ViDL"

        # Centrer la fenêtre (800 x 650) pour un cadre légèrement agrandi
        self.center_window(800, 650)

        # Icône de l'application
        try:
            icon_img = tk.PhotoImage(file="icon.png")
            self.iconphoto(False, icon_img)
        except:
            pass

        # Mettre la fenêtre au premier plan brièvement
        self.lift()
        self.attributes("-topmost", True)
        self.after(10, lambda: self.attributes("-topmost", False))

        # Police par défaut
        default_font = tkFont.Font(family="Helvetica", size=12)
        self.option_add("*Font", default_font)

        # Configuration de styles personnalisés pour un look moderne
        self.style.configure("Card.TFrame", background=self.style.colors.get("light"), padding=10, relief="flat")
        self.style.configure("Card.TLabel", background=self.style.colors.get("light"))
        self.progress_style_name = "download.Horizontal.TProgressbar"
        # Agrandir la barre de progrès et tenter d'arrondir ses bords (si ttkbootstrap le permet)
        self.style.configure(self.progress_style_name, thickness=20, borderwidth=0, relief="flat")
        # Nouveau style pour la barre d'analyse
        self.style.configure("Analyze.Horizontal.TProgressbar",
                             thickness=10,
                             troughcolor=self.style.colors.get("dark"),
                             background=self.style.colors.get("info"),
                             borderwidth=0)

        # Variables de données
        self.video_format_list = []
        self.audio_format_list = []
        self.url_var = ttk.StringVar()
        self.export_type_var = ttk.StringVar(value="mp4")
        self.selected_format = ttk.StringVar()
        self.status_var = ttk.StringVar(value="En attente...")
        self.progress_val = ttk.DoubleVar(value=0.0)
        self.download_target = 0.0
        self.animation_in_progress = False
        self.skip_first_progress_value = True
        self.cancelled = False  # Pour suivre si l'utilisateur a annulé

        self.open_folder_var = ttk.BooleanVar(value=True)
        self.output_dir = os.path.join(os.path.expanduser("~"), "Downloads")
        self.thumb_image_tk = None
        self.downloaded_file_path = None
        self.download_process = None  # Pour gérer l'annulation

        # Placeholder pour la miniature
        placeholder_img = Image.new("RGB", (240, 135), (50, 50, 50))
        self.placeholder_tk = ImageTk.PhotoImage(placeholder_img)

        # Placeholder pour la barre de recherche
        self.url_placeholder = "Entrez l'URL de la vidéo YouTube…"
        self.url_var.set(self.url_placeholder)

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
        menu_vidl.add_command(label="À propos", command=self.show_about)
        menu_vidl.add_separator()
        menu_vidl.add_command(label="Quitter", command=self.quit)
        menubar.add_cascade(label="ViDL", menu=menu_vidl)

        menu_options = ttk.Menu(menubar, tearoff=False)
        menu_themes = ttk.Menu(menu_options, tearoff=False)
        theme_list = ["darkly", "flatly", "litera", "journal", "cyborg", "minty"]
        for theme_name in theme_list:
            menu_themes.add_command(
                label=theme_name,
                command=lambda t=theme_name: self.change_theme(t)
            )
        menu_options.add_cascade(label="Changer de thème", menu=menu_themes)
        menubar.add_cascade(label="Options", menu=menu_options)

        self.config(menu=menubar)

    def show_about(self):
        messagebox.showinfo("À propos",
            "ViDL - Téléchargeur YouTube\n© 2025")

    def change_theme(self, theme_name):
        self.style.theme_use(theme_name)

    def build_ui(self):
        container = ttk.Frame(self, padding=15)
        container.pack(fill=tk.BOTH, expand=True)

        # Titre de l'application
        title_label = ttk.Label(container, text="ViDL - Téléchargeur YouTube",
                                font=("Helvetica", 24, "bold"))
        title_label.pack(pady=(0, 10))

        # --- Section Analyse de la vidéo
        frm_analyze = ttk.Labelframe(container, text="Analyse de la vidéo", padding=15)
        frm_analyze.pack(fill=tk.X, pady=10)

        # Ligne 1 : Barre de recherche
        frm_search = ttk.Frame(frm_analyze)
        frm_search.pack(fill=tk.X, padx=5, pady=5)

        lbl_url = ttk.Label(frm_search, text="URL :")
        lbl_url.pack(side=tk.LEFT, padx=5, pady=5)

        self.ent_url = ttk.Entry(frm_search, textvariable=self.url_var, width=60)
        self.ent_url.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=5, pady=5)
        self.ent_url.bind("<FocusIn>", self.clear_url_placeholder)
        self.ent_url.bind("<FocusOut>", self.add_url_placeholder)

        # Bouton avec uniquement l'icône pour coller l'URL
        btn_paste = ttk.Button(frm_search, text="📋",
                               bootstyle="secondary",
                               command=self.paste_url)
        btn_paste.pack(side=tk.LEFT, padx=5, pady=5)
        CreateToolTip(btn_paste, "Collez l'URL depuis le presse-papiers")

        btn_analyze = ttk.Button(frm_search, text="🔍 Analyser",
                                 bootstyle="primary",
                                 command=self.analyze_video)
        btn_analyze.pack(side=tk.LEFT, padx=5, pady=5)
        CreateToolTip(btn_analyze, "Analyser la vidéo")

        # Ligne 2 : Zone de statut et barre de progression d'analyse
        frm_status = ttk.Frame(frm_analyze)
        frm_status.pack(fill=tk.X, padx=5, pady=(0,5))
        self.lbl_analyze_info = ttk.Label(frm_status, text="", foreground="#aaa")
        self.lbl_analyze_info.pack(side=tk.LEFT, padx=5, pady=5)
        # Barre de progression d'analyse (style personnalisé)
        self.analyze_progress = ttk.Progressbar(frm_status, 
                                                style="Analyze.Horizontal.TProgressbar",
                                                orient=tk.HORIZONTAL,
                                                mode='indeterminate')
        self.analyze_progress.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=5, pady=5)
        self.analyze_progress.pack_forget()  # Cachée par défaut

        # Ligne 3 : Affichage de la miniature et infos dans une "card"
        frm_thumbinfo = ttk.Frame(frm_analyze)
        frm_thumbinfo.pack(fill=tk.X, pady=10)

        card_frame = ttk.Frame(frm_thumbinfo, style="Card.TFrame")
        card_frame.pack(fill=tk.X, padx=5, pady=5)

        # Colonne 1 : Miniature (étendue sur 6 lignes pour inclure les commentaires)
        self.lbl_thumbnail = ttk.Label(card_frame, image=self.placeholder_tk)
        self.lbl_thumbnail.grid(row=0, column=0, rowspan=6, padx=10, pady=5)

        # Colonne 2 : Informations de la vidéo
        self.lbl_video_title = ttk.Label(card_frame, text="Titre :", style="Card.TLabel", font=("Helvetica", 16, "bold"))
        self.lbl_video_title.grid(row=0, column=1, sticky="w", padx=5, pady=(5,2))

        self.lbl_video_channel = ttk.Label(card_frame, text="Chaîne :", style="Card.TLabel", font=("Helvetica", 12))
        self.lbl_video_channel.grid(row=1, column=1, sticky="w", padx=5, pady=2)

        self.lbl_video_date = ttk.Label(card_frame, text="Date :", style="Card.TLabel", font=("Helvetica", 12))
        self.lbl_video_date.grid(row=2, column=1, sticky="w", padx=5, pady=2)

        self.lbl_video_views = ttk.Label(card_frame, text="Vues :", style="Card.TLabel", font=("Helvetica", 12))
        self.lbl_video_views.grid(row=3, column=1, sticky="w", padx=5, pady=2)

        self.lbl_video_likes = ttk.Label(card_frame, text="Likes :", style="Card.TLabel", font=("Helvetica", 12))
        self.lbl_video_likes.grid(row=4, column=1, sticky="w", padx=5, pady=2)
        
        # Nouveau champ pour les commentaires
        self.lbl_video_comments = ttk.Label(card_frame, text="Commentaires :", style="Card.TLabel", font=("Helvetica", 12))
        self.lbl_video_comments.grid(row=5, column=1, sticky="w", padx=5, pady=2)

        # --- Section Téléchargement
        frm_download = ttk.Labelframe(container, text="Téléchargement", padding=15)
        frm_download.pack(fill=tk.X, pady=10)

        for col_index in range(4):
            frm_download.columnconfigure(col_index, weight=1)

        radio_mp4 = ttk.Radiobutton(frm_download, text="Exporter en mp4",
                                    variable=self.export_type_var, value="mp4",
                                    command=self.update_format_list)
        radio_mp4.grid(row=0, column=0, padx=5, pady=5, sticky=tk.W)

        radio_mp3 = ttk.Radiobutton(frm_download, text="Exporter en mp3",
                                    variable=self.export_type_var, value="mp3",
                                    command=self.update_format_list)
        radio_mp3.grid(row=0, column=1, padx=5, pady=5, sticky=tk.W)

        lbl_format = ttk.Label(frm_download, text="Format d'origine :")
        lbl_format.grid(row=0, column=2, sticky=tk.E, padx=5, pady=5)

        self.combo_format = ttk.Combobox(frm_download, textvariable=self.selected_format,
                                         width=40, state="readonly")
        self.combo_format.grid(row=0, column=3, sticky=(tk.W, tk.E), padx=5, pady=5)

        btn_choose_dir = ttk.Button(frm_download, text="Choisir dossier...",
                                    bootstyle="secondary",
                                    command=self.choose_download_folder)
        btn_choose_dir.grid(row=1, column=0, padx=5, pady=5, sticky=tk.W)
        CreateToolTip(btn_choose_dir, "Sélectionnez le dossier de téléchargement")

        # Création d'un conteneur pour les boutons Annuler et Télécharger, côte à côte,
        # avec le bouton Annuler placé à gauche de Télécharger.
        btn_frame = ttk.Frame(frm_download)
        btn_frame.grid(row=1, column=2, columnspan=2, sticky=tk.E, padx=5, pady=5)
        self.btn_cancel = ttk.Button(btn_frame, text="✖️ Annuler", bootstyle="danger-outline",
                                     command=self.cancel_download, state="disabled")
        self.btn_cancel.pack(side=tk.LEFT, padx=(0, 5))
        CreateToolTip(self.btn_cancel, "Annuler le téléchargement")
        btn_download = ttk.Button(btn_frame, text="📥 Télécharger", bootstyle="success",
                                  command=self.download_video)
        btn_download.pack(side=tk.LEFT)
        CreateToolTip(btn_download, "Démarrer le téléchargement")

        chk_open_folder = ttk.Checkbutton(frm_download,
                                          text="Ouvrir le dossier à la fin",
                                          variable=self.open_folder_var,
                                          bootstyle="round-toggle")
        chk_open_folder.grid(row=2, column=0, columnspan=4, sticky=tk.W, padx=5, pady=5)

        self.progress_bar = ttk.Progressbar(
            frm_download,
            style=self.progress_style_name,
            orient=tk.HORIZONTAL,
            mode='determinate',
            variable=self.progress_val
        )
        self.progress_bar.grid(row=3, column=0, columnspan=4, pady=10, sticky="we")

        self.lbl_status = ttk.Label(frm_download, textvariable=self.status_var,
                                    foreground="#aaa")
        self.lbl_status.grid(row=4, column=0, columnspan=4, sticky=tk.W, pady=5)

    # ---------------------------------------------------------
    # Gestion du placeholder dans la barre de recherche
    # ---------------------------------------------------------
    def clear_url_placeholder(self, event):
        if self.url_var.get() == self.url_placeholder:
            self.url_var.set("")

    def add_url_placeholder(self, event):
        if not self.url_var.get():
            self.url_var.set(self.url_placeholder)

    # ---------------------------------------------------------
    # Méthodes d'interaction de l'interface
    # ---------------------------------------------------------
    def paste_url(self):
        """Colle le contenu du presse-papiers dans la barre d'URL."""
        try:
            txt = self.clipboard_get()
            if txt == self.url_placeholder:
                return
            self.url_var.set(txt)
        except tk.TclError:
            messagebox.showwarning("Attention", "Le presse-papiers est vide ou invalide.")

    def choose_download_folder(self):
        new_dir = filedialog.askdirectory(title="Choisir le dossier de téléchargement")
        if new_dir:
            self.output_dir = new_dir
            messagebox.showinfo("Dossier choisi",
                                f"Les vidéos seront enregistrées dans :\n{self.output_dir}")

    # ---------------------------------------------------------
    # Analyse de la vidéo (texte fixe "Analyse en cours…")
    # ---------------------------------------------------------
    def analyze_video(self):
        url = self.url_var.get().strip()
        if not url or url == self.url_placeholder:
            messagebox.showwarning("Attention", "Veuillez saisir une URL.")
            return

        self.video_format_list.clear()
        self.audio_format_list.clear()
        self.combo_format['values'] = []
        self.selected_format.set('')
        # Afficher le texte fixe "Analyse en cours…"
        self.lbl_analyze_info.config(text="Analyse en cours…")

        # Réinitialiser la miniature et les infos
        self.lbl_thumbnail.config(image=self.placeholder_tk)
        self.lbl_video_title.config(text="Titre :")
        self.lbl_video_channel.config(text="Chaîne :")
        self.lbl_video_date.config(text="Date :")
        self.lbl_video_views.config(text="Vues :")
        self.lbl_video_likes.config(text="Likes :")
        self.lbl_video_comments.config(text="Commentaires :")

        # Afficher la barre de progression d'analyse et la démarrer
        self.analyze_progress.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=5, pady=5)
        self.analyze_progress.start(10)

        threading.Thread(target=self.run_analysis_thread, args=(url,), daemon=True).start()

    def run_analysis_thread(self, url):
        # 1) Formats disponibles
        v_list, a_list = parse_available_formats(url)
        # 2) URL du thumbnail
        thumb_url = get_thumbnail_url(url)
        # 3) Infos (titre, chaîne, date, vues, likes, commentaires)
        video_title, video_channel, video_pubdate, view_count, like_count, comment_count = get_video_info(url)

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
                messagebox.showerror("Erreur", "Aucun format exploitable trouvé.")
                self.lbl_analyze_info.config(text="Aucun format exploitable trouvé.")
                return

            self.video_format_list = v_list
            self.audio_format_list = a_list
            self.update_format_list()

            info_txt = f"{len(v_list)} formats vidéo, {len(a_list)} formats audio."
            self.lbl_analyze_info.config(text=info_txt)

            if thumb_image:
                self.thumb_image_tk = thumb_image
                self.lbl_thumbnail.config(image=self.thumb_image_tk, text='')
            else:
                self.lbl_thumbnail.config(image='', text="Pas de miniature")

            if video_title:
                self.lbl_video_title.config(text=f"Titre : {video_title}")
            if video_channel:
                self.lbl_video_channel.config(text=f"Chaîne : {video_channel}")
            if video_pubdate:
                self.lbl_video_date.config(text=f"Date : {video_pubdate}")
            if view_count is not None:
                self.lbl_video_views.config(text=f"Vues : {view_count:,}")
            if like_count is not None:
                self.lbl_video_likes.config(text=f"Likes : {like_count:,}")
            if comment_count is not None:
                self.lbl_video_comments.config(text=f"Commentaires : {comment_count:,}")

        self.after(0, on_finish)

    def update_format_list(self):
        chosen_export = self.export_type_var.get()
        if chosen_export == "mp4":
            current_list = self.video_format_list
        else:
            current_list = self.audio_format_list

        combo_values = [item[1] for item in current_list]
        self.combo_format['values'] = combo_values
        if combo_values:
            self.combo_format.current(0)
        else:
            self.selected_format.set('')

    # ---------------------------------------------------------
    # Téléchargement de la vidéo
    # ---------------------------------------------------------
    def download_video(self):
        url = self.url_var.get().strip()
        if not url or url == self.url_placeholder:
            messagebox.showwarning("Attention", "URL manquante.")
            return

        chosen_export = self.export_type_var.get()
        if chosen_export == "mp4":
            current_list = self.video_format_list
        else:
            current_list = self.audio_format_list

        if not current_list:
            messagebox.showwarning("Attention", "Veuillez analyser la vidéo d'abord (ou aucun format trouvé).")
            return

        current_val = self.selected_format.get().strip()
        if not current_val:
            messagebox.showwarning("Attention", "Aucun format sélectionné.")
            return

        combo_id = current_val.split("|")[0].strip()
        self.downloaded_file_path = None
        output_template = os.path.join(self.output_dir, "%(title)s.%(ext)s")

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
        self.status_var.set("Téléchargement en cours... 0.0%")
        self.skip_first_progress_value = True

        # Réinitialiser l'indicateur d'annulation
        self.cancelled = False

        # Activer le bouton Annuler
        self.btn_cancel.config(state="normal")
        threading.Thread(target=self.run_download_thread, args=(cmd,), daemon=True).start()

    def run_download_thread(self, cmd):
        download_regex = re.compile(r'^\[download\]\s+([\d\.]+)%')
        destination_regex = re.compile(r'^\[download\]\s+Destination:\s+(.+)$')
        merger_regex = re.compile(r'^\[Merger\]\s+Merging formats into\s+"(.+)"$')

        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            universal_newlines=True
        )
        self.download_process = process

        for line in process.stdout:
            line = line.strip()
            match = download_regex.match(line)
            if match:
                val_str = match.group(1)
                try:
                    val_float = float(val_str)
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
                self.status_var.set("Le téléchargement a été arrêté.")
            except Exception as e:
                print("Erreur lors de l'annulation :", e)
            self.btn_cancel.config(state="disabled")

    # ---------------------------------------------------------
    # Animation de la barre de progression pour le téléchargement
    # ---------------------------------------------------------
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
            self.status_var.set(f"Téléchargement en cours... {target:.1f}%")
        else:
            step = (target - current) * 0.2
            new_val = current + step
            self.progress_val.set(new_val)
            self.status_var.set(f"Téléchargement en cours... {new_val:.1f}%")
            self.after(50, self.animate_progress)

    def finish_progress(self, success):
        self.animation_in_progress = False

        if success:
            self.download_target = 100
            self.progress_val.set(100)
            file_size_msg = ""
            if self.downloaded_file_path:
                # Attendre que le fichier soit effectivement présent
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
                        print("Erreur lors de l'obtention de la taille du fichier:", e)
            self.status_var.set(f"Téléchargement terminé{file_size_msg}.")
            if self.open_folder_var.get():
                self.open_downloads_folder()
        else:
            self.download_target = 0
            self.progress_val.set(0)
            if self.cancelled:
                self.status_var.set("Le téléchargement a été arrêté.")
                self.cancelled = False  # Réinitialiser pour la prochaine opération
            else:
                self.status_var.set("Échec du téléchargement.")
                messagebox.showerror("Erreur", "Erreur lors du téléchargement.")

    def open_downloads_folder(self):
        system = platform.system()
        if system == "Darwin":
            subprocess.run(["open", self.output_dir])
        elif system == "Windows":
            os.startfile(self.output_dir)
        else:
            subprocess.run(["xdg-open", self.output_dir])


if __name__ == "__main__":
    app = YoutubeDownloaderApp()
    app.mainloop()
