nl_profile_name <- "NL Rijksoverheid \u2013 Norm Voorkeursformaten 2024"
nl_profile_source_url <- paste0(
  "https://www.nationaalarchief.nl/sites/default/files/field-file/",
  "Norm%20Voorkeursformaten%20-%20download%20lijst%20en%20onderbouwing%202024.xlsx"
)

parse_nl_profile_xlsx <- function(path) {
  if (!file.exists(path)) {
    stop_parser_error("NL profile XLSX", path, "file does not exist")
  }
  sheets <- tryCatch(
    readxl::excel_sheets(path),
    error = function(error) stop_parser_error(
      "NL profile XLSX", path, conditionMessage(error)
    )
  )
  required_sheets <- c("Lijst Voorkeursformaten", "Onderbouwing")
  missing_sheets <- setdiff(required_sheets, sheets)
  if (length(missing_sheets) > 0L) {
    stop_parser_error(
      "NL profile XLSX", path,
      sprintf("required worksheet is missing: %s", paste(missing_sheets, collapse = ", "))
    )
  }
  preferred <- read_profile_sheet(path, required_sheets[[1L]])
  rationale <- read_profile_sheet(path, required_sheets[[2L]])
  require_profile_columns(
    preferred,
    c(
      "Informatiesoort", "Extensie", "Versie en/of profiel", "Formaat naam",
      "Status", "PUID", "Opmerkingen"
    ),
    required_sheets[[1L]], path
  )
  require_profile_columns(
    rationale,
    c(
      "Informatiesoort", "Formaat", "Open standaard",
      "Adoptie en ondersteuning", "Onafhankelijkheid \n& interoperabiliteit",
      "Transparantie", "Zelf-documenterend", "Patenten en licenties", "Toelichting"
    ),
    required_sheets[[2L]], path
  )

  parsed_entries <- parse_preferred_format_rows(preferred)
  rationale_rows <- parse_profile_rationale_rows(rationale)
  rationale_links <- link_profile_rationale(
    parsed_entries$entries, rationale_rows
  )
  if (nrow(rationale_links) > 0L) {
    for (source_row in unique(rationale_links$entry_source_row)) {
      linked_rows <- rationale_links$rationale_source_row[
        rationale_links$entry_source_row == source_row
      ]
      text <- rationale_rows$rationale[
        match(linked_rows, rationale_rows$source_row)
      ]
      text <- unique(text[!is.na(text) & nzchar(text)])
      if (length(text) > 0L) {
        parsed_entries$entries$rationale[
          parsed_entries$entries$source_row == source_row
        ] <- paste(text, collapse = "\n\n")
      }
    }
  }

  issues <- parsed_entries$issues
  duplicate_values <- unique(parsed_entries$mappings$puid[
    !is.na(parsed_entries$mappings$puid) &
      duplicated(parsed_entries$mappings$puid)
  ])
  if (length(duplicate_values) > 0L) {
    for (puid in duplicate_values) {
      issues <- rbind(issues, parser_issue(
        "warning", "profile_duplicate_puid", puid,
        sprintf("PUID '%s' is referenced by more than one profile entry.", puid),
        puid
      ))
    }
  }
  unmatched_rationale <- setdiff(
    rationale_rows$source_row, unique(rationale_links$rationale_source_row)
  )
  summaries <- rbind(
    parser_summary(
      "profile_entry_count",
      sprintf("%d usable profile entries were found.", nrow(parsed_entries$entries)),
      nrow(parsed_entries$entries)
    ),
    parser_summary(
      "profile_rationale_count",
      sprintf("%d rationale rows were preserved.", nrow(rationale_rows)),
      nrow(rationale_rows)
    ),
    parser_summary(
      "profile_unlinked_rationale_count",
      sprintf(
        "%d rationale rows have no deterministic exact-label link to a profile entry.",
        length(unmatched_rationale)
      ),
      length(unmatched_rationale)
    )
  )

  result <- list(
    metadata = data.frame(
      profile_name = nl_profile_name,
      profile_version = "2024",
      publisher = "Nationaal Archief",
      publication_date = as.Date("2024-01-01"),
      source_name = basename(path),
      source_url = nl_profile_source_url,
      stringsAsFactors = FALSE
    ),
    entries = parsed_entries$entries,
    mappings = parsed_entries$mappings,
    rationales = rationale_rows,
    rationale_links = rationale_links,
    issues = issues,
    summaries = summaries
  )
  class(result) <- c("format_profile_import", "list")
  result
}

