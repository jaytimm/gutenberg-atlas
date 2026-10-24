# Structural audit of author linkage and Wikidata field coverage.
#
# This is not independent validation of P21/P27. It reports deterministic
# linkage constraints, coverage, and agreement between PG and Wikidata
# lifespan values. Run from build/:
#   /usr/bin/Rscript 19-author-metadata-report.R

suppressPackageStartupMessages(library(data.table))

r <- fread("data/release.csv")

required <- c("authors", "agent", "qid", "wd_label", "gender",
              "country_of_citizenship", "birth", "death",
              "wd_birth", "wd_death")
stopifnot(all(required %chin% names(r)))
stopifnot(r[, all(agent != "" & qid != "")])

# One row per resolved PG agent for author-level coverage.
a <- unique(r[, ..required], by = "agent")

name_signature <- function(x) {
  x <- iconv(x, to = "ASCII//TRANSLIT")
  x <- tolower(x)
  x <- sub(",?\\s*[0-9]{3,4}\\??-([0-9]{3,4})?\\??$", "", x)
  tokens <- strsplit(gsub("[^a-z ]", " ", x), "\\s+")
  vapply(tokens, function(z) paste(sort(z[nzchar(z)]), collapse = " "),
         character(1))
}

a[, pg_name := sub(",?\\s*[0-9]{3,4}\\??-([0-9]{3,4})?\\??$", "", authors)]
a[, name_agree := name_signature(pg_name) == name_signature(wd_label)]
a[, pg_surname := sub(",.*$", "", pg_name)]
a[, surname_agree := mapply(function(pg, wd) {
  pg_tokens <- strsplit(name_signature(pg), " ", fixed = TRUE)[[1]]
  wd_tokens <- strsplit(name_signature(wd), " ", fixed = TRUE)[[1]]
  all(pg_tokens %chin% wd_tokens)
}, pg_surname, wd_label)]

metric <- function(unit, field, numerator, denominator, note = "") {
  data.table(
    unit = unit,
    metric = field,
    numerator = numerator,
    denominator = denominator,
    percent = round(100 * numerator / denominator, 1),
    note = note
  )
}

out <- rbindlist(list(
  metric("book", "gender coverage", r[gender != "", .N], nrow(r),
         "Wikidata P21; coverage only"),
  metric("book", "citizenship coverage",
         r[country_of_citizenship != "", .N], nrow(r),
         "Wikidata P27; coverage only"),
  metric("book", "Wikidata birth-year coverage", r[!is.na(wd_birth), .N],
         nrow(r)),
  metric("book", "Wikidata death-year coverage", r[!is.na(wd_death), .N],
         nrow(r)),
  metric("author", "gender coverage", a[gender != "", .N], nrow(a),
         "Wikidata P21; coverage only"),
  metric("author", "citizenship coverage",
         a[country_of_citizenship != "", .N], nrow(a),
         "Wikidata P27; coverage only"),
  metric("author", "English label coverage", a[wd_label != qid, .N], nrow(a),
         "Wikidata label service; QID fallback counts as missing"),
  metric("author", "normalized name agreement", a[name_agree == TRUE, .N],
         a[!is.na(name_agree), .N],
         "Strict full-name token equality; diagnostic only"),
  metric("author", "surname token agreement", a[surname_agree == TRUE, .N],
         a[!is.na(surname_agree), .N],
         "PG surname tokens present in Wikidata label; diagnostic only"),
  metric("author", "birth year exact agreement",
         a[!is.na(birth) & !is.na(wd_birth) & birth == wd_birth, .N],
         a[!is.na(birth) & !is.na(wd_birth), .N],
         "Agreement, not independent accuracy"),
  metric("author", "birth year within one year",
         a[!is.na(birth) & !is.na(wd_birth) & abs(birth - wd_birth) <= 1, .N],
         a[!is.na(birth) & !is.na(wd_birth), .N],
         "Agreement, not independent accuracy"),
  metric("author", "death year exact agreement",
         a[!is.na(death) & !is.na(wd_death) & death == wd_death, .N],
         a[!is.na(death) & !is.na(wd_death), .N],
         "Agreement, not independent accuracy"),
  metric("author", "death year within one year",
         a[!is.na(death) & !is.na(wd_death) & abs(death - wd_death) <= 1, .N],
         a[!is.na(death) & !is.na(wd_death), .N],
         "Agreement, not independent accuracy")
))

fwrite(out, "data/author_metadata_summary.csv")
print(out)
cat(sprintf("\nResolved release authors: %d; books: %d\n", nrow(a), nrow(r)))
cat("All links were constrained to Wikidata instance-of human (Q5) in step 13.\n")
