#!/usr/bin/env python3
"""Draws the Fauna app icon (light, dark and tinted) in the style of Apple's own icons:
one simple white glyph on a soft vertical gradient. Requires Pillow."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent / "Fauna/Resources/Assets.xcassets"
OUT = ROOT / "AppIcon.appiconset"
S = 2048  # drawn at 2x, saved at 1024


def gradient(top, bottom):
    img = Image.new("RGB", (S, S))
    d = ImageDraw.Draw(img)
    for y in range(S):
        t = y / (S - 1)
        d.line([(0, y), (S, y)], fill=tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return img


def paw_mask():
    """A pawprint built from soft shapes, unioned smoothly (blur + threshold) like an SF Symbol."""
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    cx, cy, u = S * 0.5, S * 0.57, S * 0.01
    # main pad: three overlapping circles melted together into a rounded triangle
    d.ellipse([cx - 15 * u, cy - 9 * u, cx + 15 * u, cy + 13 * u], fill=255)
    d.ellipse([cx - 19 * u, cy + 1 * u, cx - 3 * u, cy + 17 * u], fill=255)
    d.ellipse([cx + 3 * u, cy + 1 * u, cx + 19 * u, cy + 17 * u], fill=255)
    m = m.filter(ImageFilter.GaussianBlur(3.2 * u)).point(lambda v: 255 if v > 120 else 0)
    # toes
    toes = Image.new("L", (S, S), 0)
    for dx, dy, rx, ry, rot in [(-21, -12, 6.2, 8.0, 28), (-8, -23, 6.6, 8.6, 9),
                                (8, -23, 6.6, 8.6, -9), (21, -12, 6.2, 8.0, -28)]:
        t = Image.new("L", (int(20 * u), int(20 * u)), 0)
        ImageDraw.Draw(t).ellipse([10 * u - rx * u, 10 * u - ry * u, 10 * u + rx * u, 10 * u + ry * u], fill=255)
        t = t.rotate(rot, resample=Image.BICUBIC)
        toes.paste(t, (int(cx + dx * u - 10 * u), int(cy + dy * u - 10 * u)), t)
    m.paste(255, (0, 0), toes)
    return m.filter(ImageFilter.GaussianBlur(1.2))


def save(img, name):
    img.resize((1024, 1024), Image.LANCZOS).save(OUT / name, optimize=True)
    print("wrote", name)


glyph = paw_mask()

# Light: white paw on a bright-to-deep green, like Apple's system app icons.
light = gradient((86, 214, 120), (22, 150, 82))
shadow = Image.new("RGBA", (S, S), (0, 70, 30, 0))
shadow.putalpha(glyph.filter(ImageFilter.GaussianBlur(S * 0.012)).point(lambda v: int(v * 0.25)))
light = light.convert("RGBA")
light.alpha_composite(shadow, (0, int(S * 0.008)))
light.paste((255, 255, 255, 255), (0, 0), glyph)
save(light.convert("RGB"), "AppIcon.png")

# Dark: near-black background, green gradient glyph (the iOS 18+ dark icon style).
dark = gradient((32, 36, 34), (10, 12, 11)).convert("RGBA")
dark.paste(gradient((110, 226, 140), (40, 180, 100)), (0, 0), glyph)
save(dark.convert("RGB"), "AppIcon-Dark.png")

# Tinted: grayscale glyph on black; iOS applies the user's tint.
tinted = gradient((0, 0, 0), (0, 0, 0)).convert("L")
tinted.paste(gradient((255, 255, 255), (200, 200, 200)).convert("L"), (0, 0), glyph)
save(tinted.convert("RGB"), "AppIcon-Tinted.png")

# In-app logo (onboarding): the light icon, smaller.
logo = ROOT / "Logo.imageset"
logo.mkdir(exist_ok=True)
light.convert("RGB").resize((360, 360), Image.LANCZOS).save(logo / "Logo.png", optimize=True)
(logo / "Contents.json").write_text('{\n  "images" : [ { "filename" : "Logo.png", "idiom" : "universal" } ],\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n')
