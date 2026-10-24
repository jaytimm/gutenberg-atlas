# Full build, step 15: draw the stratified validation sample and write the
# hand-check sheet.
#
# Strata = period x match tier (10 cells). Allocation is proportional with a
# floor of 8 per cell, so sparse periods (1700-99, 1925+) are estimable; the
# stratum weights (N_h / n_h) are kept for weighted accuracy estimates.
# The hand-check sheet is never overwritten once it exists.
# Run from build/: /usr/bin/Rscript 15-validation-sample.R

suppressPackageStartupMessages(library(data.table))

N_SAMPLE <- 200L
FLOOR <- 8L
SEED <- 20261021L

r <- fread("data/release.csv")
r[, period := as.character(cut(ht_year, c(1699, 1799, 1849, 1899, 1924, 2100),
  labels = c("1700-99", "1800-49", "1850-99", "1900-24", "1925+")))]

st <- r[, .(N_h = .N), .(period, tier)][order(period, tier)]
st[, n_h := pmin(N_h, FLOOR)]
big <- st$N_h * N_SAMPLE / sum(st$N_h) > FLOOR
rest <- N_SAMPLE - sum(st$n_h[!big])
st[big, n_h := floor(rest * N_h / sum(N_h))]
# Largest-remainder rounding so the total is exactly N_SAMPLE.
short <- N_SAMPLE - sum(st$n_h)
if (short > 0) {
  rem <- rest * st$N_h / sum(st$N_h[big]) - st$n_h
  rem[!big] <- -Inf
  k <- order(-rem)[seq_len(short)]
  st$n_h[k] <- st$n_h[k] + 1L
}
st[, weight := N_h / n_h]
cat("Allocation:\n"); print(st)

set.seed(SEED)
smp <- r[st, on = c("period", "tier")][
  , .SD[sample(.N, n_h[1])], .(period, tier)]
smp[, `:=`(N_h = NULL, n_h = NULL)]
fwrite(smp, "data/validation_sample.csv")

sheet_file <- "data/validation_handcheck.csv"
if (file.exists(sheet_file)) {
  cat(sprintf("\n%s exists; not overwriting.\n", sheet_file))
} else {
  sheet <- smp[, .(pg_id, period, tier, weight, title, authors, wd_label, qid,
    ht_year, imprint, n_matches, gender, country_of_citizenship,
    birth = fifelse(is.na(birth), wd_birth, birth),
    death = fifelse(is.na(death), wd_death, death),
    pg_url = paste0("https://www.gutenberg.org/ebooks/", pg_id),
    ht_url = paste0("https://babel.hathitrust.org/cgi/pt?id=", htid),
    wd_url = paste0("https://www.wikidata.org/wiki/", qid),
    # To fill in by hand:
    true_year = NA_integer_, year_source = "", year_ok = NA,
    confidence = "", checker = "", notes = "")]
  setorder(sheet, period, tier, pg_id)
  fwrite(sheet, sheet_file)
  cat(sprintf("\nWrote %s (%d rows)\n", sheet_file, nrow(sheet)))
}

cat("\nSample by gender:\n"); print(smp[, .N, gender])
