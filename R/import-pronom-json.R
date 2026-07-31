#' Parse one PRONOM repository JSON record
#'
#' JSON Schema owns source structure. Application validation owns domain
#' invariants, and projection runs only after structural validation succeeds.
#'
#' @param path Path to a PRONOM JSON record.
#' @param schema_bundle A compiled `pronom_schema_bundle`.
#' @return A `format_policy_import` list of normalised data frames.
parse_pronom_json <- function(path, schema_bundle = load_pronom_schema()) {
  path <- as.character(path)
  if (!file.exists(path)) {
    stop_parser_error("PRONOM JSON", path, "file does not exist")
  }
  json_text <- paste(readLines(
    path, warn = FALSE, encoding = "UTF-8"
  ), collapse = "\n")
  record <- tryCatch(
    jsonlite::fromJSON(json_text, simplifyVector = FALSE),
    error = function(error) {
      stop_parser_error("PRONOM JSON", path, conditionMessage(error))
    }
  )
  structural_issues <- validate_pronom_structure(
    json_text, schema_bundle, basename(path)
  )
  schema_summaries <- pronom_schema_audit_summaries(
    json_text, schema_bundle, nrow(structural_issues)
  )
  if (nrow(structural_issues) > 0L) {
    return(empty_pronom_result(
      path, structural_issues, schema_bundle, schema_summaries
    ))
  }

  semantic_issues <- validate_pronom_semantics(record, basename(path))
  result <- project_pronom_record(
    record, path, semantic_issues, schema_bundle, schema_summaries
  )
  result$validation_schema <- schema_bundle
  result
}

validate_pronom_semantics <- function(record, locator) {
  issues <- list()
  source_record_id <- scalar_character(record$fileFormatID)
  name <- scalar_character(record$formatName)
  required_scalars <- list(fileFormatID = source_record_id, formatName = name)
  for (field in names(required_scalars)) {
    if (is_missing_scalar(required_scalars[[field]])) {
      issues[[length(issues) + 1L]] <- parser_issue(
        "error",
        paste0("missing_", normalise_field_name(field)),
        source_record_id %||% locator,
        sprintf("Required PRONOM semantic field '%s' is missing or empty.", field)
      )
    }
  }

  identifiers <- record$identifiers
  if (is.null(identifiers) || length(identifiers) == 0L) {
    issues[[length(issues) + 1L]] <- parser_issue(
      "error", "empty_identifiers", source_record_id %||% locator,
      "The PRONOM record must contain at least one identifier."
    )
  }
  puid_values <- vapply(
    identifiers %||% list(),
    function(identifier) {
      if (toupper(identifier$identifierType) == "PUID") {
        identifier$identifierText
      } else {
        NA_character_
      }
    },
    character(1)
  )
  puid_values <- puid_values[!is.na(puid_values)]
  if (length(puid_values) == 0L) {
    issues[[length(issues) + 1L]] <- parser_issue(
      "error", "missing_puid", source_record_id %||% locator,
      "The PRONOM record has no PUID identifier."
    )
  } else {
    unique_puids <- unique(puid_values)
    if (length(puid_values) > 1L && length(unique_puids) == 1L) {
      issues[[length(issues) + 1L]] <- parser_issue(
        "error", "duplicate_puid_identifier", source_record_id %||% locator,
        sprintf("The PUID identifier '%s' occurs more than once.", unique_puids[[1L]])
      )
    }
    if (length(unique_puids) > 1L) {
      issues[[length(issues) + 1L]] <- parser_issue(
        "error", "conflicting_puid_identifiers", source_record_id %||% locator,
        sprintf(
          "The record contains conflicting PUID identifiers: %s.",
          paste(unique_puids, collapse = ", ")
        )
      )
    }
    invalid <- unique_puids[!vapply(unique_puids, is_valid_puid, logical(1))]
    if (length(invalid) > 0L) {
      issues[[length(issues) + 1L]] <- parser_issue(
        "error", "invalid_puid", source_record_id %||% locator,
        sprintf("Invalid PRONOM PUID syntax: %s.", paste(invalid, collapse = ", "))
      )
    }
  }

  for (index in seq_along(record$internalSignatures %||% list())) {
    signature <- record$internalSignatures[[index]]
    if (is_missing_scalar(scalar_character(signature$signatureID))) {
      issues[[length(issues) + 1L]] <- parser_issue(
        "error", "missing_internal_signature_id",
        sprintf("%s /internalSignatures/%d", source_record_id %||% locator, index - 1L),
        "A PRONOM internal signature has no signatureID."
      )
    }
  }
  for (index in seq_along(record$externalSignatures %||% list())) {
    signature <- record$externalSignatures[[index]]
    if (is_missing_scalar(scalar_character(signature$externalSignature))) {
      issues[[length(issues) + 1L]] <- parser_issue(
        "warning", "empty_external_signature",
        sprintf("%s /externalSignatures/%d", source_record_id %||% locator, index - 1L),
        paste(
          "A PRONOM external signature value is null, empty or whitespace-only;",
          "the child record was preserved but not normalised."
        )
      )
    }
  }
  bind_parser_rows(issues, parser_issue_columns())
}