read_profile_sheet <- function(path, sheet) {
  value <- tryCatch(
    readxl::read_excel(
      path, sheet = sheet, col_types = "text", trim_ws = FALSE,
      .name_repair = "minimal"
    ),
    error = function(error) stop_parser_error(
      "NL profile XLSX", path,
      sprintf("worksheet '%s' could not be read: %s", sheet, conditionMessage(error))
    )
  )
  value <- as.data.frame(value, stringsAsFactors = FALSE, check.names = FALSE)
  names(value) <- gsub("\\r\\n?", "\n", names(value))
  value
}

require_profile_columns <- function(rows, required, sheet, path) {
  missing <- setdiff(required, names(rows))
  if (length(missing) > 0L) {
    stop_parser_error(
      "NL profile XLSX", path,
      sprintf(
        "worksheet '%s' is missing required columns: %s",
        sheet, paste(missing, collapse = ", ")
      )
    )
  }
  invisible(TRUE)
}

parse_preferred_format_rows <- function(rows) {
  entries <- list()
  mappings <- list()
  issues <- list()
  current_category <- NA_character_
  for (index in seq_len(nrow(rows))) {
    source_row <- index + 1L
    values <- lapply(rows[index, , drop = FALSE], trim_profile_cell)
    names(values) <- names(rows)
    other_values <- unlist(values[names(values) != "Informatiesoort"], use.names = FALSE)
    is_header <- !is.na(values$Informatiesoort) && all(is.na(other_values))
    if (is_header) {
      current_category <- values$Informatiesoort
      next
    }
    if (all(is.na(other_values))) next

    display_name <- values[["Formaat naam"]]
    if (is.na(display_name)) display_name <- values$Extensie
    if (is.na(display_name)) {
      display_name <- sprintf("Source row %d", source_row)
      issues[[length(issues) + 1L]] <- parser_issue(
        "warning", "profile_missing_format_label", as.character(source_row),
        "The profile row has no format name or extension label."
      )
    }
    status <- normalise_profile_status(values$Status)
    if (is.na(values$Status)) {
      issues[[length(issues) + 1L]] <- parser_issue(
        "warning", "profile_missing_status", as.character(source_row),
        "The profile row has no preference status; it was retained as under review."
      )
    } else if (is.na(status)) {
      issues[[length(issues) + 1L]] <- parser_issue(
        "warning", "profile_unknown_status", as.character(source_row),
        sprintf("Unknown preference status '%s'; the entry was retained as under review.", values$Status),
        values$Status
      )
    }
    if (is.na(status)) status <- "under_review"
    parsed_puids <- parse_profile_puid_value(values$PUID, source_row)
    issues <- c(issues, parsed_puids$issues)
    entry_mapping_status <- if (identical(parsed_puids$kind, "missing")) {
      "no_puid"
    } else if (identical(parsed_puids$kind, "none")) {
      "no_puid"
    } else if (any(parsed_puids$mappings$syntax_status == "invalid")) {
      "invalid_puid"
    } else {
      "unmapped"
    }
    if (identical(parsed_puids$kind, "missing")) {
      issues[[length(issues) + 1L]] <- parser_issue(
        "warning", "profile_missing_puid", as.character(source_row),
        "The profile entry has no PUID value."
      )
    } else if (identical(parsed_puids$kind, "none")) {
      issues[[length(issues) + 1L]] <- parser_issue(
        "warning", "profile_unmapped_entry", as.character(source_row),
        "The source explicitly states that no PUID is available.", values$PUID
      )
    }
    raw_row <- jsonlite::toJSON(
      as.list(rows[index, , drop = FALSE]), auto_unbox = TRUE,
      na = "null", null = "null"
    )
    entries[[length(entries) + 1L]] <- data.frame(
      source_sheet = "Lijst Voorkeursformaten",
      source_row = source_row,
      category = current_category,
      information_subtype = values$Informatiesoort,
      format_label = display_name,
      extension_label = values$Extensie,
      version_label = values[["Versie en/of profiel"]],
      preference_status = status,
      source_status = values$Status,
      notes = values$Opmerkingen,
      rationale = NA_character_,
      raw_source_data = as.character(raw_row),
      mapping_status = entry_mapping_status,
      stringsAsFactors = FALSE
    )
    if (nrow(parsed_puids$mappings) > 0L) {
      mappings[[length(mappings) + 1L]] <- parsed_puids$mappings
    }
  }
  list(
    entries = bind_profile_rows(entries, profile_entry_columns()),
    mappings = bind_profile_rows(mappings, profile_mapping_columns()),
    issues = bind_parser_rows(issues, parser_issue_columns())
  )
}

