#!/usr/bin/env python3
"""Full build, step 11: PG agent ID (creator) for every eligible book.
Reads the extracted RDF catalog in ~/.cache/pg-rdf/cache/epub/.
Run from build/: python3 11-agents.py
"""
import csv
import os
import re
import sys

RDF_ROOT = os.path.expanduser("~/.cache/pg-rdf/cache/epub")
CREATOR_RE = re.compile(
    r"<dcterms:creator>.*?agents/(\d+)", re.DOTALL)
ANY_AGENT_RE = re.compile(r"agents/(\d+)")

rows = []
missing = 0
with open("data/eligible.csv", newline="", encoding="utf-8") as f:
    eligible = [r["pg_id"] for r in csv.DictReader(f)]

for i, pg_id in enumerate(eligible, 1):
    path = os.path.join(RDF_ROOT, pg_id, f"pg{pg_id}.rdf")
    agent = ""
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        m = CREATOR_RE.search(text)
        if not m:
            m = ANY_AGENT_RE.search(text)
        if m:
            agent = m.group(1)
        else:
            missing += 1
    except FileNotFoundError:
        missing += 1
    rows.append((pg_id, agent))
    if i % 5000 == 0:
        print(f"  {i}/{len(eligible)}", file=sys.stderr)

with open("data/agents.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["pg_id", "agent"])
    w.writerows(rows)

n_with = sum(1 for _, a in rows if a)
print(f"agents found for {n_with}/{len(rows)} books; missing/none: {missing}")
print(f"unique agents: {len({a for _, a in rows if a})}")
