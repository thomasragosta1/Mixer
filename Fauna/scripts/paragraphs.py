#!/usr/bin/env python3
"""Splits long article sections into short paragraphs (separated by a blank line) at the
sentence boundaries that best balance length and start a new thought. Re-running re-flows and re-splits, so it is safe to tune and run again."""
import json, re, sys
from pathlib import Path

FIELDS = ["home", "anatomy", "life", "family", "remarkable", "outlook", "people", "relatives"]
CUES = ("Today", "Unlike", "Despite", "Since", "Because", "But", "However", "Scientists", "Researchers",
        "In the ", "In recent", "In some", "In 19", "In 20", "During", "After", "When", "Later", "Over ",
        "For ", "Instead", "Like ", "Its ", "Their ", "Young", "Fossils", "Genetic", "Conservation",
        "Surprisingly", "Even ", "Once", "By ", "As ", "At ", "On ", "Most ", "Many ", "Some ", "Another",
        "Females", "Males", "Adults", "The young", "Each ", "Every ", "This ")

def sentences(text):
    # split after . ! ? followed by space and a capital letter or quote (keeps "e.g." style intact)
    parts = re.split(r"(?<=[.!?])\s+(?=[A-Z‘'\"“])", text.strip())
    return [p for p in parts if p]

def split(text):
    text = " ".join(text.split("\n\n"))  # re-flow, so thresholds can be tuned
    sents = sentences(text)
    words = [len(s.split()) for s in sents]
    total = sum(words)
    if total < 40 or len(sents) < 3:
        return text
    pieces = 3 if total > 125 and len(sents) >= 6 else 2
    cuts = []
    for k in range(1, pieces):
        target = total * k / pieces
        best, best_score = None, None
        run = 0
        for i in range(1, len(sents)):
            run += words[i - 1]
            if i in cuts or (cuts and i <= cuts[-1] + 1):
                continue
            if run < 14 or total - run < 14:
                continue
            score = abs(run - target) / total
            if sents[i].startswith(CUES):
                score -= 0.12
            if best_score is None or score < best_score:
                best, best_score = i, score
        if best is not None:
            cuts.append(best)
    if not cuts:
        return text
    paras, start = [], 0
    for c in cuts + [len(sents)]:
        paras.append(" ".join(sents[start:c]))
        start = c
    return "\n\n".join(paras)

def apply(path):
    data = json.loads(path.read_text())
    items = data if isinstance(data, list) else list(data.values())
    for a in items:
        for f in FIELDS:
            if isinstance(a.get(f), str):
                a[f] = split(a[f])
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")

if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent
    apply(root / "Fauna/Resources/animals.json")
    for p in sorted((root / "scripts/longreads").glob("*.json")):
        apply(p)
    print("done")
