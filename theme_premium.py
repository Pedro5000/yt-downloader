"""
Theme Premium macOS pour ViDL
Palette de couleurs et styles inspirés de macOS Sonoma
"""

import platform

# Palette de couleurs - Mode Sombre (macOS Dark)
COLORS_DARK = {
    # Backgrounds
    "bg_primary": "#1C1C1E",
    "bg_secondary": "#2C2C2E",
    "bg_tertiary": "#3A3A3C",
    "bg_elevated": "#48484A",

    # Surfaces & Cards
    "surface": "#2C2C2E",
    "surface_hover": "#3A3A3C",
    "surface_pressed": "#1C1C1E",

    # Text (sans alpha - tkinter ne supporte pas)
    "text_primary": "#FFFFFF",
    "text_secondary": "#EBEBF5",
    "text_tertiary": "#8E8E93",
    "text_quaternary": "#636366",

    # Accent Colors (Bleu macOS)
    "accent": "#0A84FF",
    "accent_hover": "#409CFF",
    "accent_pressed": "#0071E3",

    # Semantic Colors
    "success": "#30D158",
    "success_muted": "#234D2C",
    "warning": "#FFD60A",
    "error": "#FF453A",
    "error_muted": "#4D2623",

    # Borders & Separators
    "border": "#38383A",
    "border_focused": "#0A84FF",
    "separator": "#545458",
}

# Palette de couleurs - Mode Clair
COLORS_LIGHT = {
    # Backgrounds
    "bg_primary": "#FFFFFF",
    "bg_secondary": "#F2F2F7",
    "bg_tertiary": "#E5E5EA",
    "bg_elevated": "#FFFFFF",

    # Surfaces & Cards
    "surface": "#FFFFFF",
    "surface_hover": "#F2F2F7",
    "surface_pressed": "#E5E5EA",

    # Text (sans alpha - tkinter ne supporte pas)
    "text_primary": "#000000",
    "text_secondary": "#3C3C43",
    "text_tertiary": "#8E8E93",
    "text_quaternary": "#AEAEB2",

    # Accent Colors
    "accent": "#007AFF",
    "accent_hover": "#0056CC",
    "accent_pressed": "#004499",

    # Semantic Colors
    "success": "#34C759",
    "success_muted": "#D4EDDA",
    "warning": "#FF9500",
    "error": "#FF3B30",
    "error_muted": "#F8D7DA",

    # Borders
    "border": "#C6C6C8",
    "border_focused": "#007AFF",
    "separator": "#C6C6C8",
}

# Espacements (grille 8pt)
SPACING = {
    "xs": 4,
    "sm": 8,
    "md": 16,
    "lg": 24,
    "xl": 32,
}

# Rayons des coins
RADIUS = {
    "sm": 6,
    "md": 10,
    "lg": 14,
}


def get_system_font():
    """Retourne la police système appropriée"""
    if platform.system() == "Darwin":
        return "SF Pro Text"
    elif platform.system() == "Windows":
        return "Segoe UI"
    else:
        return "Helvetica Neue"


