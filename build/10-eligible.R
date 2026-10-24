# Full build, step 10: the eligible pool.
# Same filters as the pilot (archived pilot, 01-sample.R), without sampling.
# Run from build/: /usr/bin/Rscript 10-eligible.R

suppressPackageStartupMessages(library(data.table))

pg <- fread("../data-raw/pg_catalog.csv", encoding = "UTF-8")
setnames(pg, c("id", "type", "issued", "title", "language",
               "authors", "subjects", "locc", "bookshelves"))

pg <- pg[type == "Text" & language == "en" & authors != "" & !grepl(";", authors)]
pg <- pg[grepl(",", authors)]
pg <- pg[!grepl("^(Anonymous|Unknown|Various)", authors, ignore.case = TRUE)]

extract <- function(x, pattern) {
  m <- regexpr(pattern, x)
  out <- rep(NA_character_, length(x))
  out[m != -1L] <- regmatches(x, m)
  out
}
pg[, auth_dates := extract(authors, "[0-9]{3,4}\\??-([0-9]{3,4})?\\??$")]
pg[, auth_name := trimws(sub(",?\\s*[0-9]{3,4}\\??-([0-9]{3,4})?\\??$", "", authors))]
pg[, surname := tolower(trimws(tstrsplit(auth_name, ",")[[1]]))]
pg[, birth := suppressWarnings(as.integer(sub("-.*", "", gsub("\\?", "", auth_dates))))]
pg[, death := suppressWarnings(as.integer(
  sub(".*[0-9]{3,4}\\??-([0-9]{3,4})\\??$", "\\1", authors)))]
pg[death == birth, death := NA]

norm_title <- function(x) {
  x <- tolower(x)
  x <- sub("[:;].*$", "", x)
  x <- sub("\\bor,.*$", "", x)
  x <- gsub("[^a-z0-9 ]", " ", x)
  x <- gsub("\\b(the|a|an|of|and)\\b", " ", x)
  trimws(gsub("\\s+", " ", x))
}
pg[, title_norm := norm_title(title)]
pg <- pg[nchar(title_norm) >= 3]

out <- pg[, .(pg_id = id, title, title_norm, authors, auth_name, surname,
              birth, death)]
dir.create("data", showWarnings = FALSE)
fwrite(out, "data/eligible.csv")
cat(sprintf("Eligible pool: %d books, %d distinct author strings\n",
            nrow(out), uniqueN(out$authors)))
