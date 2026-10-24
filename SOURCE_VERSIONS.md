# Source versions

Frozen for the 2026-10-24 Gutenberg Atlas release.

## Project Gutenberg

- Local catalog: `data-raw/pg_catalog.csv`
- Source: Project Gutenberg RDF catalog extraction
- Local snapshot written: 2026-10-20
- Catalog records: 79,634
- SHA-256:
  `3d402f23786a990140d990fe6946c3575b2fcdd7cffb31fd47769a78663d8c73`

## HathiTrust

- Local filtered snapshot: `data-raw/hathi_eng_books.tsv`
- Upstream file: `hathi_full_20261001`
- Filter: English (`eng`) books (`BK`), retaining HathiTrust ID, title,
  imprint, rights date, and author
- Filtered records: 6,483,677
- SHA-256:
  `9a1824ef6906f655052a7ac3212c438d5fc9777bfbdd27f34eb8366b8f4fbbb4`

## Wikidata

- Retrieved: 2026-10-21
- Endpoint: `https://query.wikidata.org/sparql`
- Linkage: Project Gutenberg agent ID (P1938)
- Entity constraint: human (P31=Q5)
- Fields: gender (P21), country of citizenship (P27), birth (P569), death
  (P570)
- Resolved human agents: 9,493 of 15,741 queried
- Frozen result: `build/data/wikidata_authors.csv`
- SHA-256:
  `2cecbed1b925e358bbdbee6992fad429a041996c771a322de8572b12420c2e82`

Wikidata values are a dated snapshot of structured claims. Refreshing the
query can change coverage or values and therefore constitutes a new dataset
version.
