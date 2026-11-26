#!/usr/bin/env python3
"""Checks each candidate in candidates.json has a substantial English Wikipedia article with a
Commons lead photo, saves the article text for writing, and writes plan.json: the species to
add, per group, in order. Usage: python3 verify.py SOURCES_DIR"""
import json, re, sys, time, urllib.error, urllib.parse, urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
UA = {"User-Agent": "Fauna/1.0 (content research; https://github.com/thomasragosta1/Mixer)"}
TARGET = {"mammal": 65, "bird": 61, "insect": 39, "marineInvertebrate": 37, "fish": 39, "reptile": 30, "amphibian": 26}

def get(url):
    for i in range(5):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code == 404: return None
            time.sleep(2 ** i)
        except Exception:
            time.sleep(2 ** i)
    return None

def main():
    out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
    cands = json.loads((HERE / "candidates.json").read_text())
    have = {a["wikipediaTitle"].lower() for a in json.loads((ROOT / "Fauna/Resources/animals.json").read_text())}
    seen, plan, report = set(have), {}, []
    for group, titles in cands.items():
        plan[group] = []
        for t in titles:
            s = get("https://en.wikipedia.org/api/rest_v1/page/summary/" + urllib.parse.quote(t.replace(" ", "_"), safe=""))
            if not s or s.get("type") != "standard":
                report.append(f"MISSING {t}"); continue
            title = s.get("titles", {}).get("normalized") or s["title"]
            if title.lower() in seen:
                report.append(f"DUPLICATE {t} -> {title}"); continue
            commons = "/wikipedia/commons/" in (s.get("originalimage") or {}).get("source", "")
            q = urllib.parse.urlencode({"action": "query", "format": "json", "formatversion": 2, "prop": "extracts",
                                        "explaintext": 1, "redirects": 1, "titles": title})
            d = get("https://en.wikipedia.org/w/api.php?" + q)
            text = ((d or {}).get("query", {}).get("pages") or [{}])[0].get("extract", "")
            text = re.split(r"\n==+ (See also|References|Notes|Further reading|External links|Bibliography|Citations|Sources) ==+\n", text)[0].strip()
            words = len(text.split())
            ok = commons and words >= 1200
            report.append(f"{'OK  ' if ok else 'SKIP'} {group:18} {title} ({words} words, commons={commons})")
            if ok:
                seen.add(title.lower())
                slug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")
                (out / f"{slug}.txt").write_text(f"{title}\n\n{text}\n")
                plan[group].append({"title": title, "slug": slug, "words": words, "description": s.get("description", "")})
            time.sleep(0.2)
    for g in plan: plan[g] = plan[g][:TARGET[g] + 4]
    (HERE / "plan.json").write_text(json.dumps(plan, ensure_ascii=False, indent=1) + "\n")
    print("\n".join(report))
    print({g: len(v) for g, v in plan.items()}, "targets", TARGET)

main()
