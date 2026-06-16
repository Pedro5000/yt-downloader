#!/usr/bin/env python3
"""Génère l'icône macOS de ViDL : squircle dégradé violet→rose + play stylisé."""
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
MARGIN = 100
SQ = SIZE - 2 * MARGIN          # 824
RADIUS = 186                    # ~22.5% (gabarit macOS)

C1 = (140, 82, 246)             # violet
C2 = (237, 71, 153)            # rose

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

# --- Dégradé diagonal ---
grad = Image.new("RGB", (SIZE, SIZE), C1)
gdraw = ImageDraw.Draw(grad)
maxd = 2 * (SIZE - 1)
for d in range(0, 2 * SIZE - 1):
    t = d / maxd
    gdraw.line([(d, 0), (0, d)], fill=lerp(C1, C2, t))

# --- Masque squircle ---
mask = Image.new("L", (SIZE, SIZE), 0)
mdraw = ImageDraw.Draw(mask)
mdraw.rounded_rectangle([MARGIN, MARGIN, MARGIN + SQ, MARGIN + SQ], radius=RADIUS, fill=255)

icon = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
icon.paste(grad, (0, 0), mask)

# --- Reflet haut (highlight) ---
hi = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
hdraw = ImageDraw.Draw(hi)
for y in range(MARGIN, MARGIN + SQ):
    p = (y - MARGIN) / SQ
    alpha = int(60 * max(0, 1 - p * 2.2))
    hdraw.line([(MARGIN, y), (MARGIN + SQ, y)], fill=(255, 255, 255, alpha))
hi.putalpha(Image.composite(hi.getchannel("A"), Image.new("L", (SIZE, SIZE), 0), mask))
icon = Image.alpha_composite(icon, hi)

# --- Play : ombre douce + triangle "stack" ---
cx, cy = SIZE // 2, SIZE // 2
w = int(SQ * 0.30)
h = int(w * 1.15)

def triangle(offx, offy):
    return [
        (cx - w // 2 + offx, cy - h // 2 + offy),
        (cx - w // 2 + offx, cy + h // 2 + offy),
        (cx + w // 2 + offx + int(w * 0.05), cy + offy),
    ]

# Ombre portée
shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
sdraw = ImageDraw.Draw(shadow)
sdraw.polygon([(x, y + 16) for (x, y) in triangle(0, 0)], fill=(0, 0, 0, 90))
shadow = shadow.filter(ImageFilter.GaussianBlur(18))
icon = Image.alpha_composite(icon, shadow)

play = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
pdraw = ImageDraw.Draw(play)
pdraw.polygon(triangle(-26, -26), fill=(255, 255, 255, 70))   # couche arrière (effet stack)
pdraw.polygon(triangle(8, 8), fill=(255, 255, 255, 255))      # play principal
icon = Image.alpha_composite(icon, play)

icon.save("/tmp/vidl_icon_1024.png")
print("ok")
