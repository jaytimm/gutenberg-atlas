# Full build, step 20: classify the evidence behind each sourced validation
# year, and report accuracy by evidence class.
#
# Two codings per row, derived from source_url and note:
#   evidence_class  what the cited source is:
#     catalogue      library or union catalogue record for an edition
#     edition        digitized edition (scan or transcribed title page)
#     reference      scholarly bibliography or reference work
#     contemporary   period review, notice, or serial record
#     general_web    Wikipedia and other general web pages
#     trade          dealer or auction listing
#   first_claim     TRUE when the source asserts first publication, rather
#                   than only dating one edition. Catalogue records and
#                   digitized editions date an edition; they count as a first
#                   claim only when the note records first-edition evidence.
# Run from build/: /usr/bin/Rscript 20-validation-evidence.R

suppressPackageStartupMessages(library(data.table))

v <- fread("data/validation_sourced.csv",
  colClasses = list(character = c("status", "source_url", "note")))
s <- fread("data/validation_sample.csv")
r <- fread("data/release.csv")

# First matching pattern wins.
classes <- list(
  trade = "abebooks|peterharrington|christies|bonhams|historical\\.ha\\.com|johnatkinsonbooks",
  contemporary = "archive\\.spectator|nature\\.com/articles|cambridge\\.org/core/journals|harpers\\.org/archive",
  reference = paste0("darwin-online|davidhume\\.org|victorianresearch\\.org|neww\\.huygens|",
    "wikisource\\.org/wiki/.*DNB|britannica\\.com|sf-encyclopedia|writing\\.upenn\\.edu|",
    "erudit\\.org|encyclopediavirginia|libraries\\.tas\\.gov\\.au|becker\\.wustl\\.edu"),
  catalogue = paste0("catalog\\.hathitrust|loc\\.gov/item|worldcat|catalogue\\.nli\\.ie|",
    "catalog\\.folger|catalog\\.freelibrary|lawcat\\.berkeley|franklin\\.library\\.upenn|",
    "openlibrary\\.org|onlinebooks\\.library\\.upenn|biodiversitylibrary\\.org/bibliography|",
    "doi\\.org/10\\.5962/bhl"),
  edition = paste0("gutenberg|archive\\.org/details|books\\.google|loc\\.gov/resource|",
    "commons\\.wikimedia|libertyfund|standardebooks|freeread\\.de|wikisource\\.org"),
  general_web = "wikipedia|en-academic|goodreads|davidalfredbywaters|dmrbooks|curtisweyant|umkc\\.edu|series-books\\.com"
)
v[, evidence_class := NA_character_]
for (k in names(classes)) {
  v[is.na(evidence_class) & grepl(classes[[k]], source_url), evidence_class := k]
}
if (v[, anyNA(evidence_class)]) {
  print(v[is.na(evidence_class), .(pg_id, source_url)])
  stop("unclassified source URLs")
}

v[, first_claim := evidence_class %in% c("reference", "contemporary", "general_web", "trade") |
  grepl("first|1st ed", note, ignore.case = TRUE)]

fwrite(v[, .(pg_id, evidence_class, first_claim)], "data/validation_evidence.csv")

# Accuracy by class (unweighted) and weighted sensitivity estimates.
r[, period := as.character(cut(ht_year, c(1699, 1799, 1849, 1899, 1924, 2100),
  labels = c("1700-99", "1800-49", "1850-99", "1900-24", "1925+")))]
Nh <- r[, .(N_h = .N), .(period, tier)]
x <- merge(v[status == "confirmed"], s[, .(pg_id, ht_year, period, tier)], by = "pg_id")
x[, ok := abs(ht_year - true_year) <= 1]

strat_est <- function(d) {
  a <- merge(d[, .(p = mean(ok), n = .N), .(period, tier)], Nh, by = c("period", "tier"))
  W <- a$N_h / sum(a$N_h)
  p <- sum(W * a$p)
  se <- sqrt(sum(W^2 * a$p * (1 - a$p) / pmax(a$n - 1, 1)))
  data.table(judged = nrow(d), cells = nrow(a),
    accuracy_percent = round(100 * p, 1),
    ci_low_percent = round(100 * (p - 1.96 * se), 1),
    ci_high_percent = round(100 * (p + 1.96 * se), 1))
}

by_class <- x[, .(judged = .N, first_claim = sum(first_claim),
  accuracy_percent = round(100 * mean(ok), 1)), evidence_class][order(-judged)]
sens <- rbind(
  cbind(subset = "All confirmed", strat_est(x)),
  cbind(subset = "Excluding HathiTrust catalogue", strat_est(x[!grepl("hathitrust", source_url)])),
  cbind(subset = "Excluding trade listings", strat_est(x[evidence_class != "trade"])),
  cbind(subset = "First-publication claims only", strat_est(x[first_claim == TRUE])),
  cbind(subset = "Excluding trade and general web", strat_est(x[!evidence_class %in% c("trade", "general_web")]))
)
fwrite(by_class, "data/validation_evidence_by_class.csv")
fwrite(sens, "data/validation_evidence_sensitivity.csv")

cat("Evidence class (unweighted accuracy):\n"); print(by_class)
cat("\nWeighted sensitivity:\n"); print(sens)
