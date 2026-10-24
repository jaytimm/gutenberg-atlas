# Deterministic analysis labels. These labels are derived for description and
# modeling; they are not written back into the production release.

assign_genre <- function(bookshelves, subjects, locc) {
  b <- tolower(bookshelves)
  s <- tolower(subjects)
  primary_loc <- toupper(trimws(sub(";.*$", "", locc)))

  poetry <- grepl("category:\\s*poetry\\b", b, perl = TRUE) |
    grepl("(^|;)\\s*[^;]*\\bpoetry\\b[^;]*(;|$)", s, perl = TRUE) &
      !grepl("poetry --", s, fixed = TRUE)
  drama <- grepl("category:\\s*plays/films/dramas\\b", b, perl = TRUE) |
    grepl("(^|;)\\s*[^;]*\\b(drama|plays)\\b[^;]*(;|$)", s, perl = TRUE)
  fiction <- grepl(
    "category:\\s*(novels|historical novels|short stories|adventure|romance|crime, thrillers and mystery)\\b",
    b, perl = TRUE
  ) | grepl("(^|;)\\s*[^;]*\\b(fiction|stories)\\b[^;]*(;|$)", s, perl = TRUE) |
    grepl("^PZ", primary_loc)

  creative_count <- fiction + poetry + drama
  literature <- grepl("^P", primary_loc)
  genre <- rep("excluded", length(b))
  genre[creative_count == 1L & fiction] <- "fiction"
  genre[creative_count == 1L & poetry] <- "poetry"
  genre[creative_count == 1L & drama] <- "drama"
  genre[creative_count == 0L & !literature & nzchar(primary_loc)] <- "nonfiction"
  genre
}

assign_period <- function(year) {
  period <- rep(NA_character_, length(year))
  keep <- !is.na(year) & year <= 1924
  period[keep & year <= 1849] <- "1700-1849"
  period[keep & year >= 1850 & year <= 1899] <- "1850-1899"
  period[keep & year >= 1900 & year <= 1924] <- "1900-1924"
  period
}

assign_gender <- function(gender) {
  out <- rep(NA_character_, length(gender))
  out[gender %in% c("male", "female")] <- gender[gender %in% c("male", "female")]
  out
}

assign_period25 <- function(year) {
  period <- rep(NA_character_, length(year))
  keep <- !is.na(year) & year >= 1800 & year <= 1924
  start <- 1800L + 25L * ((year[keep] - 1800L) %/% 25L)
  period[keep] <- sprintf("%d-%d", start, start + 24L)
  period
}