parse_profile_puid_value <- function(value, source_row) {
  empty <- empty_parser_table(profile_mapping_columns())
  if (is.na(value)) return(list(kind = "missing", mappings = empty, issues = list()))
  if (tolower(value) == "geen") return(list(kind = "none", mappings = empty, issues = list()))
  tokens <- unlist(strsplit(gsub("[\r\n]+", " ", value), "[[:space:],;]+"))
  tokens <- tokens[nzchar(tokens)]
  rows <- list()
  issues <- list()
  ordinal <- 0L
  seen <- character()
  for (token in tokens) {
    range_match <- regexec("^(fmt|x-fmt)/([1-9][0-9]*)-([1-9][0-9]*)$", token)
    range_parts <- regmatches(token, range_match)[[1L]]
    values <- if (length(range_parts) > 0L) {
      first <- as.integer(range_parts[[3L]])
      last <- as.integer(range_parts[[4L]])
      if (last < first || last - first > 1000L) character() else {
        sprintf("%s/%d", range_parts[[2L]], seq.int(first, last))
      }
    } else if (is_valid_puid(token)) {
      token
    } else {
      character()
    }
    if (length(values) == 0L) {
      ordinal <- ordinal + 1L
      rows[[length(rows) + 1L]] <- profile_mapping_row(
        source_row, NA_character_, token, "invalid", ordinal
      )
      issues[[length(issues) + 1L]] <- parser_issue(
        "warning", "profile_invalid_puid", as.character(source_row),
        sprintf("Profile PUID value '%s' is not a valid PRONOM PUID.", token), token
      )
      next
    }
    for (puid in values) {
      if (puid %in% seen) {
        issues[[length(issues) + 1L]] <- parser_issue(
          "warning", "profile_duplicate_puid", as.character(source_row),
          sprintf("PUID '%s' occurs more than once in this profile entry.", puid), puid
        )
        next
      }
      seen <- c(seen, puid)
      ordinal <- ordinal + 1L
      rows[[length(rows) + 1L]] <- profile_mapping_row(
        source_row, puid, token, "valid", ordinal
      )
    }
  }
  list(
    kind = "values",
    mappings = bind_profile_rows(rows, profile_mapping_columns()),
    issues = issues
  )
}

profile_mapping_row <- function(source_row, puid, raw_puid, syntax_status, ordinal) {
  data.frame(
    entry_source_row = as.integer(source_row),
    puid = puid,
    raw_puid = raw_puid,
    syntax_status = syntax_status,
    ordinal = as.integer(ordinal),
    stringsAsFactors = FALSE
  )
}

