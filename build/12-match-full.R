# Full build, step 12: match every eligible book against the Hathifiles.
# Same rules as the pilot (archived pilot, 02-match.R): tier 1 = exact normalized title
# within surname; tier 2 = prefix containment within surname; earliest
# plausible year wins.
# Run from build/: /usr/bin/Rscript 12-match-full.R

suppressPackageStartupMessages(library(data.table))

pg <- fread("data/eligible.csv")
ht <- fread("../data-raw/hathi_eng_books.tsv",
            header = FALSE, sep = "\t", quote = "",
            col.names = c("htid", "ht_title", "imprint", "rights_date", "ht_author"))
cat(sprintf("eligible=%d  hathi=%d\n", nrow(pg), nrow(ht)))

norm_title <- function(x) {
  x <- tolower(x)
  x <- sub("[:;].*$", "", x)
  x <- sub("\\bor,.*$", "", x)
  x <- gsub("[^a-z0-9 ]", " ", x)
  x <- gsub("\\b(the|a|an|of|and)\\b", " ", x)
  trimws(gsub("\\s+", " ", x))
}

# HT surname: text before the first comma in the author field.
ht[, surname := tolower(trimws(sub(",.*$", "", ht_author)))]
ht <- ht[surname %chin% unique(pg$surname)]
cat(sprintf("hathi rows with an eligible surname: %d\n", nrow(ht)))
ht[, title_norm := norm_title(ht_title)]

year_from <- function(imprint, rights) {
  y <- suppressWarnings(as.integer(sub(".*?\\b(1[5-9][0-9]{2}|20[0-2][0-9])\\b.*", "\\1", imprint)))
  bad <- is.na(y)
  r <- suppressWarnings(as.integer(rights))
  y[bad] <- ifelse(!is.na(r[bad]) & r[bad] >= 1500 & r[bad] <= 2026, r[bad], NA)
  y
}
ht[, year := year_from(imprint, rights_date)]
ht <- ht[!is.na(year)]
setkey(ht, surname)

# Tier 1: exact (surname, title_norm) join; earliest year per book.
t1 <- ht[pg, on = c("surname", "title_norm"), nomatch = NULL,
         .(pg_id, htid, ht_title, imprint, year)]
t1_best <- t1[, .(ht_year = min(year), n_matches = .N,
                  htid = htid[which.min(year)],
                  ht_title = ht_title[which.min(year)],
                  imprint = imprint[which.min(year)], tier = 1L), pg_id]

# Tier 2: prefix containment within surname for still-unmatched books.
left <- pg[!pg_id %in% t1_best$pg_id]
cat(sprintf("tier1 matched=%d; trying tier2 for %d\n", nrow(t1_best), nrow(left)))
t2_list <- vector("list", nrow(left))
for (i in seq_len(nrow(left))) {
  b <- left[i]
  cand <- ht[.(b$surname), nomatch = NULL]
  if (!nrow(cand)) next
  hit <- cand[startsWith(title_norm, b$title_norm) |
                startsWith(b$title_norm, title_norm)]
  hit <- hit[nchar(title_norm) >= 3]
  if (!nrow(hit)) next
  k <- which.min(hit$year)
  t2_list[[i]] <- data.table(pg_id = b$pg_id, ht_year = hit$year[k],
                             n_matches = nrow(hit), htid = hit$htid[k],
                             ht_title = hit$ht_title[k],
                             imprint = hit$imprint[k], tier = 2L)
  if (i %% 2000 == 0) cat(sprintf("  tier2 progress: %d/%d\n", i, nrow(left)))
}
t2_best <- rbindlist(t2_list)

matches <- rbind(t1_best, t2_best)
res <- merge(pg, matches, by = "pg_id", all.x = TRUE)
fwrite(res, "data/matches_full.csv")
cat(sprintf("\nTotal matched: %d of %d (%.0f%%)  [tier1=%d tier2=%d]\n",
            res[!is.na(ht_year), .N], nrow(res),
            100 * res[!is.na(ht_year), .N] / nrow(res),
            res[tier == 1, .N], res[tier == 2, .N]))
