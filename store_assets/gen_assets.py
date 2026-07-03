"""Generate Eat Truck Love store assets: 512x512 app icon + 1024x500 feature graphic.
Recreates the ETL circular logo (red circle, black tilted E/T/L box, EAT TRUCK LOVE, BY AZIMUTH).
"""
import os
from PIL import Image, ImageDraw, ImageFont

OUT = os.path.dirname(os.path.abspath(__file__))
FONT_PATH = "/usr/share/fonts/google-noto-vf/NotoSans[wght].ttf"

RED = (193, 39, 45)
BLACK = (26, 26, 26)
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


def draw_letter_spaced(draw, x, y, s, fnt, fill, spacing):
    """Draw text left-anchored at (x, y-top) with extra spacing between chars."""
    cx = x
    for ch in s:
        w, h, ox, oy = text_wh(draw, ch, fnt)
        draw.text((cx - ox, y - oy), ch, font=fnt, fill=fill)
        cx += w + spacing
    return cx


def build_logo(S):
    """Build the circular ETL logo composition on a transparent SxS canvas."""
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # --- red circle ---
    m = int(S * 0.03)
    d.ellipse([m, m, S - m, S - m], fill=RED)

    cx = S // 2
    # ---- big right-side text: AT / RUCK / OVE (white heavy) ----
    big = font(int(S * 0.135), 900)
    # vertical positions (centers) for the three rows
    rows_y = [int(S * 0.375), int(S * 0.515), int(S * 0.655)]
    right_texts = ["AT", "RUCK", "OVE"]
    text_left = int(S * 0.375)  # where the right text starts (just right of the box)
    for ty, s in zip(rows_y, right_texts):
        w, h, ox, oy = text_wh(d, s, big)
        d.text((text_left - ox, ty - h / 2 - oy), s, font=big, fill=OFFWHITE)

    # ---- black tilted box with E/T/L ----
    boxW, boxH = int(S * 0.17), int(S * 0.48)
    box = Image.new("RGBA", (boxW, boxH), (0, 0, 0, 0))
    bd = ImageDraw.Draw(box)
    border = max(3, int(S * 0.010))
    rad = int(S * 0.012)
    bd.rounded_rectangle([0, 0, boxW - 1, boxH - 1], radius=rad, fill=WHITE)
    bd.rounded_rectangle([border, border, boxW - 1 - border, boxH - 1 - border],
                         radius=rad, fill=BLACK)
    letters = ["E", "T", "L"]
    lf = font(int(S * 0.115), 900)
    ly = [boxH * 0.19, boxH * 0.47, boxH * 0.75]
    for yy, ch in zip(ly, letters):
        w, h, ox, oy = text_wh(bd, ch, lf)
        bd.text((boxW / 2 - w / 2 - ox, yy - h / 2 - oy), ch, font=lf, fill=OFFWHITE)
    box = box.rotate(-6, expand=True, resample=Image.BICUBIC)
    # place box so its letters align with the rows; box left edge ~ 0.205*S
    bx = int(S * 0.205)
    by = int(S * 0.275)
    img.alpha_composite(box, (bx, by))

    # ---- BY AZIMUTH ----
    az = font(int(S * 0.050), 800)
    sp = int(S * 0.011)
    aw = 0
    for ch in "BY AZIMUTH":
        w, h, ox, oy = text_wh(d, ch, az)
        aw += w + sp
    ax = cx - aw / 2 + int(S * 0.02)
    draw_letter_spaced(d, ax, int(S * 0.815), "BY AZIMUTH", az, BLACK, sp)
    return img


def fit_font(draw, s, max_w, start_size, weight=900):
    size = start_size
    while size > 10:
        f = font(size, weight)
        w, _, _, _ = text_wh(draw, s, f)
        if w <= max_w:
            return f
        size -= 4
    return font(size, weight)


# ============ 1) APP ICON 512x512 (white background, opaque) ============
SS = 2048
logo = build_logo(SS)
icon = Image.new("RGBA", (SS, SS), WHITE + (255,))
# scale logo to ~96% and center
icon.alpha_composite(logo, (0, 0))
icon = icon.convert("RGB").resize((512, 512), Image.LANCZOS)
icon.save(os.path.join(OUT, "app_icon_512.png"))

