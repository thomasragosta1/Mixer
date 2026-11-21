#!/usr/bin/env python3
"""Draws the Fauna app icon (light and dark) into the asset catalog. Requires Pillow."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
import math

OUT = Path(__file__).resolve().parent.parent / "Fauna/Resources/Assets.xcassets/AppIcon.appiconset"
S = 4096  # supersampled, downscaled to 1024

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def background(top, bottom, glow):
    img = Image.new("RGB", (S, S))
    px = img.load()
    for y in range(S):
        c = lerp(top, bottom, y / S)
        ImageDraw.Draw(img).line([(0, y), (S, y)], fill=c)
    g = Image.new("L", (S, S), 0)
    ImageDraw.Draw(g).ellipse([S * 0.05, -S * 0.25, S * 0.95, S * 0.65], fill=255)
    g = g.filter(ImageFilter.GaussianBlur(S * 0.12))
    img = Image.composite(Image.new("RGB", (S, S), glow), img, g.point(lambda v: int(v * 0.55)))
    return img

def paw(draw, cx, cy, scale, color):
    # main pad: a soft rounded triangle built from overlapping ellipses
    w, h = 0.25 * scale, 0.20 * scale
    draw.ellipse([cx - w * 0.78, cy - h * 0.62, cx + w * 0.78, cy + h * 0.75], fill=color)
    draw.ellipse([cx - w * 1.0, cy - h * 0.05, cx - w * 0.02, cy + h * 0.92], fill=color)
    draw.ellipse([cx + w * 0.02, cy - h * 0.05, cx + w * 1.0, cy + h * 0.92], fill=color)
    # toes
    toes = [(-0.33, -0.22, 0.085, 0.11, -22), (-0.12, -0.42, 0.09, 0.118, -7),
            (0.12, -0.42, 0.09, 0.118, 7), (0.33, -0.22, 0.085, 0.11, 22)]
    for dx, dy, rx, ry, rot in toes:
        toe = Image.new("L", (int(rx * scale * 2.6), int(ry * scale * 2.6)), 0)
        tw, th = toe.size
        ImageDraw.Draw(toe).ellipse([tw / 2 - rx * scale, th / 2 - ry * scale, tw / 2 + rx * scale, th / 2 + ry * scale], fill=255)
        toe = toe.rotate(-rot, resample=Image.BICUBIC)
        layer = Image.new("RGBA", toe.size, color)
        draw._image.paste(layer, (int(cx + dx * scale - tw / 2), int(cy + dy * scale - th / 2)), toe)

def make(name, top, bottom, glow, paw_color, sun_color):
    img = background(top, bottom, glow).convert("RGBA")
    d = ImageDraw.Draw(img)
    # a low golden sun behind the paw
    sun = Image.new("L", (S, S), 0)
    ImageDraw.Draw(sun).ellipse([S * 0.17, S * 0.17, S * 0.83, S * 0.83], fill=255)
    sun = sun.filter(ImageFilter.GaussianBlur(S * 0.004))
    img.paste(Image.new("RGBA", (S, S), sun_color), (0, 0), sun.point(lambda v: int(v * 0.22)))
    # soft shadow under the paw
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    paw(ImageDraw.Draw(shadow), S * 0.5, S * 0.58 + S * 0.015, S * 0.92, (0, 0, 0, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(S * 0.02))
    img = Image.alpha_composite(img, shadow)
    d = ImageDraw.Draw(img)
    paw(d, S * 0.5, S * 0.58, S * 0.92, paw_color)
    img = img.convert("RGB").resize((1024, 1024), Image.LANCZOS)
    img.save(OUT / name, optimize=True)
    print("wrote", OUT / name)

make("AppIcon.png", (28, 92, 70), (9, 38, 31), (70, 140, 100), (247, 226, 178, 255), (245, 200, 107, 255))
make("AppIcon-Dark.png", (16, 40, 33), (3, 10, 9), (30, 70, 52), (240, 205, 130, 255), (245, 200, 107, 255))
