"""Faraon card asset pipeline.

Converts raw card scans in karty/<suit>/*.jpg (+ karty/back.png) into
game-ready PNGs with alpha in assets/cards/, preserving the suit folder
structure. Deterministic OpenCV approach (rembg was tested and rejected:
u2net deletes the white card face).

Steps per card:
  1. Otsu threshold -> largest contour -> minAreaRect of the physical card
  2. inset the box ~1% toward center (cuts grey scan edge on card borders)
  3. perspective warp to canonical 750x1125
  4. rounded-corner alpha mask (radius 42)

Run:  python tools/card_pipeline.py
Outputs a magenta contact sheet to tools/pipeline_report.jpg for visual QA
and prints any file whose detected card area looks suspicious.
"""
import os
import sys

import cv2
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "karty")
DST = os.path.join(ROOT, "assets", "cards")
REPORT = os.path.join(ROOT, "tools", "pipeline_report.jpg")

CANON_W, CANON_H = 750, 1125
CORNER_RADIUS = 42
INSET = 0.010  # fraction of box size trimmed on each side
SUITS = ["zalud", "cerven", "zelen", "gula"]
RANKS = ["VII", "VIII", "IX", "X", "dolnik", "hornik", "krali", "stopky"]


def order_pts(pts):
    rect = np.zeros((4, 2), dtype="float32")
    s = pts.sum(axis=1)
    d = np.diff(pts, axis=1).ravel()
    rect[0] = pts[np.argmin(s)]
    rect[1] = pts[np.argmin(d)]
    rect[2] = pts[np.argmax(s)]
    rect[3] = pts[np.argmax(d)]
    return rect


def rounded_mask(w, h, r):
    mask = np.zeros((h, w), dtype=np.uint8)
    cv2.rectangle(mask, (r, 0), (w - r, h), 255, -1)
    cv2.rectangle(mask, (0, r), (w, h - r), 255, -1)
    for cx, cy in [(r, r), (w - r, r), (r, h - r), (w - r, h - r)]:
        cv2.circle(mask, (cx, cy), r, 255, -1)
    return mask


def inset_box(box):
    center = box.mean(axis=0)
    return (box - center) * (1.0 - 2.0 * INSET) + center


def process(src_path, out_path):
    img = cv2.imread(src_path)
    if img is None:
        return None
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    blur = cv2.GaussianBlur(gray, (7, 7), 0)
    _, th = cv2.threshold(blur, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    cnts, _ = cv2.findContours(th, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    c = max(cnts, key=cv2.contourArea)
    area_ratio = cv2.contourArea(c) / (img.shape[0] * img.shape[1])
    box = order_pts(cv2.boxPoints(cv2.minAreaRect(c)))
    box = inset_box(box).astype("float32")
    dst = np.array(
        [[0, 0], [CANON_W - 1, 0], [CANON_W - 1, CANON_H - 1], [0, CANON_H - 1]],
        dtype="float32",
    )
    M = cv2.getPerspectiveTransform(box, dst)
    warped = cv2.warpPerspective(img, M, (CANON_W, CANON_H), flags=cv2.INTER_AREA)
    rgba = cv2.cvtColor(warped, cv2.COLOR_BGR2BGRA)
    rgba[:, :, 3] = rounded_mask(CANON_W, CANON_H, CORNER_RADIUS)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    cv2.imwrite(out_path, rgba)
    return area_ratio


def main():
    jobs = [(os.path.join(SRC, s, r + ".jpg"), os.path.join(DST, s, r + ".png"), f"{s}/{r}")
            for s in SUITS for r in RANKS]
    jobs.append((os.path.join(SRC, "back.png"), os.path.join(DST, "back.png"), "back"))

    problems = []
    done = []
    for src, dst, label in jobs:
        if not os.path.isfile(src):
            problems.append((label, "missing source file"))
            continue
        ratio = process(src, dst)
        if ratio is None:
            problems.append((label, "unreadable image"))
        elif ratio < 0.85:
            problems.append((label, f"suspicious card area {ratio:.1%}"))
        else:
            done.append((dst, label))
        print(f"{label:16s} {'FAIL' if ratio is None else f'{ratio:.2%}'}")

    # contact sheet of everything, composited on magenta
    H = 240
    cols = 11
    thumb_w = int(CANON_W * H / CANON_H)
    rows = (len(done) + cols - 1) // cols
    pad = 12
    sheet = Image.new("RGB", (cols * (thumb_w + pad) + pad, rows * (H + pad) + pad), (255, 0, 255))
    for i, (p, _) in enumerate(done):
        im = Image.open(p).convert("RGBA").resize((thumb_w, H))
        cell = Image.new("RGBA", (thumb_w, H), (255, 0, 255, 255))
        cell.alpha_composite(im)
        x = pad + (i % cols) * (thumb_w + pad)
        y = pad + (i // cols) * (H + pad)
        sheet.paste(cell.convert("RGB"), (x, y))
    sheet.save(REPORT, quality=88)

    print(f"\nprocessed: {len(done)}   problems: {len(problems)}")
    for label, why in problems:
        print(f"  PROBLEM {label}: {why}")
    print(f"report: {REPORT}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