class PremiumTheme:
    """Configuration complète du thème premium macOS"""

    def __init__(self, style, root, dark_mode=True):
        self.style = style
        self.root = root
        self.colors = COLORS_DARK if dark_mode else COLORS_LIGHT
        self.font_family = get_system_font()
        self.setup_theme()

    def setup_theme(self):
        """Configure tous les styles"""
        self._setup_global()
        self._setup_frames()
        self._setup_labels()
        self._setup_buttons()
        self._setup_entries()
        self._setup_combobox()
        self._setup_progressbar()
        self._setup_notebook()
        self._setup_labelframe()
        self._setup_checkbutton()
        self._setup_radiobutton()
        self._setup_scrollbar()

    def _setup_global(self):
        """Configuration globale"""
        self.style.configure(".",
            font=(self.font_family, 13),
            background=self.colors["bg_primary"],
            foreground=self.colors["text_primary"],
        )
        # Options globales pour les listes déroulantes
        self.root.option_add("*TCombobox*Listbox*Background", self.colors["bg_secondary"])
        self.root.option_add("*TCombobox*Listbox*Foreground", self.colors["text_primary"])
        self.root.option_add("*TCombobox*Listbox*selectBackground", self.colors["accent"])
        self.root.option_add("*TCombobox*Listbox*selectForeground", "#FFFFFF")
        self.root.option_add("*TCombobox*Listbox*Font", (self.font_family, 13))

    def _setup_frames(self):
        """Styles des frames"""
        self.style.configure("TFrame",
            background=self.colors["bg_primary"]
        )
        self.style.configure("Card.TFrame",
            background=self.colors["surface"],
        )
        self.style.configure("Secondary.TFrame",
            background=self.colors["bg_secondary"],
        )

    def _setup_labels(self):
        """Styles des labels"""
        self.style.configure("TLabel",
            background=self.colors["bg_primary"],
            foreground=self.colors["text_primary"],
            font=(self.font_family, 13),
        )
        self.style.configure("Card.TLabel",
            background=self.colors["surface"],
            foreground=self.colors["text_primary"],
        )
        self.style.configure("Title.TLabel",
            font=(self.font_family, 24, "bold"),
            foreground=self.colors["text_primary"],
        )
        self.style.configure("Heading.TLabel",
            font=(self.font_family, 17, "bold"),
            foreground=self.colors["text_primary"],
        )
        self.style.configure("Secondary.TLabel",
            foreground=self.colors["text_secondary"],
        )
        self.style.configure("Caption.TLabel",
            foreground=self.colors["text_tertiary"],
            font=(self.font_family, 11),
        )
        self.style.configure("Success.TLabel",
            foreground=self.colors["success"],
        )

    def _setup_buttons(self):
        """Styles des boutons"""
        # Bouton standard
        self.style.configure("TButton",
            font=(self.font_family, 13),
            padding=(16, 10),
            background=self.colors["bg_tertiary"],
            foreground=self.colors["text_primary"],
            borderwidth=0,
            focuscolor="",
        )
        self.style.map("TButton",
            background=[
                ("active", self.colors["surface_hover"]),
                ("pressed", self.colors["surface_pressed"]),
                ("disabled", self.colors["bg_secondary"]),
            ],
            foreground=[
                ("disabled", self.colors["text_quaternary"]),
            ]
        )

        # Bouton accent (primaire)
        self.style.configure("Accent.TButton",
            font=(self.font_family, 13),
            padding=(16, 10),
            background=self.colors["accent"],
            foreground="#FFFFFF",
            borderwidth=0,
        )
        self.style.map("Accent.TButton",
            background=[
                ("active", self.colors["accent_hover"]),
                ("pressed", self.colors["accent_pressed"]),
                ("disabled", self.colors["bg_tertiary"]),
            ]
        )

        # Bouton succès
        self.style.configure("Success.TButton",
            font=(self.font_family, 13),
            padding=(16, 10),
            background=self.colors["success"],
            foreground="#FFFFFF",
            borderwidth=0,
        )
        self.style.map("Success.TButton",
            background=[
                ("active", "#3DDB63"),
                ("pressed", "#28B84C"),
            ]
        )

        # Bouton danger
        self.style.configure("Danger.TButton",
            font=(self.font_family, 13),
            padding=(16, 10),
            background=self.colors["error"],
            foreground="#FFFFFF",
            borderwidth=0,
        )
        self.style.map("Danger.TButton",
            background=[
                ("active", "#FF6961"),
                ("pressed", "#E63B30"),
            ]
        )

        # Bouton outline danger
        self.style.configure("DangerOutline.TButton",
            font=(self.font_family, 13),
            padding=(16, 10),
            background=self.colors["bg_primary"],
            foreground=self.colors["error"],
            borderwidth=1,
        )

        # Bouton ghost (minimal)
        self.style.configure("Ghost.TButton",
            font=(self.font_family, 13),
            padding=(8, 8),
            background=self.colors["bg_primary"],
            foreground=self.colors["text_secondary"],
            borderwidth=0,
        )
        self.style.map("Ghost.TButton",
            background=[
                ("active", self.colors["bg_tertiary"]),
            ]
        )

        # Bouton icon (pour les petits boutons emoji)
        self.style.configure("Icon.TButton",
            font=(self.font_family, 14),
            padding=(6, 4),
            background=self.colors["bg_primary"],
            foreground=self.colors["text_secondary"],
            borderwidth=0,
            width=3,
        )
        self.style.map("Icon.TButton",
            background=[
                ("active", self.colors["bg_tertiary"]),
            ]
        )

    def _setup_entries(self):
        """Styles des champs de saisie"""
        self.style.configure("TEntry",
            font=(self.font_family, 13),
            padding=(12, 10),
            fieldbackground=self.colors["bg_tertiary"],
            foreground=self.colors["text_primary"],
            insertcolor=self.colors["accent"],
            insertwidth=2,
            borderwidth=1,
        )
        self.style.map("TEntry",
            fieldbackground=[
                ("focus", self.colors["bg_secondary"]),
                ("disabled", self.colors["bg_secondary"]),
            ],
            foreground=[
                ("disabled", self.colors["text_quaternary"]),
            ]
        )

    def _setup_combobox(self):
        """Styles des combobox"""
        self.style.configure("TCombobox",
            font=(self.font_family, 13),
            padding=(12, 10),
            background=self.colors["bg_tertiary"],
            fieldbackground=self.colors["bg_tertiary"],
            foreground=self.colors["text_primary"],
            arrowcolor=self.colors["text_secondary"],
            borderwidth=1,
        )
        self.style.map("TCombobox",
            fieldbackground=[
                ("readonly", self.colors["bg_tertiary"]),
                ("disabled", self.colors["bg_secondary"]),
            ],
            foreground=[
                ("disabled", self.colors["text_quaternary"]),
            ]
        )

    def _setup_progressbar(self):
        """Styles des barres de progression"""
        # Progress bar standard (fine, style macOS)
        self.style.configure("TProgressbar",
            thickness=6,
            troughcolor=self.colors["bg_tertiary"],
            background=self.colors["accent"],
            borderwidth=0,
            troughrelief="flat",
        )

        # Progress bar téléchargement
        self.style.configure("Download.Horizontal.TProgressbar",
            thickness=8,
            troughcolor=self.colors["bg_tertiary"],
            background=self.colors["accent"],
            borderwidth=0,
        )

        # Progress bar succès
        self.style.configure("Success.Horizontal.TProgressbar",
            thickness=8,
            troughcolor=self.colors["bg_tertiary"],
            background=self.colors["success"],
            borderwidth=0,
        )

        # Progress bar indéterminée (analyse)
        self.style.configure("Analyze.Horizontal.TProgressbar",
            thickness=4,
            troughcolor=self.colors["bg_tertiary"],
            background=self.colors["accent"],
            borderwidth=0,
        )

    def _setup_notebook(self):
        """Styles du notebook (onglets)"""
        self.style.configure("TNotebook",
            background=self.colors["bg_primary"],
            borderwidth=0,
            padding=0,
        )
        self.style.configure("TNotebook.Tab",
            font=(self.font_family, 13),
            padding=(20, 12),
            background=self.colors["bg_secondary"],
            foreground=self.colors["text_secondary"],
        )
        self.style.map("TNotebook.Tab",
            background=[
                ("selected", self.colors["bg_primary"]),
            ],
            foreground=[
                ("selected", self.colors["text_primary"]),
            ],
        )

    def _setup_labelframe(self):
        """Styles des labelframes"""
        self.style.configure("TLabelframe",
            background=self.colors["bg_secondary"],
            borderwidth=0,
            relief="flat",
            padding=16,
        )
        self.style.configure("TLabelframe.Label",
            font=(self.font_family, 12, "bold"),
            foreground=self.colors["text_secondary"],
            background=self.colors["bg_secondary"],
        )

    def _setup_checkbutton(self):
        """Styles des checkbuttons"""
        self.style.configure("TCheckbutton",
            font=(self.font_family, 13),
            background=self.colors["bg_primary"],
            foreground=self.colors["text_primary"],
        )
        self.style.map("TCheckbutton",
            background=[
                ("active", self.colors["bg_primary"]),
            ]
        )

    def _setup_radiobutton(self):
        """Styles des radiobuttons"""
        self.style.configure("TRadiobutton",
            font=(self.font_family, 13),
            background=self.colors["bg_primary"],
            foreground=self.colors["text_primary"],
        )
        self.style.map("TRadiobutton",
            background=[
                ("active", self.colors["bg_primary"]),
            ]
        )

    def _setup_scrollbar(self):
        """Styles des scrollbars"""
        self.style.configure("TScrollbar",
            background=self.colors["bg_primary"],
            troughcolor=self.colors["bg_primary"],
            arrowcolor=self.colors["text_tertiary"],
            borderwidth=0,
        )
        self.style.map("TScrollbar",
            background=[
                ("active", self.colors["bg_tertiary"]),
            ]
        )
