#!/usr/bin/env python3
"""Validate Fauna/Resources/animals.json.

  python3 scripts/validate_content.py           # structure only
  python3 scripts/validate_content.py --online  # also check every Wikipedia title has a photo
"""
import json, sys, urllib.error, urllib.parse, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GROUPS = {"mammal", "bird", "reptile", "amphibian", "fish", "insect", "marineInvertebrate"}
REGIONS = {"arctic", "naEast", "naWest", "centralAmerica", "southAmerica", "europe", "africa",
           "asia", "oceania", "antarctica", "openOcean"}
STATUSES = {"LC", "NT", "VU", "EN", "CR", "EW", "EX", "DD", "NE"}
TEXT = ["name", "scientificName", "wikipediaTitle", "range", "tagline", "lede", "home", "life",
        "remarkable", "outlook", "didYouKnow"]

def fail(msg):
    print("ERROR:", msg); fail.count += 1
fail.count = 0

animals = json.loads((ROOT / "Fauna/Resources/animals.json").read_text())
ids = set()
for a in animals:
    aid = a.get("id", "?")
    if aid in ids: fail(f"{aid}: duplicate id")
    ids.add(aid)
    for k in TEXT:
        if not isinstance(a.get(k), str) or not a[k].strip(): fail(f"{aid}: missing {k}")
    if a.get("group") not in GROUPS: fail(f"{aid}: bad group {a.get('group')}")
    if not a.get("regions") or not set(a["regions"]) <= REGIONS: fail(f"{aid}: bad regions {a.get('regions')}")
    if a.get("status") not in STATUSES: fail(f"{aid}: bad status")
    c = a.get("coordinate", {})
    if not (-90 <= c.get("latitude", 999) <= 90 and -180 <= c.get("longitude", 999) <= 180): fail(f"{aid}: bad coordinate")
    if not (0 < a.get("mapSpan", 0) <= 180): fail(f"{aid}: bad mapSpan")
    if len(a.get("facts", [])) != 4: fail(f"{aid}: needs 4 facts")
    q = a.get("quiz", [])
    if not 1 <= len(q) <= 3: fail(f"{aid}: needs 1-3 quiz questions")
    for i, qq in enumerate(q):
        ch = qq.get("choices", [])
        if len(ch) != 4 or len(set(ch)) != 4: fail(f"{aid}: quiz {i} needs 4 distinct choices")
        if not qq.get("prompt") or not qq.get("explanation"): fail(f"{aid}: quiz {i} incomplete")
    ch = a.get("charities", [])
    if not ch: fail(f"{aid}: needs a charity")
    for c in ch:
        if not c.get("url", "").startswith("https://"): fail(f"{aid}: charity url must be https")
    words = sum(len(a[k].split()) for k in ["lede", "home", "life", "remarkable", "outlook"])
    if words > 420: fail(f"{aid}: article too long ({words} words)")

print(f"{len(animals)} animals, {sum(len(a['quiz']) for a in animals)} questions")
from collections import Counter
print("groups:", dict(Counter(a["group"] for a in animals)))
print("regions:", dict(Counter(r for a in animals for r in a["regions"])))

if "--online" in sys.argv:
    import time
    # Wikipedia rate-limits bursts: go slowly, retry 429s, and only fail on real misses.
    for a in animals:
        title = a["wikipediaTitle"].replace(" ", "_")
        url = "https://en.wikipedia.org/api/rest_v1/page/summary/" + urllib.parse.quote(title, safe="")
        req = urllib.request.Request(url, headers={"User-Agent": "Fauna content check (github actions)"})
        for attempt in range(5):
            try:
                data = json.load(urllib.request.urlopen(req, timeout=20))
                img = (data.get("originalimage") or data.get("thumbnail") or {}).get("source")
                if not img: fail(f"{a['id']}: no image for '{a['wikipediaTitle']}'")
                else: print(f"ok  {a['id']:28} {data.get('title')}")
                break
            except urllib.error.HTTPError as e:
                if e.code == 429 and attempt < 4:
                    time.sleep(2 ** attempt * 2); continue
                if e.code == 429: print(f"WARN {a['id']}: still rate-limited, skipped")
                else: fail(f"{a['id']}: '{a['wikipediaTitle']}' -> {e}")
                break
            except Exception as e:
                print(f"WARN {a['id']}: {e}"); break
        time.sleep(0.6)

if fail.count:
    print(f"{fail.count} problem(s)"); sys.exit(1)
print("Content OK")
