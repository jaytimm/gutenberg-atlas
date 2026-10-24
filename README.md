# Gutenberg Atlas

Integrated publication history and author metadata for the English-language
Project Gutenberg collection.

Gutenberg Atlas links 21,296 English single-author Project Gutenberg books to
an estimated publication year (from HathiTrust bibliographic records)
and to Wikidata author claims (gender, country of citizenship, birth and death
years) for 7,383 authors. Publication years run from 1700 to 2004. Citizenship
is also mapped to present-day states (`citizenship_modern`). No book texts are
redistributed.

**Dataset DOI:** <https://doi.org/10.5281/zenodo.23628668>

## The release

| File | Contents |
|---|---|
| `build/data/release.csv` | Canonical dataset: one row per released PG book (21,296 rows). |
| `build/data/unverified_candidates.csv` | Eligible books not released, with an exclusion `decision`. |
| `build/data/funnel.csv` | Counts by release/exclusion decision. |
| `build/data/release_summary.csv` | Compact release counts and coverage. |
| `build/data/author_metadata_summary.csv` | Wikidata coverage and PG/Wikidata linkage diagnostics. |
| `build/data/date_validation_summary.csv` | Publication-year accuracy from the validation sample. |
| `build/data/validation_sourced.csv` | Sourced first-publication years for the 200-book validation sample. |

Fields are defined in [`DATA_DICTIONARY.md`](DATA_DICTIONARY.md). File
checksums for the frozen release are in
[`RELEASE_FREEZE.md`](RELEASE_FREEZE.md); upstream source snapshots are in
[`SOURCE_VERSIONS.md`](SOURCE_VERSIONS.md).

## Quality in brief

- Publication year (`ht_year`) is within one year of the sourced reference
  year for an estimated **87.4%** of released books
  (95% CI 82.7–92.1), from a stratified random sample (199 books judged),
  weighted to the full release.
- Accuracy was lower among the 16 sampled books dated 1925 or later (10
  correct); these records remain in the release.
- `date_flag` marks less reliable years (uncertain imprint, multi-volume
  title, one or more than 20 HathiTrust candidates): 35% of the release.
  Flagged books were correct for 80% of sampled cases, unflagged for 90%.
- Author fields are raw Wikidata claims. Coverage and PG/Wikidata lifespan
  agreement are reported; their accuracy is not independently validated.

See `paper/gutenberg-atlas.pdf` and `analysis/supplement.pdf` for details.

## Repository layout

```
build/       Pipeline scripts 10–19 and their outputs (build/data/)
analysis/    Descriptives, reuse experiment, supplement, model results
paper/       Data-paper manuscript and bibliography
data-raw/    Project Gutenberg catalog snapshot (HathiTrust snapshot not tracked)
```

## Rebuilding

Scripts run from `build/` in numeric order:

| Step | Script | Does |
|---|---|---|
| 10 | `10-eligible.R` | Eligible pool of English single-author PG books |
| 11 | `11-agents.py` | PG agent IDs from the PG RDF catalog |
| 12 | `12-match-full.R` | Title/author matching against HathiTrust |
| 13 | `13-wikidata-full.R` | Wikidata author claims via P1938 (network) |
| 14 | `14-decide.R` | Decision rules; release and funnel files |
| 15 | `15-validation-sample.R` | Seeded stratified validation sample |
| 16 | `16-validation-report.R` | Weighted date accuracy |
| 17–18 | `17-gather-evidence.py`, `18-match-wikidata-works.py` | Evidence gathering and cross-checks for validation (network) |
| 19 | `19-author-metadata-report.R` | Author linkage and coverage audit |
| 20 | `20-validation-evidence.R` | Validation source classes and sensitivity estimates |

Inputs not included in this repository:

- `data-raw/hathi_eng_books.tsv` (1.2 GB): English (`eng`) book (`BK`) records
  filtered from the HathiTrust Hathifile `hathi_full_20261001`. Download from
  <https://www.hathitrust.org/member-libraries/resources-for-librarians/data-resources/hathifiles/>;
  the filter and checksum are in `SOURCE_VERSIONS.md`.
- The Project Gutenberg RDF catalog
  (<https://www.gutenberg.org/cache/epub/feeds/rdf-files.tar.bz2>), extracted
  to `~/.cache/pg-rdf/` for step 11.

Without the HathiTrust extract, the release can be rebuilt from step 14 using
the frozen `build/data/matches_full.csv`, `agents.csv`, and
`wikidata_authors.csv`; this reproduces the checksums in `RELEASE_FREEZE.md`.
HathiTrust publishes new full Hathifiles monthly, so the exact upstream file
may not remain available.

Wikidata queries (step 13) return current values; re-running them produces a
new dataset version rather than reproducing the frozen snapshot.

The analysis Rmds download PG texts into `analysis/cache/` (not tracked).
Rendering the manuscript and supplement uses a shared preprint style
(`../../preprint-style/`) that is not part of this repository.

### Software

R (≥ 4.4) with `data.table`, `knitr`, `rmarkdown`, `kableExtra`, `ggplot2`,
`scales`, `Matrix`, `glmnet`, `jsonlite`. Python 3 for steps 11, 17, 18 and
the embedding step; see `requirements.txt`.

## License

Data (`build/data/`, `data-raw/pg_catalog.csv`): CC BY 4.0
([`LICENSE-DATA`](LICENSE-DATA)). Code: MIT ([`LICENSE`](LICENSE)). Wikidata
content is CC0; HathiTrust bibliographic metadata and Project Gutenberg
catalog metadata are used under their respective terms.

## Citation

See [`CITATION.cff`](CITATION.cff).
