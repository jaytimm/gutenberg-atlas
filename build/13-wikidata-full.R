# Full build, step 13: resolve every unique PG agent on Wikidata (P1938) and
# pull gender (P21), citizenship (P27), birth (P569), death (P570).
# Batched SPARQL with polite pacing.
# Run from build/: /usr/bin/Rscript 13-wikidata-full.R

suppressPackageStartupMessages({library(data.table); library(jsonlite)})

agents <- fread("data/agents.csv", colClasses = "character")
ids <- sort(unique(agents[agent != "", agent]))
cat(sprintf("Unique agents to resolve: %d\n", length(ids)))

batch_size <- 300L
batches <- split(ids, ceiling(seq_along(ids) / batch_size))
out_list <- vector("list", length(batches))

for (bi in seq_along(batches)) {
  q <- paste0(
    "SELECT ?pgid ?item ?itemLabel ?genderLabel ?citizenshipLabel ",
    "(YEAR(?b) AS ?birth) (YEAR(?d) AS ?death) WHERE { ",
    "VALUES ?pgid { ", paste(shQuote(batches[[bi]], type = "cmd"), collapse = " "), " } ",
    "?item wdt:P1938 ?pgid ; wdt:P31 wd:Q5 . ",
    "OPTIONAL { ?item wdt:P21 ?gender . } ",
    "OPTIONAL { ?item wdt:P27 ?citizenship . } ",
    "OPTIONAL { ?item wdt:P569 ?b . } ",
    "OPTIONAL { ?item wdt:P570 ?d . } ",
    "SERVICE wikibase:label { bd:serviceParam wikibase:language \"en\". } }"
  )
  tmp <- tempfile(fileext = ".json")
  for (attempt in 1:3) {
    status <- system2("curl", c("-sG", "--max-time", "120",
      "https://query.wikidata.org/sparql",
      "--data-urlencode", shQuote(paste0("query=", q)),
      "-H", shQuote("Accept: application/sparql-results+json"),
      "-H", shQuote("User-Agent: Gutenberg-Atlas-build/0.1 (jtimm@unm.edu)"),
      "-o", tmp))
    ok <- status == 0L && file.size(tmp) > 0 &&
      !inherits(try(res <- fromJSON(tmp, simplifyVector = TRUE), silent = TRUE),
                "try-error")
    if (ok) break
    cat(sprintf("  batch %d attempt %d failed; backing off\n", bi, attempt))
    Sys.sleep(10 * attempt)
  }
  if (!ok) stop("SPARQL batch ", bi, " failed repeatedly.")
  b <- res$results$bindings
  if (length(b) && !is.null(b$pgid)) {
    out_list[[bi]] <- data.table(
      agent = b$pgid$value,
      qid = basename(b$item$value),
      wd_label = b$itemLabel$value,
      gender = if (!is.null(b$genderLabel)) b$genderLabel$value else NA,
      country_of_citizenship = if (!is.null(b$citizenshipLabel)) b$citizenshipLabel$value else NA,
      wd_birth = if (!is.null(b$birth)) suppressWarnings(as.integer(b$birth$value)) else NA,
      wd_death = if (!is.null(b$death)) suppressWarnings(as.integer(b$death$value)) else NA
    )
  }
  cat(sprintf("  batch %d/%d done (%d rows)\n", bi, length(batches),
              if (is.null(out_list[[bi]])) 0L else nrow(out_list[[bi]])))
  Sys.sleep(1.5)
}

wd <- rbindlist(out_list)
wd <- wd[, .(qid = qid[1], wd_label = wd_label[1],
             gender = paste(unique(na.omit(gender)), collapse = "; "),
             country_of_citizenship = paste(
               unique(na.omit(country_of_citizenship)), collapse = "; "),
             wd_birth = wd_birth[1], wd_death = wd_death[1]), agent]
fwrite(wd, "data/wikidata_authors.csv")
cat(sprintf("\nResolved %d of %d agents (%.0f%%)\n", nrow(wd), length(ids),
            100 * nrow(wd) / length(ids)))
