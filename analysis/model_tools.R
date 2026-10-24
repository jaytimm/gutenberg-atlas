# Text preparation, author-disjoint baselines, and author-cluster bootstrap
# for the modeling report.

note <- function(...) {
  text <- paste(...)
  path <- getOption("atlas.progress")
  if (!is.null(path)) {
    cat(format(Sys.time(), "%H:%M:%S"), text, "\n", file = path, append = TRUE)
  }
  message(text)
}

# Assigns whole agents to folds, stratified by each agent's modal stratum.
group_foldid <- function(agent, strata, nfolds) {
  groups <- data.table(agent = agent, strata = as.character(strata))
  groups <- groups[, .N, by = .(agent, strata)][order(-N)][, .SD[1], by = agent]
  groups[, fold := (sample.int(.N) - 1L) %% nfolds + 1L, by = strata]
  groups$fold[match(agent, groups$agent)]
}

sample_task <- function(dt, label, n_per, max_books, seed) {
  set.seed(seed)
  parts <- lapply(sort(unique(dt[[label]])), function(group) {
    books <- dt[dt[[label]] == group]
    chosen <- books[0]
    for (author in sample(unique(books$agent))) {
      pool <- books[agent == author]
      chosen <- rbind(chosen, pool[sample.int(.N, min(.N, max_books))], fill = TRUE)
      if (nrow(chosen) >= n_per) break
    }
    head(chosen, n_per)
  })
  rbindlist(parts, fill = TRUE)
}

assign_folds <- function(dt, label, seed) {
  set.seed(seed)
  out <- copy(dt)
  out[, fold := group_foldid(agent, out[[label]], 5L)]
  out
}

words_of <- function(text) {
  text <- tolower(iconv(text, to = "ASCII", sub = " "))
  words <- strsplit(text, "[^a-z0-9']+", perl = FALSE)[[1]]
  words[nzchar(words)]
}

# The body view skips the first 400 words after the start marker and takes up
# to n_words from the middle of the rest. The raw view is the first stretch of
# the downloaded file, cut to the same length as that book's body view.
text_views <- function(text, n_words = 5000L, min_words = 1500L) {
  out <- c(raw = NA_character_, body = NA_character_)
  start <- regexpr("\\*\\*\\* *START OF (THIS|THE) PROJECT GUTENBERG",
                   text, perl = TRUE, ignore.case = TRUE)
  end <- regexpr("\\*\\*\\* *END OF (THIS|THE) PROJECT GUTENBERG",
                 text, perl = TRUE, ignore.case = TRUE)
  if (start > 0 && end > start) {
    content <- words_of(substr(text, start, end - 1L))
    if (length(content) >= 400L + min_words) {
      content <- content[-seq_len(400L)]
      take <- min(n_words, length(content))
      start_at <- floor((length(content) - take) / 2) + 1L
      out[["body"]] <- paste(content[start_at:(start_at + take - 1L)],
                             collapse = " ")
      out[["raw"]] <- paste(head(words_of(text), take), collapse = " ")
    }
  }
  out
}

fetch_views <- function(ids, cache) {
  dir.create(cache, recursive = TRUE, showWarnings = FALSE)
  out <- vector("list", length(ids))
  for (i in seq_along(ids)) {
    id <- ids[[i]]
    dest <- file.path(cache, paste0(id, ".txt"))
    if (!file.exists(dest) || file.info(dest)$size < 200) {
      url <- sprintf("https://www.gutenberg.org/cache/epub/%s/pg%s.txt", id, id)
      status <- system2("curl", c(
        "-fsSL", "--retry", "2", "--max-time", "40",
        "-A", "Gutenberg-Atlas-analysis/0.1",
        "-o", dest, url
      ), stdout = FALSE, stderr = FALSE)
      if (!identical(as.integer(status), 0L)) unlink(dest)
      Sys.sleep(0.3)
    }
    views <- c(raw = NA_character_, body = NA_character_)
    if (file.exists(dest) && file.info(dest)$size >= 200) {
      views <- text_views(paste(readLines(dest, warn = FALSE, encoding = "UTF-8"),
                                collapse = "\n"))
    }
    out[[i]] <- data.table(pg_id = id, raw_text = views[["raw"]],
                           body_text = views[["body"]])
    if (i %% 50L == 0L) note("Prepared ", i, " of ", length(ids), " texts")
  }
  rbindlist(out)
}

