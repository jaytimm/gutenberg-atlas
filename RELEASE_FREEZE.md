# Gutenberg Atlas release freeze

Freeze date: 2026-10-24 (removes the upper publication-year exclusion; source
metadata values are unchanged)

## Dataset

- Eligible English single-author books: 38,550
- Released books: 21,296
- Linked authors: 7,383
- Publication-year range: 1700–2004 (median 1901)
- Gender coverage: 99.5%
- Country-of-citizenship coverage: 89.1%
- PG/Wikidata birth-year conflicts flagged: 750
- Books with a `date_flag` (less reliable `ht_year`): 7,509 (35.3%)

## Validation

- Sourced stratified random sample: 200 books
- Reference years resolved: 199; one composite edition unresolved
- Weighted publication-year accuracy within ±1 year:
  **87.4% [82.7, 92.1]**
- The 1925+ stratum is retained in the release and weighted estimate; its
  unweighted accuracy was 62.5% (10/16).
- Author fields are reported as Wikidata claims. Coverage and PG/Wikidata
  lifespan agreement are reported; independent author-field accuracy is not
  claimed.

## Frozen artifacts

| File | Logical rows | SHA-256 |
|---|---:|---|
| `build/data/release.csv` | 21,296 | `4f713fd501dea0091369ed9caf8791ecc8f69a105e90ae4dfa53cc3161e2cd7e` |
| `build/data/unverified_candidates.csv` | 17,254 | `840bebcd1985ce666731e770aefb4db51989c9c2523ea00d08c74427f7bbb49d` |
| `build/data/funnel.csv` | 7 | `4bdf718f251d56bd87ffc6f04b2fdd624c8295a92a6aacdf21cad66d6396c47d` |
| `build/data/release_summary.csv` | 8 | `ed332a74353f016e04bd35af768621334dbff7241e18dfd2a22bd623e291e4d7` |
| `build/data/author_metadata_summary.csv` | 13 | `f2cbeac6ff19fe8c57d20c63c41672b92b1bedd975854a9b530f06df67dedd39` |
| `build/data/date_validation_summary.csv` | 7 | `11954b6009ab438c8ef482c3a6005d8ba03f9608f535387e78029ff11f70621a` |
| `build/data/validation_sourced.csv` | 200 | `46e21f9bfeb3178b4415b9ec2563a9d30ca32fe9ab70a8f54fa4a22e9ed1ad3d` |
| `build/country_map.csv` | 174 | `f90b3c930b1965600f250264f5a13e4aac5e8b4df7055fb4e949970b5a006a2a` |
| `build/data/validation_evidence.csv` | 200 | `46a60305c2fdae7cc15f50a818cff2ab2f2990f4f58c57b2106efddc6923349c` |

The canonical release is generated uniformly. The manually sourced
validation sample evaluates the pipeline and does not patch production rows.
