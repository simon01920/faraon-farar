#!/usr/bin/env python3
"""Generate app icons for iOS + Android (Godot export) from one master image.

Usage:
    python3 tools/make_icons.py MASTER.png [--fg FOREGROUND.png] [--out assets/icon]

MASTER      square, full-bleed artwork (no transparency); important content
            must sit inside the central ~66 % (Android adaptive safe zone).
--bg        optional background layer (no motif) for the Android adaptive icon.
--fg        optional transparent cut-out of the main motif (same framing as
            MASTER). Used as the Android adaptive foreground + monochrome icon.

Outputs (all PNG):
    icon_1024.png               iOS App Store / Godot iOS icon (RGB, no alpha)
    android_main_192.png        legacy Android launcher icon
    android_fg_432.png          adaptive icon foreground (108 dp @ xxxhdpi)
    android_bg_432.png          adaptive icon background
    android_mono_432.png        Android 13+ themed (monochrome) icon
    play_store_512.png          Google Play listing icon (RGB, no alpha)
    preview.png                 mask/size preview sheet (not for shipping)

Rules applied (from the app-icon / web-asset-generator skills + store specs):
  * iOS: 1024x1024, opaque, square corners (the OS rounds them).
  * Android adaptive: 108 dp layers, only the centre 72 dp is visible and the
    centre 66 dp circle is guaranteed -> motif scaled into that zone.
  * Play Store: 512x512, opaque, square (Play applies the mask).
"""
import argparse
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ADAPTIVE = 432           # 108 dp at xxxhdpi (4x)
SAFE = 66 / 108          # guaranteed-visible circle diameter


def opaque(img: Image.Image, bg=(0, 0, 0)) -> Image.Image:
    img = img.convert("RGBA")
    base = Image.new("RGBA", img.size, bg + (255,))
    return Image.alpha_composite(base, img).convert("RGB")


