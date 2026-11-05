"""6.webp: replace wrong spade corner indices with leaf pips, then build icon master."""
from pathlib import Path
from PIL import Image, ImageFilter, ImageDraw

B = Path("/tmp/claude-0/-home-user-faraon-farar/9a26ed85-e155-5efe-8341-2be0b70a7ab5")
OUT = B / "scratchpad/refined"

im = Image.open(B / "images/6.webp").convert("RGB")
src4 = Image.open(B / "images/4.webp").convert("RGB")
px = im.load()


def erase(box):
    x0, y0, x1, y1 = box
    m = Image.new("L", im.size, 0)
    mp = m.load()
    whites = []
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b = px[x, y]
            if r + g + b < 690:
                mp[x, y] = 255
            elif r + g + b > 690:
                whites.append((r, g, b))
    m = m.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(1.5))
    m = Image.composite(m, Image.new('L', im.size, 0), Image.new('L', im.size, 0).point(lambda v: 0))
    clip = Image.new('L', im.size, 0); ImageDraw.Draw(clip).rectangle(box, fill=255)
    from PIL import ImageChops as _C; m = _C.multiply(m, clip)
    avg = tuple(sum(c[i] for c in whites) // len(whites) for i in range(3))
    # keep the card's inner frame line (blue-grey, not green) untouched
    keep = Image.new("L", im.size, 0)
    kp = keep.load()
    for y in range(y0 - 6, y1 + 6):
        for x in range(x0 - 6, x1 + 6):
            r, g, b = px[x, y]
            if r + g + b < 600 and b >= g - 6:
                kp[x, y] = 255
    keep = keep.filter(ImageFilter.MaxFilter(3))
    from PIL import ImageChops
    im.paste(Image.new("RGB", im.size, avg), (0, 0), m)


def pip_from4(box):
    p = src4.crop(box).convert("RGBA")
    a = p.convert("L").point(lambda v: 255 if v < 232 else 0)
    # keep only the pip itself (connected to its centre); drop frame-line fragments
    a = a.filter(ImageFilter.MaxFilter(5))
    ImageDraw.floodfill(a, (a.size[0] // 2, a.size[1] // 2), 128)
    a = a.point(lambda v: 255 if v == 128 else 0).filter(ImageFilter.MinFilter(5))
    a = a.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(0.7))
    p.putalpha(a)
    return p.crop(a.getbbox())


def put(pip, center, height, angle):
    s = height / pip.size[1]
    p = pip.resize((round(pip.size[0] * s), round(pip.size[1] * s)), Image.LANCZOS)
    p = p.rotate(angle, resample=Image.BICUBIC, expand=True)
    base = im.convert("RGBA")
    base.alpha_composite(p, (round(center[0] - p.size[0] / 2), round(center[1] - p.size[1] / 2)))
    return base.convert("RGB")


erase((617, 543, 712, 656))
erase((1381, 1327, 1452, 1424))
tl = pip_from4((245, 125, 370, 280))
br = pip_from4((650, 735, 780, 890))
im = put(tl, (668, 602), 150, 3)
px = im.load()
im = put(br, (1414, 1372), 150, 3)
im.save(OUT / "6_fixed.png")

# icon master: crop around the card (keeps the original studio shadow)
master = im.crop((230, 230, 1770, 1770)).resize((1024, 1024), Image.LANCZOS)
master.save(OUT / "4_lebdiaca_karta.png")
print("ok")
