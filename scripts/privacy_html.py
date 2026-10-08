#!/usr/bin/env python3
"""Regenerates docs/privacy.html from FourTrack/UI/PrivacyPolicyView.swift."""
import html, pathlib, re

root = pathlib.Path(__file__).resolve().parent.parent
src = (root / "FourTrack/UI/PrivacyPolicyView.swift").read_text()
date = re.search(r'lastUpdated = "([^"]+)"', src).group(1)
pairs = re.findall(r'\("([^"]+)",\s*"((?:[^"\\]|\\.)*)"\)', src)
body = "\n".join(f"<h2>{html.escape(t)}</h2>\n<p>{html.escape(b)}</p>" for t, b in pairs)
template = (root / "docs/privacy.html").read_text()
head = template.split("<h1>")[0]
page = f'{head}<h1>Four-Track Privacy Policy</h1>\n<p class="date">Last updated {html.escape(date)}</p>\n{body}\n</body>\n</html>\n'
(root / "docs/privacy.html").write_text(page)
print("docs/privacy.html updated")