project_pronom_record <- function(record, path, issues, schema_bundle,
                                  schema_summaries) {
  source_record_id <- as.character(record$fileFormatID)
  identifiers <- record$identifiers %||% list()
  puid_values <- vapply(
    identifiers,
    function(identifier) {
      if (toupper(identifier$identifierType) == "PUID") {
        identifier$identifierText
      } else {
        NA_character_
      }
    },
    character(1)
  )
  puid_values <- puid_values[!is.na(puid_values)]
  puid <- if (length(puid_values) > 0L) puid_values[[1L]] else NA_character_

  identifier_rows <- lapply(seq_along(identifiers), function(index) {
    identifier <- identifiers[[index]]
    data.frame(
      source_record_id = source_record_id,
      identifier_type = identifier$identifierType,
      identifier_value = identifier$identifierText,
      original_value = identifier$identifierText,
      ordinal = as.integer(index),
      stringsAsFactors = FALSE
    )
  })

  extension_rows <- list()
  unsupported_external <- 0L
  extension_ordinal <- 0L
  for (signature in record$externalSignatures %||% list()) {
    external_value <- scalar_character(signature$externalSignature)
    if (is_missing_scalar(external_value)) next
    if (!identical(signature$signatureType, "File extension")) {
      unsupported_external <- unsupported_external + 1L
      next
    }
    extension_ordinal <- extension_ordinal + 1L
    extension_rows[[length(extension_rows) + 1L]] <- data.frame(
      source_record_id = source_record_id,
      puid = puid,
      extension = tolower(external_value),
      original_value = external_value,
      ordinal = extension_ordinal,
      stringsAsFactors = FALSE
    )
  }

  signature_rows <- lapply(
    record$internalSignatures %||% list(),
    function(signature) {
      data.frame(
        source_record_id = source_record_id,
        puid = puid,
        signature_kind = "binary_internal",
        source_signature_id = scalar_character(signature$signatureID),
        stringsAsFactors = FALSE
      )
    }
  )

  relationship_rows <- lapply(
    record$relationships %||% list(),
    function(relationship) {
      data.frame(
        subject_source_record_id = source_record_id,
        subject_puid = puid,
        relationship_type = normalise_relationship_type(
          relationship$relationshipType
        ),
        object_source_record_id = as.character(relationship$relatedFormatID),
        object_puid = NA_character_,
        original_relationship_type = relationship$relationshipType,
        stringsAsFactors = FALSE
      )
    }
  )

  summaries <- pronom_projection_summaries(
    record, unsupported_external
  )
  summaries <- rbind(summaries, schema_summaries)
  metadata <- cbind(
    data.frame(
      source_type = "pronom_json",
      source_version = NA_character_,
      source_created_at = NA_character_,
      source_filename = basename(path),
      stringsAsFactors = FALSE
    ),
    pronom_schema_metadata(schema_bundle)
  )
  new_parser_result(
    metadata,
    data.frame(
      source_record_id = source_record_id,
      puid = puid,
      format_name = record$formatName,
      format_version = scalar_character(record$version),
      stringsAsFactors = FALSE
    ),
    bind_parser_rows(identifier_rows, pronom_identifier_columns()),
    bind_parser_rows(extension_rows, pronom_extension_columns()),
    bind_parser_rows(signature_rows, pronom_signature_columns()),
    bind_parser_rows(relationship_rows, pronom_relationship_columns()),
    issues,
    summaries
  )
}

