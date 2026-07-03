"""Generate Eat Truck Love store + launcher assets from the ORIGINAL logo.
original_logo.png has a WHITE (opaque) background, so we detect the red circle,
crop tightly, and build a clean circular version for compositing.
"""
import os
from PIL import Image, ImageDraw, ImageFont, ImageChops

OUT = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(OUT)
FONT_PATH = "/usr/share/fonts/google-noto-vf/NotoSans[wght].ttf"
RED = (193, 39, 45)
WHITE = (255, 255, 255)
OFFWHITE = (253, 253, 250)


def font(size, weight=900):
    f = ImageFont.truetype(FONT_PATH, size)
    try:
        f.set_variation_by_axes([weight])
    except Exception:
        pass
    return f


def text_wh(draw, s, fnt):
    b = draw.textbbox((0, 0), s, font=fnt)
    return b[2] - b[0], b[3] - b[1], b[0], b[1]


def fit_font(draw, s, max_w, start_size, weight=900):
    size = start_size
    while size > 10:
        f = font(size, weight)
        w, _, _, _ = text_wh(draw, s, f)
        if w <= max_w:
            return f
        size -= 4
    return font(size, weight)


# ---- load logo (white bg) and crop tightly to the red circle ----
im = Image.open(os.path.join(OUT, "original_logo.png")).convert("RGB")
diff = ImageChops.difference(im, Image.new("RGB", im.size, WHITE))
bbox = diff.getbbox()                       # bounds of all non-white content = the circle
crop = im.crop(bbox)
w, h = crop.size
side = max(w, h)
# square with white bg, circle centered
sq_white = Image.new("RGB", (side, side), WHITE)
sq_white.paste(crop, ((side - w) // 2, (side - h) // 2))
# circular version: transparent outside the circle
sq_rgba = sq_white.convert("RGBA")
mask = Image.new("L", (side, side), 0)
ImageDraw.Draw(mask).ellipse([0, 0, side - 1, side - 1], fill=255)
circle_img = sq_rgba.copy()
circle_img.putalpha(mask)


# ============ 1) APP ICON 512x512 (white bg, opaque) ============
S = 1024
margin = int(S * 0.06)
inner = S - 2 * margin
icon = Image.new("RGB", (S, S), WHITE)
icon.paste(sq_white.resize((inner, inner), Image.LANCZOS), (margin, margin))
icon.resize((512, 512), Image.LANCZOS).save(os.path.join(OUT, "app_icon_512.png"))
icon.save(os.path.join(OUT, "app_icon_1024.png"))
icon.save(os.path.join(REPO, "etl_manager_app/assets/icon/app_icon.png"))

# adaptive foreground: just the red circle (transparent outside), centered
fg = Image.new("RGBA", (S, S), (0, 0, 0, 0))
scale = 0.86
a = circle_img.resize((int(S * scale), int(S * scale)), Image.LANCZOS)
fg.alpha_composite(a, ((S - a.width) // 2, (S - a.height) // 2))
fg.save(os.path.join(OUT, "app_icon_foreground.png"))
fg.save(os.path.join(REPO, "etl_manager_app/assets/icon/app_icon_foreground.png"))
print("icon done")


# ============ 2) FEATURE GRAPHIC 1024x500 (clean white panel + red side) ============
FW, FH = 2048, 1000
img = Image.new("RGB", (FW, FH), RED)
d = ImageDraw.Draw(img, "RGBA")
# red gradient background
top, bot = (206, 47, 53), (150, 22, 27)
for y in range(FH):
    t = y / FH
    d.line([(0, y), (FW, y)], fill=(
        int(top[0] + (bot[0] - top[0]) * t),
        int(top[1] + (bot[1] - top[1]) * t),
        int(top[2] + (bot[2] - top[2]) * t)))
d.ellipse([FW - 560, -280, FW + 140, 420], fill=(255, 255, 255, 16))

# left white panel (full height)
panel_w = int(FW * 0.40)
d.rectangle([0, 0, panel_w, FH], fill=WHITE)
# soft shadow at the panel edge
for i in range(40):
    d.line([(panel_w + i, 0), (panel_w + i, FH)], fill=(0, 0, 0, max(0, 24 - i)))
# logo centered in the white panel (blends with white bg)
logo_sz = int(FH * 0.74)
lx = panel_w // 2 - logo_sz // 2
ly = FH // 2 - logo_sz // 2
img.paste(sq_white.resize((logo_sz, logo_sz), Image.LANCZOS), (lx, ly))

# right: title + tagline + pills
tx = panel_w + int(FW * 0.045)
avail = FW - tx - int(FW * 0.04)
title = fit_font(d, "Eat Truck Love", avail, int(FH * 0.15), 900)
_, _, _, toy = text_wh(d, "Eat Truck Love", title)
d.text((tx, int(FH * 0.21) - toy), "Eat Truck Love", font=title, fill=OFFWHITE)
sub = fit_font(d, "Run your food court, effortlessly", avail, int(FH * 0.06), 600)
d.text((tx, int(FH * 0.43)), "Run your food court, effortlessly", font=sub, fill=(255, 230, 230))

pill_font = font(int(FH * 0.047), 700)
px, py = tx, int(FH * 0.62)
for p in ["Attendance", "Sales", "Housekeeping", "Maintenance"]:
    w2, h2, ox, oy = text_wh(d, p, pill_font)
    padx, pady = int(FH * 0.032), int(FH * 0.024)
    if px + w2 + 2 * padx > FW - 40:
        px = tx
        py += h2 + 2 * pady + int(FH * 0.03)
    d.rounded_rectangle([px, py, px + w2 + 2 * padx, py + h2 + 2 * pady],
                        radius=int(FH * 0.065), fill=(255, 255, 255, 45))
    d.text((px + padx - ox, py + pady - oy), p, font=pill_font, fill=OFFWHITE)
    px += w2 + 2 * padx + int(FH * 0.03)

img.resize((1024, 500), Image.LANCZOS).save(os.path.join(OUT, "feature_graphic_1024x500.png"))
print("feature graphic done")