sparse_from_tokens <- function(token_lists, vocab = NULL, min_df = 5L,
                               max_features = 8000L) {
  dt <- rbindlist(lapply(seq_along(token_lists), function(i) {
    terms <- token_lists[[i]]
    if (length(terms)) data.table(doc = i, term = terms) else NULL
  }))
  if (is.null(dt) || !nrow(dt)) {
    return(list(x = Matrix::sparseMatrix(i = 1, j = 1, x = 0,
                                         dims = c(length(token_lists), 1))[, 0],
                vocab = character()))
  }
  dt <- dt[, .(tf = .N), by = .(doc, term)]
  if (is.null(vocab)) {
    keep <- dt[, .(df = uniqueN(doc)), by = term][df >= min_df][order(-df)]
    if (nrow(keep) > max_features) keep <- keep[seq_len(max_features)]
    vocab <- keep$term
  }
  dt <- dt[term %chin% vocab]
  x <- Matrix::sparseMatrix(
    i = dt$doc, j = match(dt$term, vocab), x = dt$tf,
    dims = c(length(token_lists), length(vocab))
  )
  list(x = x, vocab = vocab)
}

apply_idf <- function(train, test) {
  df <- Matrix::colSums(train > 0)
  idf <- log((nrow(train) + 1) / (df + 1)) + 1
  scale_columns <- function(x) x %*% Matrix::Diagonal(x = idf)
  list(train = scale_columns(train), test = scale_columns(test))
}

word_tokens <- function(text) {
  lapply(strsplit(text, " ", fixed = TRUE), function(x) x[nzchar(x)])
}

hash_chars <- function(texts, buckets = 4096L) {
  mult <- c(1, 17, 289, 4913, 83521)
  rows <- integer()
  cols <- integer()
  vals <- numeric()
  for (i in seq_along(texts)) {
    bytes <- as.integer(charToRaw(paste0(" ", texts[[i]], " ")))
    acc <- integer(buckets)
    n <- length(bytes)
    for (k in 3:5) {
      if (n < k) next
      h <- numeric(n - k + 1L)
      for (j in seq_len(k)) {
        h <- h + mult[[j]] * bytes[j:(n - k + j)]
      }
      acc <- acc + tabulate((as.integer(h %% buckets)) + 1L, nbins = buckets)
    }
    nz <- which(acc > 0L)
    rows <- c(rows, rep.int(i, length(nz)))
    cols <- c(cols, nz)
    vals <- c(vals, acc[nz])
  }
  Matrix::sparseMatrix(i = rows, j = cols, x = vals,
                       dims = c(length(texts), buckets))
}

# Held-out baseline: the majority training class, or the median training year.
baseline_predict <- function(task, outcome) {
  pred <- if (outcome == "year") rep(NA_real_, nrow(task)) else rep(NA_character_, nrow(task))
  for (fold in sort(unique(task$fold))) {
    test <- task$fold == fold
    pred[test] <- if (outcome == "year") {
      median(task$year[!test])
    } else {
      names(sort(table(task$class[!test]), decreasing = TRUE))[1]
    }
  }
  pred
}

# Embeds body views with embed_bge.py; vectors are cached by pg_id in path.
embed_bge <- function(views, path, model = "BAAI/bge-base-en-v1.5") {
  input <- tempfile(fileext = ".csv")
  fwrite(views[!is.na(body_text), .(pg_id, body_text)], input)
  status <- system2("python3", c("-I", "embed_bge.py", input, path, "--model", model),
                    env = "HF_HUB_OFFLINE=1")
  unlink(input)
  if (!identical(as.integer(status), 0L)) stop("BGE embedding failed")
  emb <- fread(path)
  out <- as.matrix(emb[, -1])
  rownames(out) <- emb$pg_id
  out
}

# Held-out predictions from an L1 logistic (or linear, for year) model on
# TF-IDF features, or a ridge model on BGE embeddings.
predict_view <- function(task, text_column, feature, outcome, embeddings = NULL) {
  regression <- outcome == "year"
  classes <- sort(unique(task$class))
  family <- if (regression) "gaussian" else if (length(classes) == 2) "binomial" else "multinomial"
  texts <- task[[text_column]]
  pred <- baseline_predict(task, outcome)
  all_tokens <- if (feature == "word") word_tokens(texts) else NULL
  hashed <- if (feature == "char") hash_chars(texts) else NULL
  dense <- if (feature == "bge") embeddings[as.character(task$pg_id), , drop = FALSE] else NULL
  for (fold in sort(unique(task$fold))) {
    test <- task$fold == fold
    if (feature == "bge") {
      scaled <- list(train = dense[!test, , drop = FALSE], test = dense[test, , drop = FALSE])
    } else if (feature == "char") {
      scaled <- apply_idf(hashed[!test, , drop = FALSE], hashed[test, , drop = FALSE])
    } else {
      trained <- sparse_from_tokens(all_tokens[!test], min_df = 5L)
      if (length(trained$vocab) < 2L) next
      held <- sparse_from_tokens(all_tokens[test], vocab = trained$vocab)
      scaled <- apply_idf(trained$x, held$x)
    }
    response <- if (regression) {
      task$year[!test]
    } else if (family == "binomial") {
      as.integer(task$class[!test] == classes[[2]])
    } else {
      factor(task$class[!test], levels = classes)
    }
    inner <- group_foldid(task$agent[!test], task$class[!test], 3L)
    fit <- tryCatch(glmnet::cv.glmnet(
      scaled$train, response, family = family, alpha = if (feature == "bge") 0 else 1, foldid = inner,
      nlambda = 20, type.measure = if (regression) "mae" else "class"
    ), error = function(err) NULL)
    if (is.null(fit)) next
    if (regression) {
      pred[test] <- as.vector(predict(fit, scaled$test, s = "lambda.1se"))
    } else {
      p <- as.vector(predict(fit, scaled$test, s = "lambda.1se", type = "class"))
      pred[test] <- if (family == "binomial") ifelse(p == "1", classes[[2]], classes[[1]]) else p
    }
  }
  pred
}

