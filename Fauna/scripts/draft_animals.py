#!/usr/bin/env python3
"""Drafts new Fauna animals from their Wikipedia articles with the Claude API.

    ANTHROPIC_API_KEY=... python3 scripts/draft_animals.py --count 25

1. Asks Claude for candidate species that Fauna doesn't have yet, weighted towards the kinds
   of animals and places the library is short of.
2. Keeps only candidates whose Wikipedia article exists and has a freely licensed lead photo
   on Wikimedia Commons (the app can't show anything else).
3. For each, sends the article's full text and asks for one entry in Fauna's format, written
   only from that article. Structured output guarantees the shape.
4. Checks every draft the same way the library is checked (length, repeated facts, quiz
   structure, units, a charity link that actually loads) and gives Claude one chance to fix
   anything that fails.

Drafts are written to scripts/new_animals/drafts/ and nothing goes live until they are moved
into scripts/new_animals/ and merged with add_animals.py, after review.
"""
import argparse, concurrent.futures, datetime, json, re, sys, time, urllib.error, urllib.parse, urllib.request
from collections import Counter
from pathlib import Path

import anthropic

ROOT = Path(__file__).resolve().parent.parent
LIBRARY = ROOT / "Fauna/Resources/animals.json"
DRAFTS = ROOT / "scripts/new_animals/drafts"
NEW = ROOT / "scripts/new_animals"
UA = {"User-Agent": "Fauna/1.0 (content drafting script; https://github.com/thomasragosta1/Mixer)"}

MODEL = "claude-opus-5-5"
FALLBACK_BETA = "server-side-fallback-2026-07-01"

GROUPS = ["mammal", "bird", "reptile", "amphibian", "fish", "insect", "marineInvertebrate"]
REGIONS = {
    "arctic": "the Arctic, including the far north of Canada, Alaska, Greenland, Scandinavia and Russia",
    "naEast": "eastern North America: eastern Canada (Ontario, Quebec, the Maritimes, Newfoundland) and the eastern United States",
    "naWest": "western North America: western Canada and the western United States",
    "centralAmerica": "Mexico, Central America and the Caribbean",
    "southAmerica": "South America",
    "europe": "Europe",
    "africa": "Africa and Madagascar",
    "asia": "Asia, including the Middle East and Southeast Asia",
    "oceania": "Australia, New Zealand, New Guinea and the Pacific islands",
    "antarctica": "Antarctica and the Southern Ocean",
    "openOcean": "the open ocean and deep sea, for wide-ranging marine animals",
}
STATUSES = ["LC", "NT", "VU", "EN", "CR", "EW", "EX", "DD", "NE"]
# The mix Fauna aims for once it reaches 365 animals.
TARGET_SHARE = {"mammal": .24, "bird": .20, "insect": .13, "marineInvertebrate": .12,
                "fish": .12, "reptile": .10, "amphibian": .09}
SECTIONS = ["lede", "home", "anatomy", "life", "family", "remarkable", "outlook", "people", "relatives"]

# ---------------------------------------------------------------------------------------------
# Wikipedia

