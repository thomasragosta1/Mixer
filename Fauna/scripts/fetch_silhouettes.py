#!/usr/bin/env python3
"""Finds a side-view silhouette for each animal on PhyloPic (phylopic.org), by scientific name:
the species, else its genus, else the nearest ancestor a few steps up that has one. Only
licences that allow use in a free app are kept (public domain, CC0, CC BY, CC BY-SA; never NC).
Writes Fauna/Resources/Silhouettes/sil-<id>.png and Fauna/Resources/silhouettes.json (credits).
Usage: fetch_silhouettes.py [--refresh]"""
import json, sys, time, urllib.error, urllib.parse, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "Fauna/Resources"
OUT = RES / "Silhouettes"
API = "https://api.phylopic.org"
UA = {"User-Agent": "FaunaSilhouettes/1.0 (educational app; contact via GitHub)"}
MAX_STEPS_UP = 3   # genus, then up to two more ranks; beyond that the shape may be misleading

def get(url, raw=False):
    for i in range(4):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30) as r:
                data = r.read()
                return data if raw else json.loads(data)
        except urllib.error.HTTPError as e:
            if 400 <= e.code < 500 and e.code != 429: return None   # not found: don't retry
            time.sleep(1.5 * (i + 1))
        except Exception:
            time.sleep(1.5 * (i + 1))
    return None

# Animals PhyloPic has nothing for (or nothing close): a similar-shaped relative to stand in.
STAND_INS = {
    "snapping-turtle": "Trachemys scripta", "alligator-snapping-turtle": "Trachemys scripta",
    "blandings-turtle": "Emys orbicularis", "indian-star-tortoise": "Testudo graeca",
    "peacock-mantis-shrimp": "Squilla mantis", "pistol-shrimp": "Alpheus",
    "thorny-devil": "Phrynosoma cornutum", "atlas-moth": "Actias luna", "polyphemus-moth": "Actias luna",
    "madagascan-sunset-moth": "Actias luna", "orange-oakleaf": "Vanessa atalanta",
    "orchid-mantis": "Mantis religiosa", "hercules-beetle": "Oryctes nasicornis",
    "christmas-island-red-crab": "Carcinus maenas", "red-king-crab": "Lithodes maja",
    "black-mamba": "Naja naja", "inland-taipan": "Naja naja", "boomslang": "Natrix natrix", "gaboon-viper": "Vipera berus",
    "banded-archerfish": "Perca fluviatilis", "desert-locust": "Locusta migratoria",
    "humboldt-squid": "Loligo vulgaris", "bigfin-reef-squid": "Loligo vulgaris", "giant-pacific-octopus": "Octopus vulgaris",
    "burchells-army-ant": "Formica rufa", "asian-weaver-ant": "Formica rufa", "wandering-glider": "Anax imperator",
    "giant-oarfish": "Trachipterus", "devils-hole-pupfish": "Cyprinodon variegatus", "humphead-wrasse": "Labrus bergylta",
    "fishing-cat": "Felis silvestris", "mekong-giant-catfish": "Silurus glanis", "red-bellied-piranha": "Colossoma macropomum",
    "indri": "Propithecus verreauxi", "philippine-eagle": "Aquila chrysaetos", "harpy-eagle": "Aquila chrysaetos",
    "saola": "Oryx gazella", "takahe": "Porphyrio porphyrio", "giant-isopod": "Ligia oceanica",
    "darwins-frog": "Rana temporaria", "australian-green-tree-frog": "Hyla arborea", "asian-arowana": "Osteoglossum bicirrhosum",
    "andean-flamingo": "Phoenicopterus roseus", "kereru": "Columba palumbus", "red-billed-quelea": "Passer domesticus",
}

def licence_ok(href):
    h = (href or "").lower()
    return "/nc" not in h and ("publicdomain" in h or "/by/" in h or "/by-sa/" in h)

def licence_name(href):
    h = href.lower()
    if "publicdomain/zero" in h: return "CC0"
    if "publicdomain" in h: return "Public domain"
    v = h.rstrip("/").split("/")[-1]
    return ("CC BY-SA " if "/by-sa/" in h else "CC BY ") + v

