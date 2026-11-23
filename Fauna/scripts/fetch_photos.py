#!/usr/bin/env python3
"""Resolves each animal's photo to a freely licensed Wikimedia Commons file, with author and
license, and writes Fauna/Resources/photos.json for the app to bundle. Run in CI (needs network).

Mirrors WikiImages.swift: lead image if it's on Commons, else the article's first Commons image.
Also checks that the 1280px thumbnail URL the app will build actually loads."""
import html, json, re, sys, time, urllib.error, urllib.parse, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UA = {"User-Agent": "Fauna/1.0 (iOS app build script; https://github.com/thomasragosta1/Mixer)"}

def get(url, tries=6):
    for i in range(tries):
        try:
            return json.load(urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30))
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503, 504) and i < tries - 1:
                time.sleep(2 ** i); continue
            raise
    return None

def plain(s):
    s = re.sub(r"<[^>]+>", "", s or "")
    return " ".join(html.unescape(s).split())

def file_from_upload(url):
    parts = urllib.parse.urlparse(url).path.split("/")
    parts = [urllib.parse.unquote(p) for p in parts]
    if "thumb" in parts:
        i = parts.index("thumb")
        return parts[i + 3]
    return parts[-1]

def thumb(original, width, orig_width):
    if orig_width and orig_width <= width:
        return original
    s = original.replace("/wikipedia/commons/", "/wikipedia/commons/thumb/", 1)
    name = urllib.parse.unquote(original.rsplit("/", 1)[1])
    enc = urllib.parse.quote(name, safe="()'!*,;=+$:@&-._~")
    suffix = ".png" if name.lower().endswith((".svg", ".tif", ".tiff")) else ""
    return f"{s}/{width}px-{enc}{suffix}"

animals = json.loads((ROOT / "Fauna/Resources/animals.json").read_text())
out_path = ROOT / "Fauna/Resources/photos.json"
existing = json.loads(out_path.read_text()) if out_path.exists() else {}
files = {}
for a in animals:
    t = a["wikipediaTitle"]
    path = urllib.parse.quote(t.replace(" ", "_"), safe="")
    try:
        s = get(f"https://en.wikipedia.org/api/rest_v1/page/summary/{path}")
        lead = (s.get("originalimage") or {}).get("source", "")
        f = file_from_upload(lead) if "/wikipedia/commons/" in lead else None
        if f is None:
            print(f"note {a['id']}: lead image isn't on Commons, using the next Commons photo")
            m = get(f"https://en.wikipedia.org/api/rest_v1/page/media-list/{path}")
            for item in m.get("items", []):
                if item.get("type") == "image" and any("/wikipedia/commons/" in x.get("src", "") for x in item.get("srcset", [])):
                    f = item["title"].replace("File:", "", 1); break
        if f: files[t] = f
        else: print(f"WARN {a['id']}: no Commons photo")
    except Exception as e:
        print(f"WARN {a['id']}: {e}")
    time.sleep(0.4)

result = {}
titles = list(files.items())
for i in range(0, len(titles), 40):
    chunk = titles[i:i + 40]
    q = "|".join("File:" + f for _, f in chunk)
    data = get("https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode({
        "action": "query", "format": "json", "formatversion": "2", "prop": "imageinfo",
        "iiprop": "url|size|extmetadata", "titles": q}))
    norm = {n["from"]: n["to"] for n in data["query"].get("normalized", [])}
    pages = {p["title"]: p for p in data["query"]["pages"]}
    for t, f in chunk:
        key = norm.get("File:" + f, "File:" + f)
        p = pages.get(key)
        ii = (p or {}).get("imageinfo", [None])[0] if p else None
        if not ii:
            print(f"WARN {t}: no Commons info for {f}"); continue
        meta = ii.get("extmetadata", {})
        lic = plain(meta.get("LicenseShortName", {}).get("value"))
        if "fair use" in lic.lower() or "non-free" in lic.lower():
            print(f"WARN {t}: {f} is not free ({lic})"); continue
        result[t] = {
            "original": ii["url"], "width": ii.get("width", 0),
            "credit": {
                "file": f,
                "author": plain(meta.get("Artist", {}).get("value"))[:80],
                "license": lic,
                "licenseURL": plain(meta.get("LicenseUrl", {}).get("value")) or None,
                "pageURL": ii.get("descriptionurl") or "https://commons.wikimedia.org/wiki/File:" + urllib.parse.quote(f),
            },
        }
    time.sleep(0.5)

# Check the URLs the app will load.
bad = 0
for t, src in result.items():
    u = thumb(src["original"], 1280, src["width"])
    try:
        urllib.request.urlopen(urllib.request.Request(u, headers=UA, method="HEAD"), timeout=30)
    except Exception as e:
        bad += 1; print(f"WARN {t}: thumbnail failed {e}: {u}")
    time.sleep(0.2)

# Keep earlier entries for anything that failed this time.
for t, v in existing.items():
    result.setdefault(t, v)
out_path.write_text(json.dumps(result, ensure_ascii=False, indent=1, sort_keys=True) + "\n")
print(f"{len(result)}/{len(animals)} photos resolved, {bad} thumbnail problems")
for t, v in sorted(result.items())[:5]:
    print(" ", t, "->", v["credit"]["author"][:40], "|", v["credit"]["license"])
