"""Compose app-icon options (A-D, B2) from AI art + real game card assets.

Usage: python3 tools/compose_icon_options.py DIR  (expects DIR/images/1.jpg)
The shipped icon is B2: real zelen dolnik card over the game card back on felt.
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageChops, ImageEnhance, ImageOps

REPO = Path("/home/user/faraon-farar")
S = Path(sys.argv[1])
OUT = Path(__file__).parent / "options"
OUT.mkdir(exist_ok=True)
N = 2048  # supersampled canvas

art = Image.open(S / "images/1.jpg").convert("RGB")  # 2000x2000, baked white rounded corners
back = Image.open(REPO / "assets/cards/back.png").convert("RGBA")
dolnik = Image.open(REPO / "assets/cards/zelen/dolnik.png").convert("RGBA")


# ---------- 1. clean the art: remove baked rounded corners / white margin ----------
def clean_art(im):
    w, h = im.size
    # white-ish pixels flood-filled from the 4 corners = outside of baked squircle
    m = Image.new("L", im.size, 0)
    g = im.convert("L")
    seed = im.copy()
    for c in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
        ImageDraw.floodfill(seed, c, (255, 0, 255), thresh=60)
    r, gg, b = seed.split()
    m = ImageChops.multiply(r.point(lambda v: 255 if v == 255 else 0),
                            b.point(lambda v: 255 if v == 255 else 0))
    m = ImageChops.multiply(m, gg.point(lambda v: 255 if v == 0 else 0))
    m = m.filter(ImageFilter.MaxFilter(15)).filter(ImageFilter.GaussianBlur(6))
    # fill: progressively blurred copy with masked area replaced by felt colour
    felt = Image.new("RGB", im.size, (8, 70, 40))
    base = Image.composite(felt, im, m)
    fill = base
    for rad in (40, 80, 120):
        fill = Image.composite(base.filter(ImageFilter.GaussianBlur(rad)), fill, m)
    # add felt grain back so the filled corners are not flat
    noise = Image.effect_noise(im.size, 18).convert("RGB")
    grain = ImageChops.add(fill, noise, scale=2.0, offset=-60)
    fill = Image.composite(grain, fill, m.point(lambda v: v // 3))
    return Image.composite(fill, im, m)


clean = art.crop((110, 110, 1890, 1890)).resize((N, N), Image.LANCZOS)


def vignette(im, strength=0.55):
    v = Image.new("L", im.size, 0)
    d = ImageDraw.Draw(v)
    w = im.size[0]
    d.ellipse((-w * 0.25, -w * 0.25, w * 1.25, w * 1.25), fill=255)
    v = v.filter(ImageFilter.GaussianBlur(w * 0.12))
    dark = ImageEnhance.Brightness(im).enhance(1 - strength)
    return Image.composite(im, dark, v)


def rounded_mask(size, r, ss=4):
    w, h = size
    m = Image.new("L", (w * ss, h * ss), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w * ss - 1, h * ss - 1), radius=r * ss, fill=255)
    return m.resize((w, h), Image.LANCZOS)


# authentic leaf pip from the real card scan (zelen dolnik, left pip)
pip = dolnik.crop((104, 343, 252, 530))
pg = pip.convert("RGB")
pip_alpha = ImageOps.invert(pg.convert("L").point(lambda v: 0 if v > 225 else 255).filter(ImageFilter.MinFilter(3)))
pip_alpha = ImageOps.invert(pip_alpha).filter(ImageFilter.GaussianBlur(0.8))
pip.putalpha(pip_alpha)
pip = pip.crop(pip.getbbox())


def make_card(width, art_box, pips=True):
    """White playing card with rounded corners, thin frame, art window, leaf pips."""
    h = int(width * 1.5)
    r = int(width * 0.075)
    card = Image.new("RGBA", (width, h), (252, 250, 244, 255))
    d = ImageDraw.Draw(card)
    inset = int(width * 0.055)
    frame = (inset, inset, width - inset, h - inset)
    # art window
    win = (frame[2] - frame[0], frame[3] - frame[1])
    a = clean.crop(art_box)
    a = ImageOps.fit(a, win, Image.LANCZOS, centering=(0.5, 0.0))
    card.paste(a, frame[:2], rounded_mask(win, int(width * 0.04)))
    d.rounded_rectangle(frame, radius=int(width * 0.04), outline=(30, 34, 40, 255), width=max(3, width // 120))
    if pips:
        ps = int(width * 0.2)
        p = pip.resize((ps, int(ps * pip.size[1] / pip.size[0])), Image.LANCZOS)
        # small white plate so the pip reads on top of the art
        pad = int(ps * 0.12)
        plate = Image.new("RGBA", (p.size[0] + 2 * pad, p.size[1] + 2 * pad), (0, 0, 0, 0))
        ImageDraw.Draw(plate).rounded_rectangle((0, 0, plate.size[0] - 1, plate.size[1] - 1),
                                                radius=pad * 2, fill=(252, 250, 244, 235))
        plate.alpha_composite(p, (pad, pad))
        off = inset + int(width * 0.03)
        card.alpha_composite(plate, (off, off))
        pr = plate.rotate(180)
        card.alpha_composite(pr, (width - off - pr.size[0], h - off - pr.size[1]))
    card.putalpha(ImageChops.multiply(card.getchannel("A"), rounded_mask(card.size, r)))
    return card


def back_card(width):
    h = int(width * 1.5)
    b = back.resize((width, h), Image.LANCZOS)
    b.putalpha(rounded_mask(b.size, int(width * 0.075)))
    return b


def shadowed(layer, blur, offset, opacity=150):
    sh = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    a = layer.getchannel("A").point(lambda v: v * opacity // 255)
    sh.putalpha(a)
    pad = blur * 3
    big = Image.new("RGBA", (layer.size[0] + 2 * pad, layer.size[1] + 2 * pad), (0, 0, 0, 0))
    big.alpha_composite(sh, (pad + offset[0], pad + offset[1]))
    big = big.filter(ImageFilter.GaussianBlur(blur))
    big.alpha_composite(layer, (pad, pad))
    return big


def place(canvas, layer, center, angle=0):
    l = layer.rotate(angle, resample=Image.BICUBIC, expand=True)
    canvas.alpha_composite(l, (int(center[0] - l.size[0] / 2), int(center[1] - l.size[1] / 2)))


def felt_bg(glow=(255, 205, 90), base=None):
    grad = Image.linear_gradient("L").resize((N, N))
    bg = Image.composite(Image.new("RGB", (N, N), (5, 52, 30)), Image.new("RGB", (N, N), (16, 104, 60)), grad)
    noise = Image.effect_noise((N, N), 30).convert("RGB").filter(ImageFilter.GaussianBlur(1.2))
    bg = Image.blend(bg, noise, 0.07).convert("RGBA")
    g = Image.new("L", (N, N), 0)
    ImageDraw.Draw(g).ellipse((N * 0.2, N * 0.15, N * 0.8, N * 0.75), fill=110)
    g = g.filter(ImageFilter.GaussianBlur(N * 0.12))
    glow_l = Image.new("RGBA", (N, N), glow + (0,))
    glow_l.putalpha(g)
    bg.alpha_composite(glow_l)
    return vignette(bg.convert("RGB"), 0.45).convert("RGBA")


def emit(name, master_rgba, fg_rgba=None, bg_rgba=None):
    if bg_rgba is not None:
        bg_rgba.convert("RGB").resize((1024, 1024), Image.LANCZOS).save(OUT / f"{name}_bg.png")
    master_rgba.convert("RGB").resize((1024, 1024), Image.LANCZOS).save(OUT / f"{name}.png")
    if fg_rgba is not None:
        fg_rgba.resize((1024, 1024), Image.LANCZOS).save(OUT / f"{name}_fg.png")


BUST = (330, 70, 1830, 2000)   # bust area in clean art (2048 space after resize)
BUST = tuple(int(v * N / 2000) for v in BUST)

# ---------- A: improved original (full-bleed, no baked corners, graded) ----------
A = ImageEnhance.Contrast(clean).enhance(1.06)
A = ImageEnhance.Color(A).enhance(1.05)
A = vignette(A, 0.35).convert("RGBA")
emit("A_vylepseny_original", A)

# ---------- B: card on the table, fan with the game's own card back ----------
bg = felt_bg()
fg = Image.new("RGBA", (N, N), (0, 0, 0, 0))
cw = int(N * 0.47)
place(fg, shadowed(back_card(cw), 30, (0, 24)), (N * 0.62, N * 0.52), -14)
place(fg, shadowed(make_card(cw, BUST), 34, (0, 30), 170), (N * 0.43, N * 0.50), 8)
B = bg.copy(); B.alpha_composite(fg)
emit("B_karta_na_stole", B, fg, bg)

# ---------- C: single card, clean iOS style ----------
bg = Image.new("RGBA", (N, N))
top, bot = (22, 120, 72), (4, 44, 26)
grad = Image.linear_gradient("L").resize((N, N))
bg = Image.composite(Image.new("RGB", (N, N), bot), Image.new("RGB", (N, N), top), grad).convert("RGBA")
hl = Image.new("L", (N, N), 0)
ImageDraw.Draw(hl).ellipse((N * 0.1, -N * 0.35, N * 0.9, N * 0.45), fill=60)
hl = hl.filter(ImageFilter.GaussianBlur(N * 0.08))
white = Image.new("RGBA", (N, N), (255, 255, 255, 0)); white.putalpha(hl)
bg.alpha_composite(white)
fg = Image.new("RGBA", (N, N), (0, 0, 0, 0))
place(fg, shadowed(make_card(int(N * 0.52), BUST), 40, (0, 40), 190), (N * 0.5, N * 0.51), -6)
C = bg.copy(); C.alpha_composite(fg)
emit("C_ios_jedna_karta", C, fg, bg)

# ---------- D: fan of three (back, back, front) on warm gold ----------
gtop, gbot = (250, 214, 120), (196, 128, 36)
bg = Image.composite(Image.new("RGB", (N, N), gbot), Image.new("RGB", (N, N), gtop), grad).convert("RGBA")
fg = Image.new("RGBA", (N, N), (0, 0, 0, 0))
cw = int(N * 0.42)
pivot_y = N * 0.56
for ang, dx in ((22, -0.2), (11, -0.1)):
    place(fg, shadowed(back_card(cw), 24, (0, 18), 120), (N * (0.5 + dx), pivot_y), ang)
place(fg, shadowed(make_card(cw, BUST), 30, (0, 26), 160), (N * 0.56, pivot_y - N * 0.02), -4)
D = bg.copy(); D.alpha_composite(fg)
emit("D_vejar_zlata", D, fg, bg)
print("done")


# ---------- B2: card on the table with the REAL zelen dolnik card ----------
def real_card(width):
    face = dolnik.crop((58, 25, 682, 1059)).convert("RGB")   # inner frame + 4 px
    m = 40
    card = Image.new("RGBA", (face.size[0] + 2 * m, face.size[1] + 2 * m), (255, 255, 255, 255))
    card.paste(face, (m, m))
    h = int(card.size[1] * width / card.size[0])
    card = card.resize((width, h), Image.LANCZOS)
    card.putalpha(rounded_mask(card.size, int(width * 0.075)))
    # hairline edge so the white card reads on light backgrounds too
    edge = Image.new("RGBA", card.size, (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle((1, 1, card.size[0] - 2, card.size[1] - 2),
                                           radius=int(width * 0.075), outline=(0, 0, 0, 40), width=3)
    card.alpha_composite(edge)
    return card


bg = felt_bg()
fg = Image.new("RGBA", (N, N), (0, 0, 0, 0))
cw = int(N * 0.47)
place(fg, shadowed(back_card(cw), 30, (0, 24)), (N * 0.62, N * 0.52), -14)
place(fg, shadowed(real_card(cw), 34, (0, 30), 170), (N * 0.43, N * 0.50), 8)
B2 = bg.copy(); B2.alpha_composite(fg)
emit("B2_realna_karta", B2, fg, bg)
print("B2 done")
