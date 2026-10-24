# Full build, step 17: gather independent first-publication evidence for
# the validation sample, from the Library of Congress catalogue, Wikipedia
# infoboxes, and Open Library (weak; often reports reprint years).
# Output is evidence for hand adjudication, not a decision.
# Run from build/: python3 -I 17-gather-evidence.py

import csv, json, re, sys, time, unicodedata, urllib.parse, urllib.request

UA = "Gutenberg-Atlas-validation/0.1 (jtimm@unm.edu)"
SHEET = "data/validation_handcheck.csv"
OUT = "data/validation_evidence.csv"


def get_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=40) as r:
                return json.load(r)
        except Exception:
            time.sleep(3 * (attempt + 1))
    return None


def norm(s):
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9 ]", " ", s.lower()).split()


def short_title(t):
    t = t.split("\n")[0].split("\r")[0]
    t = re.split(r"\s*[;:—]\s*|,\s*or,?\s+|\s+—\s+", t)[0]
    t = re.split(r",?\s*\b(vol\.?|volume|part)\b", t, flags=re.I)[0]
    return t.strip(" ,.")


def surname(authors):
    return norm(authors.split(",")[0])[-1] if authors else ""


def title_ok(want, got):
    w, g = norm(want), norm(got)
    w = [x for x in w if x not in ("the", "a", "an")]
    g = [x for x in g if x not in ("the", "a", "an")]
    return len(w) > 0 and g[:len(w)] == w


def loc(title, sur):
    q = urllib.parse.quote_plus(f"{title} {sur}")
    d = get_json(f"https://www.loc.gov/books/?q={q}&fo=json&c=50")
    hits = []
    for x in (d or {}).get("results", []):
        contrib = " ".join(x.get("contributor") or [])
        if sur and sur not in norm(contrib):
            continue
        if not title_ok(title, x.get("title", "")):
            continue
        y = re.search(r"\b(1[5-9]\d\d|20[0-2]\d)\b", str(x.get("date", "")))
        if y:
            hits.append((int(y.group(1)), x.get("id", "")))
    hits.sort()
    return hits


def wikipedia(title, sur):
    q = urllib.parse.quote(f'"{title}" {sur}')
    d = get_json("https://en.wikipedia.org/w/api.php?action=query&list=search"
                 f"&srsearch={q}&srlimit=3&format=json&formatversion=2")
    for hit in (d or {}).get("query", {}).get("search", []):
        if not title_ok(title, re.sub(r"\s*\(.*\)$", "", hit["title"])):
            continue
        p = get_json("https://en.wikipedia.org/w/api.php?action=query"
                     "&prop=revisions&rvprop=content&rvslots=main&rvsection=0"
                     "&format=json&formatversion=2&titles="
                     + urllib.parse.quote(hit["title"]))
        try:
            txt = p["query"]["pages"][0]["revisions"][0]["slots"]["main"]["content"]
        except (TypeError, KeyError, IndexError):
            continue
        if sur not in norm(txt):
            continue
        m = re.search(r"\|\s*(pub_date|release_date|published)\s*=([^\n]*)", txt)
        y = re.search(r"\b(1[5-9]\d\d|20[0-2]\d)\b", m.group(2)) if m else None
        if y:
            url = "https://en.wikipedia.org/wiki/" + hit["title"].replace(" ", "_")
            return int(y.group(1)), url
    return None, ""


def openlibrary(title, sur):
    q = urllib.parse.urlencode({"title": title, "author": sur,
                                "fields": "title,first_publish_year", "limit": 5})
    d = get_json(f"https://openlibrary.org/search.json?{q}")
    ys = [x["first_publish_year"] for x in (d or {}).get("docs", [])
          if x.get("first_publish_year") and title_ok(title, x.get("title", ""))]
    return min(ys) if ys else None


rows = list(csv.DictReader(open(SHEET, encoding="utf-8")))
if len(sys.argv) > 1:  # optional row limit for testing
    rows = rows[:int(sys.argv[1])]
    OUT = OUT.replace(".csv", "_test.csv")
out = []
for i, r in enumerate(rows, 1):
    t, s = short_title(r["title"]), surname(r["authors"])
    lh = loc(t, s); time.sleep(1)
    wy, wu = wikipedia(t, s); time.sleep(0.5)
    oy = openlibrary(t, s); time.sleep(0.6)
    out.append({
        "pg_id": r["pg_id"], "short_title": t, "surname": s,
        "ht_year": r["ht_year"],
        "loc_year": lh[0][0] if lh else "", "loc_url": lh[0][1] if lh else "",
        "loc_years": " ".join(str(y) for y, _ in lh[:8]),
        "wiki_year": wy or "", "wiki_url": wu, "ol_year": oy or ""})
    if i % 20 == 0:
        print(f"  {i}/{len(rows)}", flush=True)

with open(OUT, "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=list(out[0]))
    w.writeheader(); w.writerows(out)
print(f"Wrote {OUT}: LoC {sum(1 for o in out if o['loc_year'])}, "
      f"Wikipedia {sum(1 for o in out if o['wiki_year'])}, "
      f"Open Library {sum(1 for o in out if o['ol_year'])} of {len(out)}")