def square(img: Image.Image) -> Image.Image:
    w, h = img.size
    s = min(w, h)
    return img.crop(((w - s) // 2, (h - s) // 2, (w - s) // 2 + s, (h - s) // 2 + s))


def fit_center(img: Image.Image, canvas: int, frac: float) -> Image.Image:
    size = round(canvas * frac)
    out = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    out.paste(img.resize((size, size), Image.LANCZOS), ((canvas - size) // 2,) * 2)
    return out


def mask(size: int, kind: str) -> Image.Image:
    m = Image.new("L", (size * 4, size * 4), 0)
    d = ImageDraw.Draw(m)
    box = (0, 0, size * 4 - 1, size * 4 - 1)
    if kind == "circle":
        d.ellipse(box, fill=255)
    elif kind == "squircle":
        d.rounded_rectangle(box, radius=size * 4 * 0.32, fill=255)
    elif kind == "ios":
        d.rounded_rectangle(box, radius=size * 4 * 0.2237, fill=255)
    else:
        d.rounded_rectangle(box, radius=size * 4 * 0.08, fill=255)
    return m.resize((size, size), Image.LANCZOS)


def adaptive_preview(fg: Image.Image, bg: Image.Image, size: int, kind: str) -> Image.Image:
    layer = Image.alpha_composite(bg.convert("RGBA"), fg)
    # Visible viewport = centre 72/108 of the layer.
    c = ADAPTIVE * (18 / 108)
    view = layer.crop((round(c), round(c), round(ADAPTIVE - c), round(ADAPTIVE - c)))
    view = view.resize((size, size), Image.LANCZOS)
    view.putalpha(mask(size, kind))
    return view


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("master")
    ap.add_argument("--fg")
    ap.add_argument("--bg", help="optional background layer without the motif (Android adaptive)")
    ap.add_argument("--out", default="assets/icon")
    a = ap.parse_args()
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)

    master = opaque(square(Image.open(a.master))).resize((1024, 1024), Image.LANCZOS)
    master.save(out / "icon_1024.png", optimize=True)
    master.resize((512, 512), Image.LANCZOS).save(out / "play_store_512.png", optimize=True)

    # Legacy launcher icon: full art with light rounding baked in (pre-Android 8).
    main192 = master.resize((192, 192), Image.LANCZOS).convert("RGBA")
    main192.putalpha(mask(192, "squircle"))
    main192.save(out / "android_main_192.png", optimize=True)

    if a.fg:
        fg_src = square(Image.open(a.fg).convert("RGBA"))
        # Shrink the cut-out so the whole motif lands inside the safe circle.
        bbox = fg_src.getbbox() or (0, 0, *fg_src.size)
        fg_src = fg_src.crop(bbox)
        s = max(fg_src.size)
        padded = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        padded.paste(fg_src, ((s - fg_src.size[0]) // 2, (s - fg_src.size[1]) // 2))
        fg = fit_center(padded, ADAPTIVE, SAFE * 0.98)
        if a.bg:
            bg = opaque(square(Image.open(a.bg))).resize((ADAPTIVE, ADAPTIVE), Image.LANCZOS)
        else:
            # Fallback: the master artwork blurred, so the colours match.
            bg = master.resize((ADAPTIVE, ADAPTIVE), Image.LANCZOS).filter(ImageFilter.GaussianBlur(18))
        # Monochrome: white silhouette, system tints it.
        alpha = fg.getchannel("A")
        mono = Image.new("RGBA", fg.size, (255, 255, 255, 0))
        mono.putalpha(alpha)
    else:
        # Full-bleed art as background: the visible 72 dp viewport + 66 dp
        # safe circle are both centred, matching how the master was composed.
        bg = master.resize((ADAPTIVE, ADAPTIVE), Image.LANCZOS)
        fg = Image.new("RGBA", (ADAPTIVE, ADAPTIVE), (0, 0, 0, 0))
        # Monochrome from luminance edges of the centre (best effort).
        g = master.convert("L").resize((ADAPTIVE, ADAPTIVE), Image.LANCZOS)
        edges = g.filter(ImageFilter.FIND_EDGES).point(lambda v: 255 if v > 40 else 0)
        circle = Image.new("L", g.size, 0)
        r = ADAPTIVE * SAFE / 2
        ImageDraw.Draw(circle).ellipse((ADAPTIVE / 2 - r, ADAPTIVE / 2 - r, ADAPTIVE / 2 + r, ADAPTIVE / 2 + r), fill=255)
        mono = Image.new("RGBA", g.size, (255, 255, 255, 0))
        mono.putalpha(ImageChops.multiply(edges, circle))

    fg.save(out / "android_fg_432.png", optimize=True)
    bg.convert("RGB").save(out / "android_bg_432.png", optimize=True)
    mono.save(out / "android_mono_432.png", optimize=True)

    # Preview sheet: masks on light + dark backgrounds and small sizes.
    sheet = Image.new("RGB", (1240, 560), (245, 245, 245))
    ImageDraw.Draw(sheet).rectangle((0, 280, 1240, 560), fill=(24, 24, 28))
    for row, y0 in enumerate((40, 320)):
        x = 30
        ios = master.resize((200, 200), Image.LANCZOS).convert("RGBA")
        ios.putalpha(mask(200, "ios"))
        sheet.paste(ios, (x, y0), ios)
        x += 230
        for kind in ("circle", "squircle", "rounded"):
            p = adaptive_preview(fg, bg, 200, kind)
            sheet.paste(p, (x, y0), p)
            x += 230
        for sz in (96, 48, 29):
            p = master.resize((sz, sz), Image.LANCZOS).convert("RGBA")
            p.putalpha(mask(sz, "ios"))
            sheet.paste(p, (x, y0 + 200 - sz), p)
            x += sz + 20
    sheet.save(out / "preview.png", optimize=True)
    print("wrote", ", ".join(sorted(p.name for p in out.glob("*.png"))))


if __name__ == "__main__":
    main()