# high-res master for flutter_launcher_icons (1024 on white)
master = Image.new("RGBA", (SS, SS), WHITE + (255,))
master.alpha_composite(logo, (0, 0))
master.convert("RGB").resize((1024, 1024), Image.LANCZOS).save(os.path.join(OUT, "app_icon_1024.png"))

# adaptive foreground: logo art centered in middle ~66%, transparent bg
fg = Image.new("RGBA", (SS, SS), (0, 0, 0, 0))
small = logo.resize((int(SS * 0.72), int(SS * 0.72)), Image.LANCZOS)
fg.alpha_composite(small, ((SS - small.width) // 2, (SS - small.height) // 2))
fg.resize((1024, 1024), Image.LANCZOS).save(os.path.join(OUT, "app_icon_foreground.png"))

print("icon done")


# ============ 2) FEATURE GRAPHIC 1024x500 ============
FW, FH = 2048, 1000
fg_img = Image.new("RGB", (FW, FH), RED)
fd = ImageDraw.Draw(fg_img, "RGBA")
# vertical gradient red -> deep red
top = (206, 47, 53)
bot = (150, 22, 27)
for y in range(FH):
    t = y / FH
    r = int(top[0] + (bot[0] - top[0]) * t)
    g = int(top[1] + (bot[1] - top[1]) * t)
    b = int(top[2] + (bot[2] - top[2]) * t)
    fd.line([(0, y), (FW, y)], fill=(r, g, b))
# decorative translucent circles
fd.ellipse([FW - 520, -260, FW + 120, 380], fill=(255, 255, 255, 18))
fd.ellipse([-200, FH - 320, 360, FH + 240], fill=(0, 0, 0, 30))

# left: logo on a white circle "badge"
badge = int(FH * 0.82)
bx = int(FW * 0.045)
by = (FH - badge) // 2
fd.ellipse([bx - 12, by - 12, bx + badge + 12, by + badge + 12], fill=(255, 255, 255, 40))
logo_small = build_logo(1600).resize((badge, badge), Image.LANCZOS)
# put logo (its own red circle) directly
white_disc = Image.new("RGBA", (badge, badge), (0, 0, 0, 0))
wd = ImageDraw.Draw(white_disc)
wd.ellipse([0, 0, badge - 1, badge - 1], fill=WHITE + (255,))
white_disc.alpha_composite(logo_small)
fg_img.paste(white_disc, (bx, by), white_disc)

# right: title + tagline + pills
tx = int(FW * 0.47)
right_margin = int(FW * 0.035)
avail = FW - tx - right_margin
title = fit_font(fd, "Eat Truck Love", avail, int(FH * 0.145), 900)
tw, th, tox, toy = text_wh(fd, "Eat Truck Love", title)
fd.text((tx, int(FH * 0.22) - toy), "Eat Truck Love", font=title, fill=OFFWHITE)
sub = fit_font(fd, "Run your food court, effortlessly", avail, int(FH * 0.058), 600)
fd.text((tx, int(FH * 0.44)), "Run your food court, effortlessly", font=sub, fill=(255, 232, 232))

# feature pills
pill_font = font(int(FH * 0.046), 700)
pills = ["Attendance", "Sales", "Housekeeping", "Maintenance"]
px = tx
py = int(FH * 0.63)
for p in pills:
    w, h, ox, oy = text_wh(fd, p, pill_font)
    padx, pady = int(FH * 0.03), int(FH * 0.022)
    if px + w + 2 * padx > FW - 40:
        px = tx
        py += h + 2 * pady + int(FH * 0.03)
    fd.rounded_rectangle([px, py, px + w + 2 * padx, py + h + 2 * pady],
                         radius=int(FH * 0.06), fill=(255, 255, 255, 38))
    fd.text((px + padx - ox, py + pady - oy), p, font=pill_font, fill=OFFWHITE)
    px += w + 2 * padx + int(FH * 0.028)

fg_img.resize((1024, 500), Image.LANCZOS).save(os.path.join(OUT, "feature_graphic_1024x500.png"))
print("feature graphic done")