pronom_projection_summaries <- function(record, unsupported_external) {
  summaries <- list()
  if (unsupported_external > 0L) {
    summaries[[length(summaries) + 1L]] <- parser_summary(
      "pronom_external_signatures_preserved",
      "External signature types other than file extensions were preserved in the source content but not normalised.",
      unsupported_external
    )
  }
  detailed_internal <- sum(vapply(
    record$internalSignatures %||% list(),
    function(signature) length(setdiff(names(signature), "signatureID")) > 0L,
    logical(1)
  ))
  if (detailed_internal > 0L) {
    summaries[[length(summaries) + 1L]] <- parser_summary(
      "pronom_signature_details_preserved",
      "Internal-signature names, notes and byte sequences were preserved in the source content but not normalised.",
      detailed_internal
    )
  }
  related_names <- sum(vapply(
    record$relationships %||% list(),
    function(relationship) !is.null(relationship$relatedFormatName),
    logical(1)
  ))
  if (related_names > 0L) {
    summaries[[length(summaries) + 1L]] <- parser_summary(
      "pronom_related_names_preserved",
      "Related-format display names were preserved in the source content but not normalised.",
      related_names
    )
  }
  supported <- c(
    "fileFormatID", "formatName", "version", "identifiers",
    "externalSignatures", "internalSignatures", "relationships"
  )
  unsupported <- setdiff(names(record), supported)
  unsupported <- unsupported[
    vapply(record[unsupported], function(value) !is.null(value), logical(1))
  ]
  if (length(unsupported) > 0L) {
    summaries[[length(summaries) + 1L]] <- parser_summary(
      "pronom_descriptive_metadata_preserved",
      sprintf(
        "PRONOM descriptive metadata was preserved in the source content but not normalised (%s).",
        paste(unsupported, collapse = ", ")
      ),
      length(unsupported)
    )
  }
  bind_parser_rows(summaries, c(
    summary_code = "character", message = "character", item_count = "integer"
  ))
}

empty_pronom_result <- function(path, issues, schema_bundle, schema_summaries) {
  metadata <- cbind(
    data.frame(
      source_type = "pronom_json",
      source_version = NA_character_,
      source_created_at = NA_character_,
      source_filename = basename(path),
      stringsAsFactors = FALSE
    ),
    pronom_schema_metadata(schema_bundle)
  )
  result <- new_parser_result(
    metadata,
    empty_parser_table(pronom_format_columns()),
    empty_parser_table(pronom_identifier_columns()),
    empty_parser_table(pronom_extension_columns()),
    empty_parser_table(pronom_signature_columns()),
    empty_parser_table(pronom_relationship_columns()),
    issues,
    schema_summaries
  )
  result$validation_schema <- schema_bundle
  result
}

pronom_format_columns <- function() c(
  source_record_id = "character", puid = "character",
  format_name = "character", format_version = "character"
)

pronom_identifier_columns <- function() c(
  source_record_id = "character", identifier_type = "character",
  identifier_value = "character", original_value = "character",
  ordinal = "integer"
)

pronom_extension_columns <- function() c(
  source_record_id = "character", puid = "character",
  extension = "character", original_value = "character", ordinal = "integer"
)

pronom_signature_columns <- function() c(
  source_record_id = "character", puid = "character",
  signature_kind = "character", source_signature_id = "character"
)

pronom_relationship_columns <- function() c(
  subject_source_record_id = "character", subject_puid = "character",
  relationship_type = "character", object_source_record_id = "character",
  object_puid = "character", original_relationship_type = "character"
)

parser_issue_columns <- function() c(
  severity = "character", issue_code = "character",
  record_locator = "character", message = "character",
  raw_value = "character", validation_layer = "character"
)

normalise_relationship_type <- function(value) {
  if (is.na(value)) return(NA_character_)
  gsub("[^a-z0-9]+", "_", tolower(trimws(value)))
}

normalise_field_name <- function(value) {
  gsub("([a-z0-9])([A-Z])", "\\1_\\2", value) |>
    tolower()
}

`%||%` <- function(left, right) {
  if (is.null(left) || length(left) == 0L || all(is.na(left))) right else left
}
