#!/usr/bin/env python3
"""Prints a compact digest of a saved Wikipedia article for writing an entry: the
introduction, then the opening of each section, within a word budget.
Usage: brief.py SOURCE.txt [words]"""
import re, sys

SKIP = re.compile(r"etymolog|subspecies|genetics|genome|phylogen|cladogram|parasit|diseases?$|captivity|systematics", re.I)

def main():
    text = open(sys.argv[1]).read()
    budget = int(sys.argv[2]) if len(sys.argv) > 2 else 1100
    parts = re.split(r"\n(=+) (.+?) =+\n", text)
    intro, out = parts[0].strip(), []
    words = intro.split()
    out.append(" ".join(words[:260]))
    used = min(len(words), 260)
    sections = [(parts[i + 1], parts[i + 2].strip()) for i in range(1, len(parts) - 2, 3)]
    sections = [(h, b) for h, b in sections if b and not SKIP.search(h)]
    if not sections:
        print("\n".join(out)); return
    per = max(60, (budget - used) // len(sections))
    for h, b in sections:
        w = b.split()
        take = w[:per]
        out.append(f"[{h}] " + " ".join(take))
        used += len(take)
        if used > budget: break
    print("\n".join(out))

main()
