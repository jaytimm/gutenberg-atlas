# Full build, step 14: apply the decision rules, produce the release files
# and the funnel table.
#
# Release row requirements:
#   1. matched a HathiTrust record (tier 1 or 2);
#   2. author resolves to a Wikidata QID via PG agent ID (P1938);
#   3. year within [birth+15, death+5] (birth+90 cap when death unknown),
#      using PG lifespan supplemented by Wikidata where PG lacks it;
#   4. in scope: year >= 1700.
# Everything else lands in unverified_candidates.csv with a reason.
# Run from build/: /usr/bin/Rscript 14-decide.R

suppressPackageStartupMessages(library(data.table))

m <- fread("data/matches_full.csv")
ag <- fread("data/agents.csv", colClasses = "character")
wd <- fread("data/wikidata_authors.csv", colClasses = list(character = "agent"))

m[, pg_id_chr := as.character(pg_id)]
m[ag, on = c(pg_id_chr = "pg_id"), agent := i.agent]
m[wd, on = "agent", `:=`(qid = i.qid, wd_label = i.wd_label,
                         gender = i.gender,
                         country_of_citizenship = i.country_of_citizenship,
                         wd_birth = i.wd_birth, wd_death = i.wd_death)]

# Citizenship: raw Wikidata P27 labels are kept as recorded. A derived field
# maps each label to a present-day state via country_map.csv (successor-state
# rule; judgment calls are flagged there). Duplicates are dropped, order kept.
cmap <- fread("country_map.csv", na.strings = NULL)
to_modern <- function(x) {
  vapply(strsplit(x, ";", fixed = TRUE), function(labels) {
    mc <- cmap$modern_country[match(trimws(labels), cmap$wikidata_label)]
    mc <- unique(mc[!is.na(mc) & mc != ""])
    paste(mc, collapse = "; ")
  }, character(1))
}
m[, citizenship_modern := fifelse(is.na(country_of_citizenship), "",
                                  to_modern(country_of_citizenship))]

# Lifespan: PG first, Wikidata fills gaps; disagreements kept as flags.
m[, birth_use := fifelse(is.na(birth), wd_birth, birth)]
m[, death_use := fifelse(is.na(death), wd_death, death)]
m[, lifespan_conflict := !is.na(birth) & !is.na(wd_birth) & birth != wd_birth]

m[, decision := fcase(
  is.na(ht_year), "no match",
  is.na(qid) | qid == "", "no wikidata link",
  ht_year < 1700, "out of scope (pre-1700)",
  !is.na(birth_use) & ht_year < birth_use + 15, "review (too early)",
  !is.na(death_use) & ht_year > death_use + 5, "review (posthumous)",
  is.na(death_use) & !is.na(birth_use) & ht_year > birth_use + 90, "review (posthumous)",
  is.na(death_use) & is.na(birth_use), "review (no lifespan)",
  default = "release"
)]
# Date flags: conditions under which ht_year is less reliable. Blank when none
# apply; several are joined with ";". Flags describe; they do not exclude.
#   uncertain_imprint: imprint year is queried, a range, a partial decade
#     ("18--", "189-"), or absent (rights-date fallback);
#   multivolume: PG title names a volume, part, or collected/complete works;
#   single_match / many_matches: one HathiTrust candidate, or more than 20.
date_flag_rules <- list(
  uncertain_imprint = function(d) {
    grepl("\\?|between|\\b1[5-9]-|\\b1[5-9][0-9]-", d$imprint, ignore.case = TRUE) |
      !grepl("1[5-9][0-9]{2}", d$imprint)
  },
  multivolume = function(d) {
    grepl("\\b(vols?|volumes?|part [0-9ivxlc]+|works of|complete works|collected)\\b",
          d$title, ignore.case = TRUE)
  },
  single_match = function(d) d$n_matches == 1L,
  many_matches = function(d) d$n_matches > 20L
)
flags <- sapply(date_flag_rules, function(rule) rule(m) %in% TRUE)
m[, date_flag := apply(flags, 1, function(x) paste(names(date_flag_rules)[x], collapse = ";"))]
m[is.na(ht_year), date_flag := ""]

cat("Funnel:\n")
funnel <- m[, .N, decision][order(-N)]
print(funnel)
fwrite(funnel, "data/funnel.csv")

release_cols <- c("pg_id", "title", "authors", "agent", "qid", "wd_label",
                  "gender", "country_of_citizenship", "citizenship_modern", "birth", "death", "wd_birth",
                  "wd_death", "lifespan_conflict", "ht_year", "htid",
                  "imprint", "tier", "n_matches", "date_flag")
# Flatten line breaks in titles so the CSV reads cleanly.
m[, title := trimws(gsub("\\s*[\r\n]+\\s*", " ", title))]

fwrite(m[decision == "release", ..release_cols], "data/release.csv")
fwrite(m[decision != "release",
         c(release_cols, "decision"), with = FALSE],
       "data/unverified_candidates.csv")

r <- m[decision == "release"]
cat(sprintf("\nRELEASE: %d books\n", nrow(r)))
cat(sprintf("  gender coverage:      %.0f%%\n", 100 * r[gender != "", .N] / nrow(r)))
cat(sprintf("  citizenship coverage: %.0f%%\n",
            100 * r[country_of_citizenship != "", .N] / nrow(r)))
cat(sprintf("  year range: %d-%d (median %d)\n",
            min(r$ht_year), max(r$ht_year), as.integer(median(r$ht_year))))
cat(sprintf("  lifespan conflicts flagged: %d\n", r[lifespan_conflict == TRUE, .N]))
cat("\nRelease by half-century:\n")
print(r[, .N, .(half_century = 50 * (ht_year %/% 50))][order(half_century)])

summary <- data.table(
  metric = c(
    "eligible_books", "release_books", "gender_coverage_percent",
    "citizenship_coverage_percent", "lifespan_conflicts",
    "publication_year_min", "publication_year_median", "publication_year_max"
  ),
  value = c(
    nrow(m), nrow(r),
    round(100 * r[gender != "", .N] / nrow(r), 1),
    round(100 * r[country_of_citizenship != "", .N] / nrow(r), 1),
    r[lifespan_conflict == TRUE, .N],
    min(r$ht_year), as.integer(median(r$ht_year)), max(r$ht_year)
  )
)
fwrite(summary, "data/release_summary.csv")
