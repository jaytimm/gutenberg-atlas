# Full build, step 18: match validation-sample titles to Wikidata works
# (P50 author = our QID, with P577 publication date) from
# data/wikidata_works.csv. Cross-check only; not used by script 16.
# Run from build/: python3 -I 18-match-wikidata-works.py

import csv, re, unicodedata

def norm(s):
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    return [w for w in re.sub(r"[^a-z0-9 ]", " ", s.lower()).split() if w not in ("the","a","an")]

def short(t):
    t = t.split("\n")[0].split("\r")[0]
    t = re.split(r"\s*[;:—]\s*|,\s*or,?\s+|\s+—\s+", t)[0]
    return re.split(r",?\s*\b(vol\.?|volume|part)\b", t, flags=re.I)[0].strip(" ,.")

works = {}
for r in csv.DictReader(open("data/wikidata_works.csv")):
    works.setdefault(r["author"].rsplit("/",1)[1], []).append(r)
out = []
truth = {}
for r in csv.DictReader(open("data/validation_handcheck.csv")):
    truth[r["pg_id"]] = r
    w = norm(short(r["title"])); best = None
    for x in works.get(r["qid"], []):
        g = norm(x["workLabel"])
        n = min(len(w), len(g))
        title_match = (
            n >= 2 and (g[:len(w)] == w or w[:len(g)] == g)
        ) or (n == 1 and g == w)
        if title_match:
            y = int(x["year"])
            if best is None or y < best[0]: best = (y, x["work"], x["workLabel"])
    out.append({"pg_id": r["pg_id"], "wd_work_year": best[0] if best else "",
                "wd_work_url": best[1] if best else "", "wd_work_label": best[2] if best else ""})
with open("data/validation_wdworks.csv", "w", newline="") as f:
    wr = csv.DictWriter(f, fieldnames=list(out[0])); wr.writeheader(); wr.writerows(out)

matched = [o for o in out if o["wd_work_year"]]
judged = [
    o for o in matched
    if truth[o["pg_id"]]["true_year"]
    and truth[o["pg_id"]]["confidence"] != "ambiguous"
]
exact = sum(
    int(o["wd_work_year"]) == int(truth[o["pg_id"]]["true_year"])
    for o in judged
)
close = sum(
    abs(int(o["wd_work_year"]) - int(truth[o["pg_id"]]["true_year"])) <= 1
    for o in judged
)
print(len(matched), "of", len(out), "matched")
print(f"vs sourced truth: exact {exact}/{len(judged)}; +/-1 year {close}/{len(judged)}")