def http_json(url, tries=5):
    for i in range(tries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            if e.code in (429, 500, 502, 503, 504) and i < tries - 1:
                time.sleep(2 ** i); continue
            return None
        except (urllib.error.URLError, TimeoutError):
            if i < tries - 1:
                time.sleep(2 ** i); continue
            return None

def wikipedia(title):
    """Canonical title, plain-text article and whether it has a Commons lead photo."""
    path = urllib.parse.quote(title.replace(" ", "_"), safe="")
    summary = http_json(f"https://en.wikipedia.org/api/rest_v1/page/summary/{path}")
    if not summary or summary.get("type") != "standard":
        return None
    canonical = summary.get("titles", {}).get("normalized") or summary.get("title") or title
    lead = (summary.get("originalimage") or {}).get("source", "")
    q = urllib.parse.urlencode({"action": "query", "format": "json", "formatversion": 2, "prop": "extracts",
                                "explaintext": 1, "redirects": 1, "titles": canonical})
    data = http_json(f"https://en.wikipedia.org/w/api.php?{q}")
    pages = (data or {}).get("query", {}).get("pages", [])
    text = pages[0].get("extract", "") if pages else ""
    # Drop reference-only sections at the end.
    text = re.split(r"\n==+ (See also|References|Notes|Further reading|External links|Bibliography) ==+\n", text)[0]
    return {"title": canonical, "text": text.strip(), "commons_photo": "/wikipedia/commons/" in lead}

def link_works(url):
    try:
        req = urllib.request.Request(url, headers={**UA, "Accept": "text/html"}, method="GET")
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.status < 400
    except urllib.error.HTTPError as e:
        # Some charity sites refuse scripts (403) but load fine in a browser.
        return e.code in (401, 403, 429)
    except Exception:
        return False

# ---------------------------------------------------------------------------------------------
# Claude

client = anthropic.Anthropic()

def ask(system, messages, schema, max_tokens=32000):
    """One structured request on Claude Opus 5.5, falling back to Anthropic's recommended model
    if a safety classifier declines. Returns (parsed JSON or None, full assistant content)."""
    with client.beta.messages.stream(
        model=MODEL,
        max_tokens=max_tokens,
        betas=[FALLBACK_BETA],
        fallbacks="default",
        system=[{"type": "text", "text": system, "cache_control": {"type": "ephemeral"}}],
        messages=messages,
        output_config={"effort": "high", "format": {"type": "json_schema", "schema": schema}},
    ) as stream:
        message = stream.get_final_message()
    if message.stop_reason in ("refusal", "max_tokens"):
        return None, message.content
    text = next((b.text for b in message.content if b.type == "text"), "")
    try:
        return json.loads(text), message.content
    except json.JSONDecodeError:
        return None, message.content

def obj(props, required=None):
    return {"type": "object", "properties": props, "required": required or list(props), "additionalProperties": False}

STR = {"type": "string"}
ANIMAL_SCHEMA = obj({
    "id": STR, "name": STR, "scientificName": STR, "wikipediaTitle": STR,
    "group": {"type": "string", "enum": GROUPS},
    "regions": {"type": "array", "items": {"type": "string", "enum": list(REGIONS)}},
    "range": STR,
    "status": {"type": "string", "enum": STATUSES},
    "coordinate": obj({"latitude": {"type": "number"}, "longitude": {"type": "number"}}),
    "mapSpan": {"type": "number"},
    "tagline": STR, "lede": STR, "home": STR, "anatomy": STR, "life": STR, "family": STR,
    "remarkable": STR, "outlook": STR, "people": STR, "relatives": STR, "didYouKnow": STR,
    "facts": {"type": "array", "items": obj({"label": STR, "value": STR})},
    "quiz": {"type": "array", "items": obj({"prompt": STR, "choices": {"type": "array", "items": STR}, "explanation": STR})},
    "charities": {"type": "array", "items": obj({"name": STR, "url": STR, "blurb": STR})},
})
CANDIDATES_SCHEMA = obj({"candidates": {"type": "array", "items": obj({
    "name": STR, "wikipediaTitle": STR, "group": {"type": "string", "enum": GROUPS}, "why": STR})}})

def style_guide(example):
    regions = "\n".join(f"- {k}: {v}" for k, v in REGIONS.items())
    return f"""You write entries for Fauna, an iPhone app that introduces one remarkable animal a day. Each entry is a condensed, adapted version of the animal's English Wikipedia article (shared under CC BY-SA, credited in the app). Readers are curious adults reading for about four minutes; afterwards they must pass a three-question quiz to unlock the next animal.

Write only from the Wikipedia article you're given. Don't add facts from memory, and don't guess numbers. If the article doesn't support a claim, leave it out.

Voice: warm, vivid and plain, like a good science magazine. Short paragraphs. Explain any term a curious reader might not know the first time it appears (a reader once had to stop and ask "What is Nahuatl?"). British spelling (colour, metres). Measurements in metric with digits ("3 metres", "40 kg", "up to 1,200 m"); the app converts them for American readers, so never write numbers as words next to a unit.

Fields:
- id: lowercase kebab-case common name, e.g. "snow-leopard".
- name: common name in title case. scientificName: binomial. wikipediaTitle: exactly the title you were given.
- group, regions, status: from the article. Regions (use every one that applies to its native range):
{regions}
- range: one short line, e.g. "Himalayas, from Nepal to southwest China".
- coordinate: roughly the centre of its native range. mapSpan: latitude span in degrees for a map of that range (small for an island species, large for an ocean wanderer).
- tagline: under 60 characters, no full stop, intriguing rather than descriptive.
- lede: 2-3 sentences that make someone want to read on.
- home, anatomy, life, family, remarkable, people, relatives, outlook: the article's sections. Separate paragraphs with a blank line ("\\n\\n"). people is how humans have known, used, studied or protected it; relatives is its family tree and closest kin; outlook is its conservation status and what threatens or helps it.
- didYouKnow: one surprising fact that appears nowhere else in the entry.
- facts: exactly 4 short label/value pairs (e.g. Length, Weight, Lifespan, Diet).
- quiz: exactly 3 questions, each answerable from this entry alone, about memorable facts rather than trivia. Each has 4 distinct choices with the correct answer first (the app shuffles them) and a one-sentence explanation. Make wrong answers plausible and similar in length to the right one; across the three questions the right answer should not consistently be the longest or most detailed choice.
- charities: 1-2 real conservation organisations that work on this species, its close relatives or its habitat, with their real homepage URL (https). blurb: one sentence on what they do.

The whole entry (lede through relatives) should be 700-950 words. State each fact once: never repeat a fact in a second section, and don't let the lede, remarkable or didYouKnow restate what another section says.

Here is an existing entry, for format and tone:
{json.dumps(example, ensure_ascii=False, indent=1)}"""

# ---------------------------------------------------------------------------------------------
# Checks (mirroring validate_content.py)

STOP = set("the a an and or of to in on at for with by from as is are was were be been its it their they this that these those which who can may also than then into over about up out only more most some many much very such not no but if so all each other one two three has have had do does it's just even like around while when where how what why there here because".split())

def keywords(s):
    return {w for w in re.findall(r"[a-z0-9]+", s.lower()) if w not in STOP and len(w) > 2}

NUMBER_WORDS = r"\b(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|twenty|thirty|forty|fifty|hundred)\s+(metres?|kilometres?|centimetres?|millimetres?|grams?|kilograms?|tonnes?)\b"

def problems(a, known_ids):
    out = []
    if a["id"] in known_ids: out.append(f"id '{a['id']}' is already used")
    if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", a["id"]): out.append("id must be lowercase kebab-case")
    words = sum(len(a[k].split()) for k in SECTIONS)
    if not 650 <= words <= 1100: out.append(f"the entry is {words} words; it should be 700-950")
    if len(a["tagline"]) > 60 or a["tagline"].endswith("."): out.append("tagline must be under 60 characters with no full stop")
    if not a["regions"]: out.append("regions is empty")
    if len(a["facts"]) != 4: out.append("facts must have exactly 4 items")
    if len(a["quiz"]) != 3: out.append("quiz must have exactly 3 questions")
    for q in a["quiz"]:
        if len(q["choices"]) != 4 or len({c.lower() for c in q["choices"]}) != 4:
            out.append(f"question '{q['prompt']}' needs 4 distinct choices")
        if not q["prompt"].strip().endswith("?"): out.append(f"'{q['prompt']}' should be a question")
    longest = sum(1 for q in a["quiz"] if len(q["choices"]) == 4 and len(q["choices"][0]) > max(map(len, q["choices"][1:])))
    if longest == 3: out.append("the right answer is the longest choice in all three questions; vary the wrong answers' length")
    if not 1 <= len(a["charities"]) <= 2: out.append("give 1 or 2 charities")
    for c in a["charities"]:
        if not c["url"].startswith("https://"): out.append(f"{c['name']}: url must start with https://")
        elif not link_works(c["url"]): out.append(f"{c['name']}: {c['url']} doesn't load; use the organisation's real homepage, or a different organisation")
    text = " ".join(a[k] for k in SECTIONS + ["didYouKnow"])
    if re.search(NUMBER_WORDS, text, re.I): out.append("write measurements with digits, e.g. '7 metres', not 'seven metres'")
    if "  " in text: out.append("remove double spaces")
    sents = [(k, s) for k in SECTIONS + ["didYouKnow"]
             for s in re.split(r"(?<=[.!?])\s+", a[k].replace("\n\n", " ")) if len(s.split()) >= 5]
    for i in range(len(sents)):
        for j in range(i + 1, len(sents)):
            wi, wj = keywords(sents[i][1]), keywords(sents[j][1])
            shared = wi & wj
            if wi and wj and len(shared) >= 5 and len(shared) / min(len(wi), len(wj)) >= 0.7:
                out.append(f"repeated fact: [{sents[i][0]}] \"{sents[i][1]}\" and [{sents[j][0]}] \"{sents[j][1]}\"")
    return out

# ---------------------------------------------------------------------------------------------

def propose(count, library, drafted):
    groups = Counter(a["group"] for a in library)
    regions = Counter(r for a in library for r in a["regions"])
    want = {g: max(0, round(TARGET_SHARE[g] * 365) - groups[g]) for g in GROUPS}
    have = sorted({a["name"] for a in library} | {d["name"] for d in drafted})
    prompt = f"""Suggest {count} animal species to add to Fauna. Fauna already has: {", ".join(have)}.

Favour remarkable, lesser-known animals with good stories, mixed with a few famous ones the library lacks. Each must be a single species (or a well-known species group with its own Wikipedia article) with a substantial English Wikipedia article.

The library currently has {dict(groups)} by kind and {dict(regions)} by region. Roughly how many more of each kind it needs: {want}. Spread suggestions across regions too, including plenty from eastern and western North America (especially Canada), and some from places the library has few of.

For each, give the exact English Wikipedia article title."""
    data, _ = ask("You help curate the animal library for Fauna, an app that introduces one remarkable animal a day.",
                  [{"role": "user", "content": prompt}], CANDIDATES_SCHEMA, max_tokens=16000)
    return (data or {}).get("candidates", [])

def draft(candidate, example, known_ids, known_titles):
    wiki = wikipedia(candidate["wikipediaTitle"])
    if not wiki:
        return None, f"{candidate['wikipediaTitle']}: no Wikipedia article"
    if wiki["title"].lower() in known_titles:
        return None, f"{wiki['title']}: already in Fauna"
    if not wiki["commons_photo"]:
        return None, f"{wiki['title']}: no freely licensed lead photo"
    if len(wiki["text"].split()) < 1200:
        return None, f"{wiki['title']}: article too short to write a full entry from"
    messages = [{"role": "user", "content": f"Write the Fauna entry for the Wikipedia article \"{wiki['title']}\".\n\n<article>\n{wiki['text']}\n</article>"}]
    system = style_guide(example)
    for attempt in range(2):
        animal, content = ask(system, messages, ANIMAL_SCHEMA)
        if animal is None:
            return None, f"{wiki['title']}: no usable response (declined or cut off)"
        animal["wikipediaTitle"] = wiki["title"]
        issues = problems(animal, known_ids)
        if not issues:
            return animal, None
        if attempt == 0:
            messages += [{"role": "assistant", "content": content},
                         {"role": "user", "content": "Please fix these problems and return the whole entry again:\n- " + "\n- ".join(issues)}]
    return None, f"{wiki['title']}: still failing checks: " + "; ".join(issues)

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--count", type=int, default=25)
    p.add_argument("--workers", type=int, default=4)
    args = p.parse_args()
    if args.count <= 0:
        print("Count is 0: nothing to draft."); return

    library = json.loads(LIBRARY.read_text())
    drafted = [d for f in sorted(DRAFTS.glob("*.json")) for d in json.loads(f.read_text())] if DRAFTS.exists() else []
    drafted += [d for f in sorted(NEW.glob("*.json")) for d in json.loads(f.read_text())]
    known_ids = {a["id"] for a in library} | {d["id"] for d in drafted}
    known_titles = {a["wikipediaTitle"].lower() for a in library} | {d["wikipediaTitle"].lower() for d in drafted}
    example = next(a for a in library if a["id"] == "red-panda")

    # Ask for extras: some candidates won't have a usable article or photo.
    candidates = [c for c in propose(int(args.count * 1.5) + 5, library, drafted)
                  if c["wikipediaTitle"].lower() not in known_titles]
    print(f"{len(candidates)} candidates")

    results, skipped = [], []
    with concurrent.futures.ThreadPoolExecutor(args.workers) as pool:
        futures = {}
        queue = iter(candidates)
        def submit():
            c = next(queue, None)
            if c: futures[pool.submit(draft, c, example, known_ids, known_titles)] = c
        for _ in range(args.workers): submit()
        while futures:
            done = next(concurrent.futures.as_completed(futures))
            futures.pop(done)
            animal, reason = done.result()
            if animal and animal["id"] not in {r["id"] for r in results} and len(results) < args.count:
                results.append(animal); print(f"  drafted {animal['name']} ({len(results)}/{args.count})")
            elif reason:
                skipped.append(reason); print(f"  skipped {reason}")
            if len(results) < args.count: submit()

    if not results:
        print("Nothing drafted."); sys.exit(1)
    DRAFTS.mkdir(parents=True, exist_ok=True)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d-%H%M")
    out = DRAFTS / f"batch-{stamp}.json"
    out.write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n")
    report = [f"# Draft batch {stamp}", "", f"{len(results)} animals drafted with {MODEL}.", ""]
    report += [f"- **{a['name']}** ({a['group']}; {', '.join(a['regions'])}; {a['status']}): {a['tagline']}" for a in results]
    if skipped:
        report += ["", "Skipped:", ""] + [f"- {s}" for s in skipped]
    out.with_suffix(".md").write_text("\n".join(report) + "\n")
    print(f"Wrote {out.relative_to(ROOT)}")

if __name__ == "__main__":
    main()
