#' Parse a DROID binary-signature XML release
#'
#' @param path Path to a DROID binary-signature XML file.
#' @return A `format_policy_import` list of normalised data frames.
parse_droid_xml <- function(path) {
  path <- as.character(path)
  if (!file.exists(path)) {
    stop_parser_error("DROID XML", path, "file does not exist")
  }
  document <- tryCatch(
    xml2::read_xml(path, options = "NONET"),
    error = function(error) {
      detail <- conditionMessage(error)
      stop_parser_error("DROID XML", path, detail)
    }
  )
  root <- xml2::xml_root(document)
  if (xml2::xml_name(root) != "FFSignatureFile") {
    stop_parser_error("DROID XML", path, "root element must be FFSignatureFile")
  }

  expected_namespace <- "http://www.nationalarchives.gov.uk/pronom/SignatureFile"
  namespace_values <- unname(xml2::xml_ns(document))
  if (expected_namespace %in% namespace_values) {
    xml_dialect <- "pronom_signature_namespace"
  } else if (length(namespace_values) == 0L) {
    xml_dialect <- "historical_namespace_less"
  } else {
    stop_parser_error("DROID XML", path, "unsupported DROID signature namespace")
  }

  format_nodes <- xml2::xml_find_all(document, ".//*[local-name()='FileFormat']")
  signature_definition_nodes <- xml2::xml_find_all(
    document,
    ".//*[local-name()='InternalSignatureCollection']/*[local-name()='InternalSignature']"
  )
  signature_definition_ids <- xml_attribute_values(signature_definition_nodes, "ID")
  issues <- list()
  summaries <- list()

  if (length(format_nodes) == 0L) {
    issues[[length(issues) + 1L]] <- parser_issue(
      "error", "zero_formats", "FFSignatureFile",
      "The DROID binary-signature file contains no FileFormat records."
    )
  }

  format_rows <- vector("list", length(format_nodes))
  identifier_rows <- list()
  extension_rows <- list()
  signature_rows <- list()
  relationship_rows <- list()
  source_record_rows <- list()
  seen_format_ids <- character()
  seen_puids <- character()
  referenced_signature_ids <- trimws(xml2::xml_text(xml2::xml_find_all(
    document, ".//*[local-name()='FileFormat']/*[local-name()='InternalSignatureID']"
  )))
  referenced_signature_ids <- referenced_signature_ids[nzchar(referenced_signature_ids)]
  priority_target_ids <- trimws(xml2::xml_text(xml2::xml_find_all(
    document,
    ".//*[local-name()='FileFormat']/*[local-name()='HasPriorityOverFileFormatID']"
  )))
  priority_target_ids <- priority_target_ids[nzchar(priority_target_ids)]
  empty_extension_count <- 0L
  duplicate_extension_count <- 0L

  puid_values <- vapply(
    format_nodes, missing_xml_attribute, character(1), name = "PUID"
  )
  placeholder_puid <- !is.na(puid_values) &
    tolower(trimws(puid_values)) == "not yet assigned"
  valid_puid <- vapply(puid_values, is_valid_puid, logical(1))
  missing_puid <- is.na(puid_values)
  invalid_puid <- !missing_puid & !placeholder_puid & !valid_puid
  valid_puid_count <- sum(valid_puid)
  placeholder_puid_count <- sum(placeholder_puid)
  missing_puid_count <- sum(missing_puid)
  invalid_puid_count <- sum(invalid_puid)
  support_mode <- if (length(format_nodes) > 0L &&
                      valid_puid_count == length(format_nodes)) {
    "puid_comparison"
  } else if (valid_puid_count > 0L) {
    "partial_historical"
  } else {
    "snapshot_only"
  }

  for (index in seq_along(format_nodes)) {
    node <- format_nodes[[index]]
    source_record_id <- missing_xml_attribute(node, "ID")
    puid <- puid_values[[index]]
    name <- missing_xml_attribute(node, "Name")
    version <- missing_xml_attribute(node, "Version")
    locator <- if (is.na(source_record_id)) sprintf("FileFormat[%d]", index) else source_record_id

    required <- list(ID = source_record_id, Name = name)
    for (field in names(required)) {
      if (is_missing_scalar(required[[field]])) {
        issues[[length(issues) + 1L]] <- parser_issue(
          "error", paste0("missing_", tolower(field)), locator,
          sprintf("Required FileFormat attribute '%s' is missing or empty.", field)
        )
      }
    }
    if (!is_missing_scalar(source_record_id) && source_record_id %in% seen_format_ids) {
      issues[[length(issues) + 1L]] <- parser_issue(
        "error", "duplicate_format_id", locator,
        sprintf("DROID FileFormat ID '%s' occurs more than once.", source_record_id)
      )
    }
    if (valid_puid[[index]] && puid %in% seen_puids) {
      issues[[length(issues) + 1L]] <- parser_issue(
        "error", "duplicate_format_puid", locator,
        sprintf("DROID PUID '%s' occurs more than once.", puid)
      )
    }
    seen_format_ids <- c(seen_format_ids, source_record_id)
    if (valid_puid[[index]]) seen_puids <- c(seen_puids, puid)

    if (!valid_puid[[index]]) {
      source_record_rows[[length(source_record_rows) + 1L]] <- data.frame(
        source_record_id = source_record_id,
        source_relative_path = sprintf(
          "FileFormatCollection/FileFormat[%s]",
          if (is.na(source_record_id)) index else source_record_id
        ),
        raw_content = as.character(node),
        stringsAsFactors = FALSE
      )
      next
    }

    format_rows[[index]] <- data.frame(
      source_record_id = source_record_id,
      puid = puid,
      format_name = name,
      format_version = version,
      stringsAsFactors = FALSE
    )

    identifier_rows[[length(identifier_rows) + 1L]] <- data.frame(
      source_record_id = source_record_id,
      identifier_type = "PUID",
      identifier_value = puid,
      original_value = puid,
      ordinal = 1L,
      stringsAsFactors = FALSE
    )
    mime_source <- missing_xml_attribute(node, "MIMEType")
    if (!is.na(mime_source)) {
      mime_values <- trimws(strsplit(mime_source, ",", fixed = TRUE)[[1L]])
      if (any(!nzchar(mime_values))) {
        issues[[length(issues) + 1L]] <- parser_issue(
          "error", "empty_mime_identifier", locator,
          "The MIMEType attribute contains an empty identifier."
        )
      }
      mime_values <- mime_values[nzchar(mime_values)]
      for (mime_index in seq_along(mime_values)) {
        identifier_rows[[length(identifier_rows) + 1L]] <- data.frame(
          source_record_id = source_record_id,
          identifier_type = "MIME",
          identifier_value = mime_values[[mime_index]],
          original_value = mime_source,
          ordinal = as.integer(mime_index),
          stringsAsFactors = FALSE
        )
      }
    }

    extension_nodes <- xml2::xml_find_all(node, "./*[local-name()='Extension']")
    seen_extensions <- character()
    for (extension_index in seq_along(extension_nodes)) {
      original <- trimws(xml2::xml_text(extension_nodes[[extension_index]]))
      if (!nzchar(original)) {
        empty_extension_count <- empty_extension_count + 1L
        next
      }
      normalised_extension <- tolower(original)
      if (normalised_extension %in% seen_extensions) {
        duplicate_extension_count <- duplicate_extension_count + 1L
        next
      }
      seen_extensions <- c(seen_extensions, normalised_extension)
      extension_rows[[length(extension_rows) + 1L]] <- data.frame(
        source_record_id = source_record_id,
        puid = puid,
        extension = normalised_extension,
        original_value = original,
        ordinal = as.integer(extension_index),
        stringsAsFactors = FALSE
      )
    }

    signature_nodes <- xml2::xml_find_all(
      node, "./*[local-name()='InternalSignatureID']"
    )
    for (signature_node in signature_nodes) {
      signature_id <- trimws(xml2::xml_text(signature_node))
      if (!nzchar(signature_id)) {
        issues[[length(issues) + 1L]] <- parser_issue(
          "error", "empty_internal_signature_reference", locator,
          "An InternalSignatureID reference is empty."
        )
        next
      }
      referenced_signature_ids <- c(referenced_signature_ids, signature_id)
      signature_rows[[length(signature_rows) + 1L]] <- data.frame(
        source_record_id = source_record_id,
        puid = puid,
        signature_kind = "binary_internal",
        source_signature_id = signature_id,
        stringsAsFactors = FALSE
      )
    }

    priority_nodes <- xml2::xml_find_all(
      node, "./*[local-name()='HasPriorityOverFileFormatID']"
    )
    for (priority_node in priority_nodes) {
      target_id <- trimws(xml2::xml_text(priority_node))
      if (!nzchar(target_id)) {
        issues[[length(issues) + 1L]] <- parser_issue(
          "error", "empty_priority_target", locator,
          "A HasPriorityOverFileFormatID reference is empty."
        )
        next
      }
      priority_target_ids <- c(priority_target_ids, target_id)
      relationship_rows[[length(relationship_rows) + 1L]] <- data.frame(
        subject_source_record_id = source_record_id,
        subject_puid = puid,
        relationship_type = "has_priority_over",
        object_source_record_id = target_id,
        object_puid = NA_character_,
        original_relationship_type = "HasPriorityOverFileFormatID",
        stringsAsFactors = FALSE
      )
    }
  }

  if (placeholder_puid_count > 0L) {
    issues[[length(issues) + 1L]] <- parser_issue(
      "warning", "placeholder_puids", "FileFormatCollection",
      sprintf(
        "%d FileFormat records use the historical placeholder PUID 'Not yet assigned'.",
        placeholder_puid_count
      )
    )
  }
  if (missing_puid_count > 0L) {
    issues[[length(issues) + 1L]] <- parser_issue(
      "warning", "missing_puids", "FileFormatCollection",
      sprintf("%d FileFormat records have no PUID attribute.", missing_puid_count)
    )
  }
  if (invalid_puid_count > 0L) {
    issues[[length(issues) + 1L]] <- parser_issue(
      "warning", "invalid_puids", "FileFormatCollection",
      sprintf(
        "%d FileFormat records contain a non-empty value that is not a valid PRONOM PUID.",
        invalid_puid_count
      )
    )
  }
  if (empty_extension_count > 0L) {
    issues[[length(issues) + 1L]] <- parser_issue(
      "warning", "empty_extensions", "FileFormatCollection",
      sprintf(
        paste(
          "%d DROID Extension elements are empty; their source XML is preserved",
          "but no normalised extension value was created."
        ),
        empty_extension_count
      )
    )
    summaries[[length(summaries) + 1L]] <- parser_summary(
      "droid_empty_extension_count",
      sprintf(
        "%d empty Extension elements were preserved but not normalised.",
        empty_extension_count
      ),
      empty_extension_count
    )
  }
  if (duplicate_extension_count > 0L) {
    issues[[length(issues) + 1L]] <- parser_issue(
      "warning", "duplicate_extensions", "FileFormatCollection",
      sprintf(
        paste(
          "%d repeated DROID Extension values were preserved in the source XML",
          "but stored once in the normalised extension set."
        ),
        duplicate_extension_count
      )
    )
    summaries[[length(summaries) + 1L]] <- parser_summary(
      "droid_duplicate_extension_count",
      sprintf(
        "%d repeated Extension values were preserved but deduplicated during normalisation.",
        duplicate_extension_count
      ),
      duplicate_extension_count
    )
  }

  valid_format_ids <- seen_format_ids[!is.na(seen_format_ids) & nzchar(seen_format_ids)]
  unresolved_signatures <- setdiff(unique(referenced_signature_ids), signature_definition_ids)
  for (signature_id in unresolved_signatures) {
    issues[[length(issues) + 1L]] <- parser_issue(
      "error", "unresolved_internal_signature_reference", "InternalSignatureCollection",
      sprintf("InternalSignatureID '%s' has no matching InternalSignature definition.", signature_id),
      signature_id
    )
  }
  unresolved_priorities <- setdiff(unique(priority_target_ids), valid_format_ids)
  for (target_id in unresolved_priorities) {
    issues[[length(issues) + 1L]] <- parser_issue(
      "error", "unresolved_priority_target", "FileFormatCollection",
      sprintf("Priority target FileFormat ID '%s' does not exist in this DROID release.", target_id),
      target_id
    )
  }

  if (length(signature_definition_nodes) > 0L) {
    byte_sequence_count <- length(xml2::xml_find_all(
      document,
      ".//*[local-name()='InternalSignatureCollection']//*[local-name()='ByteSequence']"
    ))
    summaries[[length(summaries) + 1L]] <- parser_summary(
      "droid_signature_definitions_preserved",
      sprintf(
        "%d internal-signature definitions and %d byte-sequence structures were preserved in the source content but not normalised.",
        length(signature_definition_nodes), byte_sequence_count
      ),
      length(signature_definition_nodes)
    )
  }

  coverage_message <- switch(
    support_mode,
    puid_comparison = paste(
      "Complete valid PUID coverage; this snapshot is available to the",
      "canonical Format Explorer and PUID-based release comparison."
    ),
    partial_historical = paste(
      "Partial valid PUID coverage; only explicitly PUID-resolved records are",
      "available to canonical comparisons. Other records remain preserved and unresolved."
    ),
    snapshot_only = paste(
      "No usable PUIDs; the snapshot and its source records are preserved,",
      "but it is unavailable to the canonical Format Explorer."
    )
  )
  summaries <- c(summaries, list(
    parser_summary("droid_support_mode", coverage_message, length(format_nodes)),
    parser_summary(
      "droid_valid_puid_count",
      sprintf("%d records contain a syntactically valid PRONOM PUID.", valid_puid_count),
      valid_puid_count
    ),
    parser_summary(
      "droid_placeholder_puid_count",
      sprintf("%d records contain the placeholder PUID 'Not yet assigned'.", placeholder_puid_count),
      placeholder_puid_count
    ),
    parser_summary(
      "droid_missing_puid_count",
      sprintf("%d records have no PUID value.", missing_puid_count),
      missing_puid_count
    ),
    parser_summary(
      "droid_invalid_puid_count",
      sprintf("%d records contain an invalid non-placeholder PUID.", invalid_puid_count),
      invalid_puid_count
    )
  ))

  metadata <- data.frame(
    source_type = "droid_binary_signature",
    source_version = missing_xml_attribute(root, "Version"),
    source_created_at = missing_xml_attribute(root, "DateCreated"),
    source_filename = basename(path),
    droid_support_mode = support_mode,
    droid_xml_dialect = xml_dialect,
    droid_format_count = length(format_nodes),
    droid_valid_puid_count = valid_puid_count,
    droid_placeholder_puid_count = placeholder_puid_count,
    droid_missing_puid_count = missing_puid_count,
    droid_invalid_puid_count = invalid_puid_count,
    stringsAsFactors = FALSE
  )

  new_parser_result(
    metadata,
    bind_parser_rows(Filter(Negate(is.null), format_rows), c(
      source_record_id = "character", puid = "character", format_name = "character",
      format_version = "character"
    )),
    bind_parser_rows(identifier_rows, c(
      source_record_id = "character", identifier_type = "character",
      identifier_value = "character", original_value = "character", ordinal = "integer"
    )),
    bind_parser_rows(extension_rows, c(
      source_record_id = "character", puid = "character", extension = "character",
      original_value = "character", ordinal = "integer"
    )),
    bind_parser_rows(signature_rows, c(
      source_record_id = "character", puid = "character", signature_kind = "character",
      source_signature_id = "character"
    )),
    bind_parser_rows(relationship_rows, c(
      subject_source_record_id = "character", subject_puid = "character",
      relationship_type = "character", object_source_record_id = "character",
      object_puid = "character", original_relationship_type = "character"
    )),
    bind_parser_rows(issues, c(
      severity = "character", issue_code = "character", record_locator = "character",
      message = "character", raw_value = "character",
      validation_layer = "character"
    )),
    bind_parser_rows(summaries, c(
      summary_code = "character", message = "character", item_count = "integer"
    )),
    bind_parser_rows(source_record_rows, c(
      source_record_id = "character", source_relative_path = "character",
      raw_content = "character"
    ))
  )
}

missing_xml_attribute <- function(node, name) {
  value <- xml2::xml_attr(node, name)
  if (length(value) == 0L || is.na(value) || !nzchar(trimws(value))) NA_character_ else trimws(value)
}

xml_attribute_values <- function(nodes, name) {
  if (length(nodes) == 0L) return(character())
  values <- xml2::xml_attr(nodes, name)
  unique(values[!is.na(values) & nzchar(trimws(values))])
}