parse_profile_rationale_rows <- function(rows) {
  result <- list()
  current_category <- NA_character_
  for (index in seq_len(nrow(rows))) {
    source_row <- index + 1L
    values <- lapply(rows[index, , drop = FALSE], trim_profile_cell)
    names(values) <- names(rows)
    other <- unlist(values[names(values) != "Informatiesoort"], use.names = FALSE)
    if (!is.na(values$Informatiesoort) && all(is.na(other))) {
      current_category <- values$Informatiesoort
      next
    }
    if (all(is.na(other))) next
    result[[length(result) + 1L]] <- data.frame(
      source_sheet = "Onderbouwing",
      source_row = source_row,
      category = current_category,
      information_subtype = values$Informatiesoort,
      format_label = values$Formaat,
      open_standard = values[["Open standaard"]],
      adoption_support = values[["Adoptie en ondersteuning"]],
      independence_interoperability = values[["Onafhankelijkheid \n& interoperabiliteit"]],
      transparency = values$Transparantie,
      self_documenting = values[["Zelf-documenterend"]],
      patents_licences = values[["Patenten en licenties"]],
      rationale = values$Toelichting,
      raw_source_data = as.character(jsonlite::toJSON(
        as.list(rows[index, , drop = FALSE]), auto_unbox = TRUE,
        na = "null", null = "null"
      )),
      stringsAsFactors = FALSE
    )
  }
  bind_profile_rows(result, profile_rationale_columns())
}

link_profile_rationale <- function(entries, rationales) {
  if (nrow(entries) == 0L || nrow(rationales) == 0L) {
    return(empty_parser_table(c(
      entry_source_row = "integer", rationale_source_row = "integer",
      link_method = "character"
    )))
  }
  rationale_keys <- normalise_profile_label(rationales$format_label)
  links <- list()
  for (index in seq_len(nrow(entries))) {
    candidates <- profile_entry_label_candidates(entries[index, , drop = FALSE])
    positions <- which(rationale_keys %in% candidates & !is.na(rationale_keys))
    keys <- rationale_keys[positions]
    positions <- positions[!duplicated(keys) & !duplicated(keys, fromLast = TRUE)]
    for (position in positions) {
      links[[length(links) + 1L]] <- data.frame(
        entry_source_row = entries$source_row[[index]],
        rationale_source_row = rationales$source_row[[position]],
        link_method = "exact_source_label",
        stringsAsFactors = FALSE
      )
    }
  }
  bind_profile_rows(links, c(
    entry_source_row = "integer", rationale_source_row = "integer",
    link_method = "character"
  ))
}

profile_entry_label_candidates <- function(entry) {
  values <- c(entry$extension_label, entry$format_label)
  extension <- entry$extension_label[[1L]]
  if (!is.na(extension)) {
    values <- c(values, unlist(strsplit(extension, "[/\r\n]+")))
  }
  unique(na.omit(normalise_profile_label(values)))
}

normalise_profile_label <- function(value) {
  value <- gsub("\u00a0", " ", value, fixed = TRUE)
  value <- toupper(trimws(gsub("[[:space:]]+", " ", value)))
  missing <- is.na(value) | !nzchar(value)
  value[missing] <- NA_character_
  value
}

normalise_profile_status <- function(value) {
  if (is.na(value)) return(NA_character_)
  switch(
    tolower(trimws(value)),
    voorkeur = "preferred",
    acceptabel = "acceptable",
    NA_character_
  )
}

trim_profile_cell <- function(value) {
  if (length(value) == 0L || is.na(value[[1L]])) return(NA_character_)
  value <- trimws(as.character(value[[1L]]))
  if (!nzchar(value)) NA_character_ else value
}

bind_profile_rows <- function(rows, columns) {
  if (length(rows) == 0L) return(empty_parser_table(columns))
  do.call(rbind, rows)
}

profile_entry_columns <- function() c(
  source_sheet = "character", source_row = "integer", category = "character",
  information_subtype = "character", format_label = "character",
  extension_label = "character", version_label = "character",
  preference_status = "character", source_status = "character",
  notes = "character", rationale = "character", raw_source_data = "character",
  mapping_status = "character"
)

profile_mapping_columns <- function() c(
  entry_source_row = "integer", puid = "character", raw_puid = "character",
  syntax_status = "character", ordinal = "integer"
)

profile_rationale_columns <- function() c(
  source_sheet = "character", source_row = "integer", category = "character",
  information_subtype = "character", format_label = "character",
  open_standard = "character", adoption_support = "character",
  independence_interoperability = "character", transparency = "character",
  self_documenting = "character", patents_licences = "character",
  rationale = "character", raw_source_data = "character"
)
