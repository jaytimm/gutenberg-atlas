# Gutenberg Atlas data dictionary

## Canonical dataset

`build/data/release.csv` contains one row per released Project Gutenberg
book. It is generated uniformly by scripts 10–14; no book-specific manual
corrections are applied.

| Field | Meaning |
|---|---|
| `pg_id` | Project Gutenberg ebook identifier. One row per ebook, not per work: 3,055 rows share an `htid` with another row (930 HathiTrust items), from duplicate ebooks or volumes of a set. |
| `title` | Title from the Project Gutenberg catalog. |
| `authors` | Project Gutenberg author string, including lifespan when supplied. |
| `agent` | Project Gutenberg agent identifier for the author. |
| `qid` | Wikidata entity identifier linked by Wikidata property P1938. Step 13 requires the entity to be human (P31=Q5). |
| `wd_label` | English Wikidata label; may fall back to the QID when no English label exists. |
| `gender` | Raw Wikidata P21 label. This is a sourced claim, not an inferred or independently validated value. Released values: `male` (16,701), `female` (4,490), `cisgender woman` (3), blank (102). |
| `country_of_citizenship` | Raw Wikidata P27 label(s), separated by semicolons. This is not generalized “nationality.” Ten values are Wikidata placeholders (an “unknown value” blank-node URI or an unlabelled QID) kept as recorded. |
| `citizenship_modern` | Derived: each `country_of_citizenship` label mapped to a present-day state by `build/country_map.csv` (successor-state rule; judgment calls flagged in its `review` column), deduplicated, semicolon-separated. Blank when no label maps. |
| `birth`, `death` | Birth and death years parsed from the Project Gutenberg author string. |
| `wd_birth`, `wd_death` | Birth and death years from Wikidata P569 and P570. |
| `lifespan_conflict` | `TRUE` when both PG and Wikidata provide a birth year and they disagree; neither value is silently overwritten. |
| `ht_year` | Earliest imprint year among the selected HathiTrust title/author matches: the earliest matched English-language edition, used as an estimate of publication year. For translations it estimates the first English edition; for volumes of collected works or multi-volume sets it can reflect the date of the set. Errors are mostly late (later editions or reprints). Released values run from 1700 to 2004. |
| `htid` | HathiTrust item identifier supporting `ht_year`. |
| `imprint` | HathiTrust imprint string for the selected item. |
| `tier` | Match tier: 1 = exact normalized title within author surname; 2 = normalized-title prefix containment within surname. |
| `n_matches` | Number of HathiTrust candidates in the selected match tier. |
| `date_flag` | Conditions under which `ht_year` is less reliable, semicolon-separated; blank when none apply. `uncertain_imprint`: imprint year queried, a range, a partial decade ("18--"), or absent. `multivolume`: title names a volume, part, or collected/complete works. `single_match`: one HathiTrust candidate. `many_matches`: more than 20 candidates. Flags describe; they do not exclude. In the validation sample, flagged books were within one year for 66 of 82 (80%), unflagged for 105 of 117 (90%). |

## Other generated files

- `build/data/unverified_candidates.csv`: records excluded from release, with
  all release fields plus `decision`.
- `build/data/funnel.csv`: counts by release/exclusion decision.
- `build/data/release_summary.csv`: compact full-release counts and coverage.
- `build/data/author_metadata_summary.csv`: book- and author-level Wikidata
  coverage plus PG/Wikidata linkage and lifespan-agreement diagnostics.
- `build/data/date_validation_summary.csv`: weighted overall date accuracy
  and unweighted period-specific results.

## Validation data

- `build/data/validation_sample.csv`: seeded 200-book stratified sample by
  matched period and match tier. All five periods contribute to the weighted
  accuracy estimate.
- `build/data/validation_sourced.csv`: independently researched
  first-publication years and citations for that sample. `status` is
  `confirmed` or `ambiguous`.
- `build/data/validation_evidence.csv`: evidence class of each validation
  source (`catalogue`, `edition`, `reference`, `contemporary`, `general_web`,
  `trade`) and `first_claim`, whether the source asserts first publication.
  Summaries are in `validation_evidence_by_class.csv` and
  `validation_evidence_sensitivity.csv`.
- `build/data/validation_handcheck.csv`: working join of the release sample
  and sourced date truth. Legacy blank author-field check columns are not
  accuracy claims.

The manual validation data measure the automated pipeline. They do not patch
individual production rows.