def node_by_name(build, name):
    q = urllib.parse.urlencode({"build": build, "filter_name": name.lower(), "embed_items": "true",
                                "embed_primaryImage": "true", "page": 0})
    d = get(f"{API}/nodes?{q}")
    items = ((d or {}).get("_embedded") or {}).get("items") or []
    return items[0] if items else None

def usable(image):
    if not image: return None
    lic = image.get("_links", {}).get("license", {}).get("href", "")
    if not licence_ok(lic): return None
    raster = image["_links"].get("rasterFiles") or []
    if not raster: return None
    # Largest raster up to 512 px wide (plenty for a phone, and keeps the app small).
    def width(f): return int(f["sizes"].split("x")[0])
    pick = sorted((f for f in raster if width(f) <= 512), key=width)[-1] if any(width(f) <= 512 for f in raster) else raster[-1]
    return {"url": pick["href"], "license": licence_name(lic), "licenseURL": lic,
            "author": image.get("attribution") or image["_links"].get("contributor", {}).get("title", "Unknown"),
            "page": "https://www.phylopic.org" + image["_links"]["self"]["href"].split("?")[0],
            "taxon": image["_links"].get("specificNode", {}).get("title", "")}

def find(build, sci):
    words = sci.split()
    candidates = [sci] if len(words) > 1 else []
    candidates.append(words[0])
    for name in candidates:
        node = node_by_name(build, name)
        if not node: continue
        hit = usable(node.get("_embedded", {}).get("primaryImage"))
        if hit: return hit, ("species" if name == sci and len(words) > 1 else "genus")
        # Walk up the lineage a few steps for the nearest relative with a usable silhouette.
        uuid = node["_links"]["self"]["href"].split("/nodes/")[1].split("?")[0]
        q = urllib.parse.urlencode({"build": build, "embed_items": "true", "embed_primaryImage": "true", "page": 0})
        lin = get(f"{API}/nodes/{uuid}/lineage?{q}")
        for step, anc in enumerate(((lin or {}).get("_embedded") or {}).get("items", [])[1:MAX_STEPS_UP + 1], 1):
            hit = usable(anc.get("_embedded", {}).get("primaryImage"))
            if hit: return hit, f"relative ({anc['names'][0][0]['text'] if anc.get('names') else '?'})"
        return None, "no usable image near " + name
    return None, "not on PhyloPic"

def main():
    from concurrent.futures import ThreadPoolExecutor
    refresh = "--refresh" in sys.argv
    animals = json.loads((RES / "animals.json").read_text())
    path = RES / "silhouettes.json"
    credits = json.loads(path.read_text()) if path.exists() and not refresh else {}
    OUT.mkdir(parents=True, exist_ok=True)
    build = get(API + "/")["build"]
    todo = [a for a in animals if not (a["id"] in credits and (OUT / f"sil-{a['id']}.png").exists())]

    def one(a):
        hit, how = find(build, a["scientificName"])
        if not hit and a["id"] in STAND_INS:
            hit, how2 = find(build, STAND_INS[a["id"]])
            how = f"stand-in ({STAND_INS[a['id']]})" if hit else how
        if not hit: return a["id"], None, f"{a['scientificName']}: {how}"
        png = get(hit.pop("url"), raw=True)
        if not png: return a["id"], None, "download failed"
        (OUT / f"sil-{a['id']}.png").write_bytes(png)
        hit["match"] = how
        return a["id"], hit, None

    missing = []
    with ThreadPoolExecutor(max_workers=6) as pool:
        for aid, hit, err in pool.map(one, todo):
            if hit:
                credits[aid] = hit
                path.write_text(json.dumps(credits, ensure_ascii=False, indent=1, sort_keys=True) + "\n")
                print(f"ok  {aid:32} {hit['match'][:28]:28} {hit['license']:12} {hit['author'][:30]}", flush=True)
            else:
                missing.append(f"{aid}: {err}")
    known = {a["id"] for a in animals}
    credits = {k: v for k, v in credits.items() if k in known}
    path.write_text(json.dumps(credits, ensure_ascii=False, indent=1, sort_keys=True) + "\n")
    print(f"{len(credits)}/{len(animals)} silhouettes")
    for m in missing: print("MISSING", m)

main()
