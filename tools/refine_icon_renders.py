"""Refine the user's WaveSpeed card renders into app-icon masters (+ Android fg/bg)."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageChops, ImageEnhance

B = Path("/tmp/claude-0/-home-user-faraon-farar/9a26ed85-e155-5efe-8341-2be0b70a7ab5")
IMG = B / "images"
OUT = B / "scratchpad/refined"
OUT.mkdir(exist_ok=True)
N = 2048


def card_mask(im):
    """Background = greenish or dark pixels connected to the border; card = the rest."""
    w, h = im.size
    r, g, b = [c.point(lambda v: v) for c in im.split()]
    px = im.load()
    bgmap = Image.new("L", im.size, 0)
    bp = bgmap.load()
    for y in range(h):
        for x in range(w):
            R, G, Bb = px[x, y]
            if (G - max(R, Bb) > 12) or (R + G + Bb < 150):
                bp[x, y] = 255
    for c in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1), (w // 2, 0), (w // 2, h - 1), (0, h // 2), (w - 1, h // 2)]:
        if bp[c] == 255:
            ImageDraw.floodfill(bgmap, c, 128)
    m = bgmap.point(lambda v: 0 if v == 128 else 255)
    # clean: close small gaps, then slight erode + feather for a crisp anti-aliased edge
    m = m.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))
    m = m.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(1.0))
    return m


def extract(im):
    im = im.convert("RGB")
    m = card_mask(im)
    card = im.convert("RGBA")
    card.putalpha(m)
    return card.crop(m.getbbox())


def felt(top=(30, 150, 80), bottom=(3, 48, 24), spot=0.5):
    grad = Image.linear_gradient("L").resize((N, N))
    bg = Image.composite(Image.new("RGB", (N, N), bottom), Image.new("RGB", (N, N), top), grad)
    # soft spotlight from above
    s = Image.new("L", (N, N), 0)
    ImageDraw.Draw(s).ellipse((N * 0.05, -N * 0.45, N * 0.95, N * 0.55), fill=int(90 * spot))
    s = s.filter(ImageFilter.GaussianBlur(N * 0.1))
    bg = Image.composite(Image.new("RGB", (N, N), (120, 220, 150)), bg, s)
    # vignette
    v = Image.new("L", (N, N), 0)
    ImageDraw.Draw(v).ellipse((-N * 0.3, -N * 0.3, N * 1.3, N * 1.3), fill=255)
    v = v.filter(ImageFilter.GaussianBlur(N * 0.12))
    bg = Image.composite(bg, ImageEnhance.Brightness(bg).enhance(0.55), v)
    noise = Image.effect_noise((N, N), 40).convert("RGB")
    return Image.blend(bg, noise, 0.04).convert("RGBA")


def shadow_of(layer, blur, offset, opacity):
    sh = Image.new("RGBA", layer.size, (0, 10, 4, 0))
    sh.putalpha(layer.getchannel("A").point(lambda v: v * opacity // 255))
    pad = blur * 3
    big = Image.new("RGBA", (layer.size[0] + 2 * pad, layer.size[1] + 2 * pad), (0, 0, 0, 0))
    big.alpha_composite(sh, (pad + offset[0], pad + offset[1]))
    return big.filter(ImageFilter.GaussianBlur(blur)), pad


def compose(card, height_frac, center=(0.5, 0.5), shadow=(50, (0, 50), 170)):
    scale = N * height_frac / card.size[1]
    c = card.resize((round(card.size[0] * scale), round(card.size[1] * scale)), Image.LANCZOS)
    fg = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    sh, pad = shadow_of(c, *shadow)
    x = round(N * center[0] - c.size[0] / 2)
    y = round(N * center[1] - c.size[1] / 2)
    fg.alpha_composite(sh, (x - pad, y - pad)) if x - pad >= 0 and y - pad >= 0 else None
    if x - pad < 0 or y - pad < 0:
        tmp = Image.new("RGBA", (N + 4 * pad, N + 4 * pad), (0, 0, 0, 0))
        tmp.alpha_composite(sh, (x + pad, y + pad))
        fg.alpha_composite(tmp.crop((2 * pad, 2 * pad, 2 * pad + N, 2 * pad + N)))
    fg.alpha_composite(c, (x, y))
    return fg


def emit(name, bg, fg):
    m = bg.copy(); m.alpha_composite(fg)
    m.convert("RGB").resize((1024, 1024), Image.LANCZOS).save(OUT / f"{name}.png")
    fg.resize((1024, 1024), Image.LANCZOS).save(OUT / f"{name}_fg.png")
    bg.convert("RGB").resize((1024, 1024), Image.LANCZOS).save(OUT / f"{name}_bg.png")


# 1) 4.webp - tilted card, iOS style: recentre, a touch smaller so corners breathe
c4 = extract(Image.open(IMG / "4.webp"))
c4.save(OUT / "card4.png")
emit("1_naklonena_karta", felt(), compose(c4, 0.86, (0.5, 0.5)))

# 2) 2.webp - standing studio photo: card larger, keep the studio feel
c2 = extract(Image.open(IMG / "2.webp"))
c2.save(OUT / "card2.png")
emit("2_stojaca_karta", felt(top=(20, 140, 70), bottom=(2, 40, 18), spot=0.7),
     compose(c2, 0.80, (0.5, 0.49), shadow=(60, (40, 60), 190)))

# 3) 3.webp - standing card with big pips (portrait source)
c3 = extract(Image.open(IMG / "3.webp"))
c3.save(OUT / "card3.png")
emit("3_karta_velke_listy", felt(top=(22, 130, 72), bottom=(2, 38, 20), spot=0.6),
     compose(c3, 0.82, (0.5, 0.5), shadow=(60, (40, 60), 190)))
print("ok")

# 1b) detail: top half of the tilted card, readable at tiny sizes
emit("1b_detail_hlavy", felt(), compose(c4, 1.22, (0.57, 0.76), shadow=(50, (0, 50), 170)))
print("1b ok")
