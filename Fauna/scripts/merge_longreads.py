#!/usr/bin/env python3
"""Merges scripts/longreads/*.json ({id: {anatomy, family, people}}) into animals.json."""
import json
from pathlib import Path
root = Path(__file__).resolve().parent.parent
path = root / "Fauna/Resources/animals.json"
animals = json.loads(path.read_text())
extra = {}
for f in sorted((root / "scripts/longreads").glob("*.json")):
    extra.update(json.loads(f.read_text()))
order = ["id", "name", "scientificName", "wikipediaTitle", "group", "regions", "range", "status", "coordinate",
         "mapSpan", "tagline", "lede", "home", "anatomy", "life", "family", "remarkable", "outlook", "people",
         "didYouKnow", "facts", "quiz", "charities"]
out = []
for a in animals:
    a.update(extra.get(a["id"], {}))
    out.append({k: a[k] for k in order if k in a})
path.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n")
print(f"merged {len(extra)} long reads; {sum(1 for a in out if 'anatomy' in a)}/{len(out)} animals have them")
