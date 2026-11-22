#!/usr/bin/env python3
"""Appends animals from scripts/new_animals/*.json (lists of full entries) to animals.json,
skipping ids that already exist, then re-runs paragraph splitting."""
import json, subprocess, sys
from pathlib import Path
root = Path(__file__).resolve().parent.parent
path = root / "Fauna/Resources/animals.json"
animals = json.loads(path.read_text())
have = {a["id"] for a in animals}
added = 0
for f in sorted((root / "scripts/new_animals").glob("*.json")):
    for a in json.loads(f.read_text()):
        if a["id"] not in have:
            animals.append(a); have.add(a["id"]); added += 1
# Extensions: {id: {field: "paragraph to append"}}, applied once.
byid = {a["id"]: a for a in animals}
extended = 0
for f in sorted((root / "scripts/extensions").glob("*.json")):
    for aid, fields in json.loads(f.read_text()).items():
        for field, text in fields.items():
            a = byid[aid]
            flat = " ".join(a.get(field, "").split())
            if " ".join(text.split()) not in flat:
                a[field] = (a.get(field, "").rstrip() + "\n\n" + text).strip()
                extended += 1
path.write_text(json.dumps(animals, ensure_ascii=False, indent=2) + "\n")
print(f"added {added}, extended {extended} sections; library now {len(animals)} animals")
subprocess.run([sys.executable, str(root / "scripts/paragraphs.py")], check=True)
