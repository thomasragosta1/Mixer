#!/usr/bin/env python3
"""Applies the repeat-removal edits in scripts/dedupe/edits_*.py to animals.json.
Each edit is (id, section, exact old text, replacement); an empty replacement deletes the
sentence, and an empty old text appends the replacement as a new paragraph. Prints the edited paragraph so each change can be read in context."""
import json, glob, importlib.util, re, sys
from pathlib import Path
root = Path(__file__).resolve().parents[2]
path = root / "Fauna/Resources/animals.json"
animals = json.loads(path.read_text()); by = {a["id"]: a for a in animals}
only = sys.argv[1:]  # optional: edit files to apply
bad = 0
for f in sorted(glob.glob(str(root / "scripts/dedupe/edits_*.py"))):
    if only and Path(f).name not in only: continue
    spec = importlib.util.spec_from_file_location("e", f); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    for aid, sec, old, new in m.E:
        text = by[aid][sec]
        if old == "":  # append a new paragraph
            if new in text: continue
            by[aid][sec] = text.rstrip() + "\n\n" + new
            print(f"++ {aid}.{sec}: {new[:70]}")
            continue
        if old not in text:
            if new and new in text: continue  # already applied
            print(f"!! {aid}.{sec}: not found: {old[:70]}"); bad += 1; continue
        text = text.replace(old, new, 1)
        # Tidy spacing left by deletions, keeping paragraph breaks.
        text = "\n\n".join(re.sub(r"[ \t]{2,}", " ", p).strip() for p in text.split("\n\n") if p.strip())
        by[aid][sec] = text
        para = next((p for p in text.split("\n\n") if (new and new in p)), None)
        print(f"-- {aid}.{sec}: " + (para if para else "(deleted) " + old[:60]))
path.write_text(json.dumps(animals, ensure_ascii=False, indent=2) + "\n")
print("failed:", bad)
