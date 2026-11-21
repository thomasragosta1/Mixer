#!/usr/bin/env python3
"""Draws the Fauna app icon: an amber animal eye with a slit pupil on flat green.
Writes light, dark and tinted variants plus the in-app Logo. Requires Pillow."""
from pathlib import Path
import math
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent / "Fauna/Resources/Assets.xcassets"
OUT = ROOT / "AppIcon.appiconset"
S = 2048
GREEN = (51, 173, 94)


def radial(size, inner, outer, power=1.0):
    img = Image.new("RGB", (size, size))
    px = img.load()
    c = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            t = min(1.0, math.hypot(x - c, y - c) / c) ** power
            px[x, y] = tuple(round(inner[i] + (outer[i] - inner[i]) * t) for i in range(3))
    return img


def eye(gray=False):
    """Returns (RGBA eye layer at full canvas size)."""
    d = int(S * 0.62)                   # iris diameter
    small = 512                         # draw the iris texture small, then scale up
    iris = radial(small, (255, 214, 92), (214, 118, 22), 1.3)
    # fine radial fibres
    fib = Image.new("L", (small, small), 0)
    fd = ImageDraw.Draw(fib)
    c = small / 2
    for k in range(180):
        a = k / 180 * 2 * math.pi
        r0, r1 = small * 0.12, small * 0.49
        fd.line([(c + r0 * math.cos(a), c + r0 * math.sin(a)), (c + r1 * math.cos(a), c + r1 * math.sin(a))],
                fill=40 if k % 2 else 22, width=2)
    iris = Image.composite(Image.new("RGB", (small, small), (150, 70, 0)), iris, fib.filter(ImageFilter.GaussianBlur(1)))
    iris = iris.resize((d, d), Image.LANCZOS)

    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ox = oy = (S - d) // 2
    circle = Image.new("L", (d, d), 0)
    ImageDraw.Draw(circle).ellipse([0, 0, d - 1, d - 1], fill=255)
    layer.paste(iris, (ox, oy), circle)

    # darker limbal ring
    ring = Image.new("L", (S, S), 0)
    rd = ImageDraw.Draw(ring)
    rd.ellipse([ox, oy, ox + d, oy + d], outline=255, width=int(d * 0.035))
    ring = ring.filter(ImageFilter.GaussianBlur(d * 0.012))
    layer.paste((110, 55, 5, 255), (0, 0), ring.point(lambda v: int(v * 0.8)))

    # slit pupil: the overlap of two large circles (a vertical lens)
    R = d * 0.62
    w = d * 0.19
    cx, cy = S / 2, S / 2
    a = Image.new("L", (S, S), 0); ImageDraw.Draw(a).ellipse([cx - R + w / 2 - R, cy - R, cx + w / 2 + R - R + R, cy + R], fill=255)
    a = Image.new("L", (S, S), 0); ImageDraw.Draw(a).ellipse([cx + w / 2 - 2 * R, cy - R, cx + w / 2, cy + R], fill=255)
    b = Image.new("L", (S, S), 0); ImageDraw.Draw(b).ellipse([cx - w / 2, cy - R, cx - w / 2 + 2 * R, cy + R], fill=255)
    pupil = ImageChops.multiply(a, b)
    clip = Image.new("L", (S, S), 0); ImageDraw.Draw(clip).ellipse([ox + d * 0.04, oy + d * 0.04, ox + d * 0.96, oy + d * 0.96], fill=255)
    pupil = ImageChops.multiply(pupil, clip).filter(ImageFilter.GaussianBlur(2))
    layer.paste((18, 12, 6, 255), (0, 0), pupil)

    # catch-light
    hl = Image.new("L", (S, S), 0)
    hx, hy, hr = cx - d * 0.2, cy - d * 0.22, d * 0.075
    ImageDraw.Draw(hl).ellipse([hx - hr, hy - hr, hx + hr, hy + hr], fill=255)
    layer.paste((255, 255, 255, 255), (0, 0), hl.filter(ImageFilter.GaussianBlur(3)).point(lambda v: int(v * 0.92)))

    if gray:
        g = layer.convert("LA")
        layer = Image.merge("RGBA", (g.getchannel(0),) * 3 + (g.getchannel(1),))
    return layer


def compose(bg, layer, shadow=True):
    base = Image.new("RGBA", (S, S), bg + (255,))
    if shadow:
        sh = Image.new("RGBA", (S, S), (0, 40, 15, 0))
        sh.putalpha(layer.getchannel("A").filter(ImageFilter.GaussianBlur(S * 0.02)).point(lambda v: int(v * 0.35)))
        base.alpha_composite(sh, (0, int(S * 0.012)))
    base.alpha_composite(layer)
    return base.convert("RGB")


def save(img, path, size=1024):
    img.resize((size, size), Image.LANCZOS).save(path, optimize=True)
    print("wrote", path.name)


e = eye()
light = compose(GREEN, e)
save(light, OUT / "AppIcon.png")
save(compose((14, 16, 15), e), OUT / "AppIcon-Dark.png")
save(compose((0, 0, 0), eye(gray=True), shadow=False), OUT / "AppIcon-Tinted.png")

logo = ROOT / "Logo.imageset"
logo.mkdir(exist_ok=True)
save(light, logo / "Logo.png", 360)
(logo / "Contents.json").write_text('{\n  "images" : [ { "filename" : "Logo.png", "idiom" : "universal" } ],\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n')
