# Full build, step 16: date accuracy from the validation sheet.
#
# Truth comes from validation_sourced.csv (one cited source URL per book;
# status confirmed / probable / ambiguous). Rows in validation_handcheck.csv
# are filled from it unless a person has already checked them (checker is
# anything other than "", "pass1" or "sources"). Ambiguous rows get no
# true_year and are excluded. year_ok = |ht_year - true_year| <= 1.
# validation_pass1.csv (Claude's unsourced recall) is used only to report
# how well recall agreed with the sources.
# Run from build/: /usr/bin/Rscript 16-validation-report.R

suppressPackageStartupMessages(library(data.table))

sheet_file <- "data/validation_handcheck.csv"
h <- fread(sheet_file, colClasses = list(character = c("year_source",
  "confidence", "checker", "notes"), integer = "true_year"))
src <- fread("data/validation_sourced.csv",
  colClasses = list(character = c("status", "source_url", "note"),
                    integer = "true_year"))

fill <- which(h$checker %in% c("", "pass1", "sources") & h$pg_id %in% src$pg_id)
k <- match(h$pg_id[fill], src$pg_id)
h[fill, `:=`(true_year = src$true_year[k], confidence = src$status[k],
             year_source = src$source_url[k], notes = src$note[k],
             checker = "sources")]
cat(sprintf("Filled %d rows from cited sources\n", length(fill)))
h[, year_ok := fifelse(is.na(true_year), NA, abs(ht_year - true_year) <= 1L)]
fwrite(h, sheet_file)

# Stratified estimator over judged books: p = sum(W_h p_h),
# var = sum(W_h^2 p_h (1 - p_h) / (n_h - 1)), W_h = population share.
strat_est <- function(d) {
  release <- fread("data/release.csv")
  release[, period := as.character(cut(
    ht_year, c(1699, 1799, 1849, 1899, 1924, 2100),
    labels = c("1700-99", "1800-49", "1850-99", "1900-24", "1925+")
  ))]
  N <- release[, .(N_h = .N), .(period, tier)]
  s <- d[!is.na(year_ok), .(n_h = .N, p_h = mean(year_ok)), .(period, tier)]
  s <- s[N, on = c("period", "tier"), nomatch = 0L]
  s[, W_h := N_h / sum(N_h)]
  p <- s[, sum(W_h * p_h)]
  se <- sqrt(s[n_h > 1, sum(W_h^2 * p_h * (1 - p_h) / (n_h - 1))])
  list(judged = sum(s$n_h), acc = p, lo = max(0, p - 1.96 * se),
       hi = min(1, p + 1.96 * se))
}

fmt <- function(e) sprintf("%.1f%% [%.1f, %.1f]  (n=%d)",
  100 * e$acc, 100 * e$lo, 100 * e$hi, e$judged)

cat(sprintf("\nJudged %d of %d; unresolved %d\n", h[!is.na(year_ok), .N],
            nrow(h), h[is.na(year_ok), .N]))
all_est <- strat_est(h)
confirmed_est <- strat_est(h[confidence == "confirmed" |
                               !checker %in% c("pass1", "sources")])
cat("Weighted date accuracy (+/-1 yr), 95% CI:\n")
cat("  all:            ", fmt(all_est), "\n")
cat("  confirmed only: ", fmt(confirmed_est), "\n")

p1 <- fread("data/validation_pass1.csv", select = c("pg_id", "true_year"))
cmp <- merge(h[!is.na(true_year), .(pg_id, src_year = true_year, ht_year)],
             p1[!is.na(true_year), .(pg_id, recall_year = true_year)], by = "pg_id")
cat(sprintf("\nRecall (pass 1) vs sources: same +/-1 yr on %d of %d; ",
            cmp[abs(recall_year - src_year) <= 1, .N], nrow(cmp)))
cat(sprintf("same HT verdict on %d of %d\n",
            cmp[(abs(recall_year - ht_year) <= 1) == (abs(src_year - ht_year) <= 1), .N],
            nrow(cmp)))

cat("\nBy period (unweighted within period):\n")
period_summary <- h[!is.na(year_ok), .(
  judged = .N, ok = sum(year_ok),
  accuracy_percent = round(100 * mean(year_ok), 1)
), period]
print(period_summary)
cat("\nBy tier:\n")
print(h[!is.na(year_ok), .(judged = .N, acc = round(100 * mean(year_ok), 1)), tier])
cat("\nBy gender:\n")
print(h[!is.na(year_ok), .(judged = .N, acc = round(100 * mean(year_ok), 1)), gender])

cat("\nErrors (HT year minus true year):\n")
err <- h[year_ok == FALSE, .(pg_id, period, title = substr(title, 1, 40),
                             ht_year, true_year, gap = ht_year - true_year)]
print(err[order(period, -gap)])
cat("\nUnresolved (need a hand look):\n")
print(h[is.na(year_ok), .(pg_id, title = substr(title, 1, 45), ht_year, notes)])

validation_summary <- rbindlist(list(
  data.table(
    scope = "overall_weighted",
    group = c("all", "confirmed_only"),
    judged = c(all_est$judged, confirmed_est$judged),
    accuracy_percent = round(100 * c(all_est$acc, confirmed_est$acc), 1),
    ci_low_percent = round(100 * c(all_est$lo, confirmed_est$lo), 1),
    ci_high_percent = round(100 * c(all_est$hi, confirmed_est$hi), 1)
  ),
  period_summary[, .(
    scope = "period_unweighted", group = period, judged,
    accuracy_percent, ci_low_percent = NA_real_, ci_high_percent = NA_real_
  )]
), use.names = TRUE)
fwrite(validation_summary, "data/date_validation_summary.csv")
