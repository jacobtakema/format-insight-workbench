empty_parser_table <- function(columns) {
  values <- lapply(columns, function(type) {
    switch(type,
      character = character(),
      integer = integer(),
      logical = logical(),
      stop(sprintf("Unsupported parser column type: %s", type), call. = FALSE)
    )
  })
  as.data.frame(values, stringsAsFactors = FALSE, optional = TRUE)
}

parser_issue <- function(severity, code, record_locator, message,
                         raw_value = NA_character_,
                         validation_layer = "semantic") {
  data.frame(
    severity = severity,
    issue_code = code,
    record_locator = record_locator,
    message = message,
    raw_value = raw_value,
    validation_layer = validation_layer,
    stringsAsFactors = FALSE
  )
}

parser_summary <- function(code, message, item_count) {
  data.frame(
    summary_code = code,
    message = message,
    item_count = as.integer(item_count),
    stringsAsFactors = FALSE
  )
}

bind_parser_rows <- function(rows, columns) {
  if (length(rows) == 0L) {
    return(empty_parser_table(columns))
  }
  do.call(rbind, rows)
}

scalar_character <- function(value) {
  if (is.null(value) || length(value) == 0L || is.na(value[[1L]])) {
    return(NA_character_)
  }
  as.character(value[[1L]])
}

new_parser_result <- function(metadata, formats, identifiers, extensions,
                              signatures, relationships, issues, summaries = NULL,
                              source_records = NULL) {
  if (is.null(summaries)) {
    summaries <- empty_parser_table(c(
      summary_code = "character",
      message = "character",
      item_count = "integer"
    ))
  }
  if (is.null(source_records)) {
    source_records <- empty_parser_table(c(
      source_record_id = "character",
      source_relative_path = "character",
      raw_content = "character"
    ))
  }
  result <- list(
    metadata = metadata,
    formats = formats,
    identifiers = identifiers,
    extensions = extensions,
    signatures = signatures,
    relationships = relationships,
    issues = issues,
    summaries = summaries,
    source_records = source_records
  )
  class(result) <- c("format_policy_import", "list")
  result
}

is_missing_scalar <- function(value) {
  length(value) != 1L || is.na(value) || !nzchar(trimws(as.character(value)))
}

is_object_member <- function(value) {
  is.list(value) && !is.null(names(value)) && length(names(value)) > 0L
}

is_valid_puid <- function(value) {
  !is_missing_scalar(value) &&
    grepl("^(fmt|x-fmt)/[1-9][0-9]*$", value)
}

stop_parser_error <- function(source_type, path, detail) {
  source_type <- as.character(source_type)
  path <- as.character(path)
  detail <- as.character(detail)
  message <- sprintf("Could not parse %s file '%s': %s", source_type, path, detail)
  condition <- structure(
    list(message = message, call = NULL, source_type = source_type, path = path),
    class = c("format_policy_parse_error", "error", "condition")
  )
  stop(condition)
}
