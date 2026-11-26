#!/usr/bin/env python3
"""Checks a batch file before merging: the same rules as validate_content.py (length, repeats,
quiz shape) plus units and quiz-answer balance. Usage: check_batch.py BATCH.json"""
import json, re, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
SECTIONS = ["lede", "home", "anatomy", "life", "family", "remarkable", "outlook", "people", "relatives"]
STOP = set("the a an and or of to in on at for with by from as is are was were be been its it their they this that these those which who can may also than then into over about up out only more most some many much very such not no but if so all each other one two three has have had do does it's just even like around while when where how what why there here because".split())
kw = lambda s: {w for w in re.findall(r"[a-z0-9]+", s.lower()) if w not in STOP and len(w) > 2}
lib = json.loads((ROOT / "Fauna/Resources/animals.json").read_text())
ids = {a["id"] for a in lib}; titles = {a["wikipediaTitle"] for a in lib}
batch = json.loads(Path(sys.argv[1]).read_text())
bad = 0; longest = shortest = n = 0
for a in batch:
    p = []
    if a["id"] in ids: p.append("id exists")
    if a["wikipediaTitle"] in titles: p.append("title exists")
    w = sum(len(a[k].split()) for k in SECTIONS)
    if not 650 <= w <= 1100: p.append(f"{w} words")
    if len(a["tagline"]) > 60 or a["tagline"].endswith("."): p.append("tagline")
    if len(a["facts"]) != 4 or len(a["quiz"]) != 3: p.append("facts/quiz count")
    for q in a["quiz"]:
        c = q["choices"]
        if len(c) != 4 or len(set(c)) != 4: p.append("choices")
        if not q["prompt"].endswith("?"): p.append("prompt ?")
        n += 1; longest += len(c[0]) > max(map(len, c[1:])); shortest += len(c[0]) < min(map(len, c[1:]))
    txt = " ".join(a[k] for k in SECTIONS + ["didYouKnow"])
    if re.search(r"\b(one|two|three|four|five|six|seven|eight|nine|ten|twenty|hundred)\s+(metres?|kilometres?|centimetres?|kilograms?|grams?|tonnes?)\b", txt, re.I): p.append("number words with unit")
    if re.search(r"vaccin", json.dumps(a), re.I): p.append("mentions vaccines")
    if "  " in txt or " ," in txt: p.append("spacing")
    s = [(k, x) for k in SECTIONS + ["didYouKnow"] for x in re.split(r"(?<=[.!?])\s+", a[k].replace("\n\n", " ")) if len(x.split()) >= 5]
    for i in range(len(s)):
        for j in range(i + 1, len(s)):
            A, B = kw(s[i][1]), kw(s[j][1]); sh = A & B
            if A and B and len(sh) >= 5 and len(sh) / min(len(A), len(B)) >= 0.7:
                p.append(f"repeat [{s[i][0]}] {s[i][1][:60]} / [{s[j][0]}] {s[j][1][:60]}")
    print(f"{'OK ' if not p else 'BAD'} {a['name']:28} {w:4} words  {'; '.join(p)}")
    bad += bool(p)
print(f"{len(batch)} animals, {bad} with problems; right answer longest {longest}/{n}, shortest {shortest}/{n}")