model_names <- c("baseline", "raw_word", "raw_char", "body_word", "body_char",
                 "body_bge")
models_in <- function(pred) intersect(model_names, names(pred))

# Returns one row per book, with a held-out prediction column for each model.
run_task <- function(task, outcome = "class", embeddings = NULL) {
  name <- unique(task$task)
  out <- task[, intersect(c("task", "pg_id", "agent", "class", "year", "fold"),
                          names(task)), with = FALSE]
  set(out, j = "baseline", value = baseline_predict(task, outcome))
  for (view in c("raw", "body")) {
    for (feature in c("word", "char")) {
      note(sprintf("%s | %s | %s", name, view, feature))
      set(out, j = paste(view, feature, sep = "_"),
          value = predict_view(task, paste0(view, "_text"), feature, outcome))
    }
  }
  if (!is.null(embeddings)) {
    note(sprintf("%s | body_text | bge", name))
    set(out, j = "body_bge",
        value = predict_view(task, "body_text", "bge", outcome, embeddings))
  }
  out
}

macro_f1 <- function(true, pred, classes) {
  mean(vapply(classes, function(class) {
    tp <- sum(true == class & pred == class)
    fp <- sum(true != class & pred == class)
    fn <- sum(true == class & pred != class)
    if (tp == 0) 0 else 2 * tp / (2 * tp + fp + fn)
  }, numeric(1)))
}

balanced_accuracy <- function(true, pred, classes) {
  mean(vapply(classes, function(class) {
    denom <- sum(true == class)
    if (denom == 0) NA_real_ else sum(true == class & pred == class) / denom
  }, numeric(1)), na.rm = TRUE)
}

# Primary metric: macro-F1 for classes, mean absolute error (years) for year.
primary_metric <- function(pred, outcome, classes, idx = seq_len(nrow(pred))) {
  vapply(models_in(pred), function(m) {
    if (outcome == "year") {
      mean(abs(pred$year[idx] - pred[[m]][idx]))
    } else {
      macro_f1(pred$class[idx], pred[[m]][idx], classes)
    }
  }, numeric(1))
}

# Resamples agents with replacement, so books by one author move together.
# Gains are signed so that a positive value always means the text model helps.
boot_task <- function(pred, outcome, B = 1000L, seed = 1L) {
  set.seed(seed)
  classes <- sort(unique(pred$class))
  rows <- split(seq_len(nrow(pred)), pred$agent)
  sign <- if (outcome == "year") -1 else 1
  summarise <- function(m) {
    gain <- sign * (m[-1] - m[["baseline"]])
    names(gain) <- paste0("gain_", names(m)[-1])
    c(m, gain,
      header_word = sign * (m[["raw_word"]] - m[["body_word"]]),
      header_char = sign * (m[["raw_char"]] - m[["body_char"]]))
  }
  est <- summarise(primary_metric(pred, outcome, classes))
  reps <- vapply(seq_len(B), function(b) {
    idx <- unlist(rows[sample.int(length(rows), replace = TRUE)], use.names = FALSE)
    summarise(primary_metric(pred, outcome, classes, idx))
  }, numeric(length(est)))
  data.table(
    task = unique(pred$task), quantity = names(est), estimate = unname(est),
    lo = apply(reps, 1, quantile, 0.025), hi = apply(reps, 1, quantile, 0.975)
  )
}

secondary_metrics <- function(pred, outcome) {
  classes <- sort(unique(pred$class))
  rbindlist(lapply(models_in(pred), function(m) {
    if (outcome == "year") {
      p <- pred[[m]]
      data.table(task = unique(pred$task), model = m,
                 mae = mean(abs(pred$year - p)),
                 r = if (sd(p) > 0) cor(pred$year, p) else NA_real_)
    } else {
      data.table(task = unique(pred$task), model = m,
                 macro_f1 = macro_f1(pred$class, pred[[m]], classes),
                 balanced_accuracy = balanced_accuracy(pred$class, pred[[m]], classes))
    }
  }))
}
