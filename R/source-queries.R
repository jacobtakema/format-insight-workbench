list_source_snapshots <- function(connection) {
  rows <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT",
      "  CAST(snapshot.snapshot_id AS VARCHAR) AS snapshot_id,",
      "  snapshot.source_type,",
      "  snapshot.source_version,",
      "  snapshot.source_filename,",
      "  snapshot.source_relative_path,",
      "  snapshot.imported_at,",
      "  snapshot.import_status,",
      "  coalesce(max(profile.format_count), count(format.source_format_id)) AS format_count",
      "FROM source_snapshot AS snapshot",
      "LEFT JOIN source_format AS format",
      "  ON format.snapshot_id = snapshot.snapshot_id",
      "LEFT JOIN droid_snapshot_profile AS profile",
      "  ON profile.snapshot_id = snapshot.snapshot_id",
      "GROUP BY ALL",
      "ORDER BY snapshot.imported_at DESC, snapshot.source_filename"
    )
  )
  rows$imported_at <- format_source_timestamp(rows$imported_at)
  rows
}

list_import_summaries <- function(connection, snapshot_id) {
  DBI::dbGetQuery(
    connection,
    paste(
      "SELECT summary_code, message, item_count",
      "FROM source_import_summary",
      "WHERE snapshot_id = ?",
      "ORDER BY summary_code"
    ),
    params = list(snapshot_id)
  )
}

list_source_snapshot_choices <- function(connection, source_group) {
  source_types <- switch(
    source_group,
    pronom = c("pronom_repository", "pronom_json"),
    droid = "droid_binary_signature",
    stop("Unknown source snapshot group.", call. = FALSE)
  )
  placeholders <- paste(rep("?", length(source_types)), collapse = ", ")
  rows <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT",
      " CAST(snapshot.snapshot_id AS VARCHAR) AS snapshot_id,",
      " snapshot.source_type, snapshot.source_version,",
      " snapshot.source_filename, snapshot.imported_at",
      "FROM source_snapshot AS snapshot",
      "LEFT JOIN droid_snapshot_profile AS profile",
      " ON profile.snapshot_id = snapshot.snapshot_id",
      sprintf("WHERE snapshot.source_type IN (%s)", placeholders),
      " AND (profile.support_mode IS NULL OR profile.support_mode <> 'snapshot_only')",
      "ORDER BY snapshot.imported_at DESC, snapshot.source_filename"
    ),
    params = as.list(source_types)
  )
  rows$imported_at <- format_source_timestamp(rows$imported_at)
  rows
}

snapshot_choice_labels <- function(snapshots) {
  if (nrow(snapshots) == 0L) return(character())
  version <- ifelse(
    is.na(snapshots$source_version) | !nzchar(snapshots$source_version),
    "version unavailable", snapshots$source_version
  )
  labels <- sprintf("%s — %s (%s)", snapshots$source_filename, version, snapshots$source_type)
  stats::setNames(snapshots$snapshot_id, labels)
}

compare_droid_snapshots <- function(connection, left_snapshot_id,
                                    right_snapshot_id) {
  snapshot_ids <- c(left_snapshot_id, right_snapshot_id)
  profiles <- lapply(snapshot_ids, function(snapshot_id) {
    DBI::dbGetQuery(
      connection,
      paste(
        "SELECT support_mode FROM droid_snapshot_profile",
        "WHERE snapshot_id = ?"
      ),
      params = list(snapshot_id)
    )
  })
  if (any(vapply(profiles, nrow, integer(1)) != 1L)) {
    stop("Both snapshots must be imported DROID binary-signature releases.",
         call. = FALSE)
  }
  modes <- vapply(profiles, function(profile) profile$support_mode[[1L]], character(1))
  if (any(modes == "snapshot_only")) {
    stop(
      paste(
        "Canonical DROID release comparison is unavailable for snapshot-only",
        "releases because they contain no usable PUIDs."
      ),
      call. = FALSE
    )
  }
  DBI::dbGetQuery(
    connection,
    paste(
      "WITH left_formats AS (",
      " SELECT puid, format_name, format_version FROM source_format",
      " WHERE snapshot_id = ?",
      "), right_formats AS (",
      " SELECT puid, format_name, format_version FROM source_format",
      " WHERE snapshot_id = ?",
      ")",
      "SELECT coalesce(left_formats.puid, right_formats.puid) AS puid,",
      " left_formats.puid IS NOT NULL AS present_left,",
      " right_formats.puid IS NOT NULL AS present_right,",
      " left_formats.format_name AS left_name,",
      " right_formats.format_name AS right_name,",
      " left_formats.format_version AS left_version,",
      " right_formats.format_version AS right_version",
      "FROM left_formats FULL OUTER JOIN right_formats",
      " ON right_formats.puid = left_formats.puid",
      "ORDER BY CASE WHEN split_part(coalesce(left_formats.puid, right_formats.puid), '/', 1)",
      " = 'fmt' THEN 0 ELSE 1 END,",
      " try_cast(split_part(coalesce(left_formats.puid, right_formats.puid), '/', 2) AS INTEGER)"
    ),
    params = list(left_snapshot_id, right_snapshot_id)
  )
}

list_integrated_formats <- function(connection, pronom_snapshot_id, droid_snapshot_id) {
  pronom_snapshot_id <- snapshot_parameter(pronom_snapshot_id)
  droid_snapshot_id <- snapshot_parameter(droid_snapshot_id)
  DBI::dbGetQuery(
    connection,
    paste(
      "WITH active_puids AS (",
      " SELECT puid FROM source_format WHERE snapshot_id = ?",
      " UNION",
      " SELECT puid FROM source_format WHERE snapshot_id = ?",
      "), observations AS (",
      " SELECT puid,",
      "  max(CASE WHEN snapshot_id = ? THEN source_format_id END) AS pronom_format_id,",
      "  max(CASE WHEN snapshot_id = ? THEN source_format_id END) AS droid_format_id,",
      "  max(CASE WHEN snapshot_id = ? THEN format_name END) AS pronom_name,",
      "  max(CASE WHEN snapshot_id = ? THEN format_name END) AS droid_name,",
      "  max(CASE WHEN snapshot_id = ? THEN format_version END) AS pronom_version,",
      "  max(CASE WHEN snapshot_id = ? THEN format_version END) AS droid_version",
      " FROM source_format",
      " WHERE snapshot_id IN (?, ?)",
      " GROUP BY puid",
      ")",
      "SELECT active.puid,",
      " coalesce(observation.pronom_name, observation.droid_name, '') AS format_name,",
      " coalesce(observation.pronom_version, observation.droid_version, '') AS format_version,",
      " coalesce((SELECT string_agg(DISTINCT identifier_value, ', ' ORDER BY identifier_value)",
      "   FROM source_format_identifier",
      "   WHERE source_format_id = coalesce(observation.pronom_format_id, observation.droid_format_id)",
      "     AND upper(identifier_type) = 'MIME'), '') AS mime_types,",
      " coalesce((SELECT string_agg(DISTINCT extension, ', ' ORDER BY extension)",
      "   FROM source_format_extension",
      "   WHERE source_format_id = coalesce(observation.pronom_format_id, observation.droid_format_id)), '') AS extensions,",
      " observation.pronom_format_id IS NOT NULL AS present_in_pronom,",
      " observation.droid_format_id IS NOT NULL AS present_in_droid,",
      " coalesce((SELECT count(DISTINCT source_signature_id)",
      "   FROM source_format_signature",
      "   WHERE source_format_id = observation.droid_format_id",
      "     AND signature_kind = 'binary_internal'), 0) AS droid_internal_signature_references",
      "FROM active_puids AS active",
      "JOIN observations AS observation ON observation.puid = active.puid",
      "ORDER BY CASE WHEN split_part(active.puid, '/', 1) = 'fmt' THEN 0 ELSE 1 END,",
      " try_cast(split_part(active.puid, '/', 2) AS INTEGER), active.puid"
    ),
    params = as.list(c(
      pronom_snapshot_id, droid_snapshot_id,
      pronom_snapshot_id, droid_snapshot_id,
      pronom_snapshot_id, droid_snapshot_id,
      pronom_snapshot_id, droid_snapshot_id,
      pronom_snapshot_id, droid_snapshot_id
    ))
  )
}

filter_integrated_formats <- function(formats, search_text, coverage_filter = "all",
                                      missing_mime = FALSE, missing_extension = FALSE,
                                      no_droid_signature = FALSE) {
  search_text <- trimws(search_text %||% "")
  if (nrow(formats) == 0L) return(formats)
  keep <- rep(TRUE, nrow(formats))
  if (nzchar(search_text)) {
    searchable <- apply(formats, 1L, function(row) paste(row, collapse = " "))
    keep <- keep & grepl(tolower(search_text), tolower(searchable), fixed = TRUE)
  }
  if (identical(coverage_filter, "both")) {
    keep <- keep & formats$present_in_pronom & formats$present_in_droid
  } else if (identical(coverage_filter, "pronom_only")) {
    keep <- keep & formats$present_in_pronom & !formats$present_in_droid
  } else if (identical(coverage_filter, "droid_only")) {
    keep <- keep & !formats$present_in_pronom & formats$present_in_droid
  }
  if (isTRUE(missing_mime)) keep <- keep & !nzchar(formats$mime_types)
  if (isTRUE(missing_extension)) keep <- keep & !nzchar(formats$extensions)
  if (isTRUE(no_droid_signature)) {
    keep <- keep & formats$droid_internal_signature_references == 0L
  }
  formats[keep, , drop = FALSE]
}

get_integrated_format_details <- function(connection, puid, pronom_snapshot_id,
                                          droid_snapshot_id) {
  snapshot_ids <- c(
    snapshot_parameter(pronom_snapshot_id),
    snapshot_parameter(droid_snapshot_id)
  )
  observations <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT CAST(format.source_format_id AS VARCHAR) AS source_format_id,",
      " snapshot.source_type, snapshot.source_version, snapshot.source_filename,",
      " snapshot.source_relative_path, snapshot.imported_at, format.format_name,",
      " format.format_version, record.source_relative_path AS record_path,",
      " record.parse_status",
      "FROM source_format AS format",
      "JOIN source_snapshot AS snapshot ON snapshot.snapshot_id = format.snapshot_id",
      "LEFT JOIN source_record AS record ON record.source_record_uuid = format.source_record_uuid",
      "WHERE format.puid = ? AND format.snapshot_id IN (?, ?)",
      "ORDER BY CASE WHEN snapshot.source_type IN ('pronom_repository', 'pronom_json') THEN 0 ELSE 1 END"
    ),
    params = as.list(c(puid, snapshot_ids))
  )
  observations$imported_at <- format_source_timestamp(observations$imported_at)
  format_ids <- observations$source_format_id
  child_query <- function(table, fields, order_by) {
    if (length(format_ids) == 0L) return(data.frame())
    placeholders <- paste(rep("?", length(format_ids)), collapse = ", ")
    DBI::dbGetQuery(
      connection,
      sprintf(
        "SELECT %s FROM %s WHERE CAST(source_format_id AS VARCHAR) IN (%s) ORDER BY %s",
        fields, table, placeholders, order_by
      ),
      params = as.list(format_ids)
    )
  }
  identifiers <- child_query(
    "source_format_identifier",
    "CAST(source_format_id AS VARCHAR) AS source_format_id, identifier_type, identifier_value, original_value",
    "source_format_id, identifier_type, identifier_value"
  )
  extensions <- child_query(
    "source_format_extension",
    "CAST(source_format_id AS VARCHAR) AS source_format_id, extension, original_value",
    "source_format_id, extension"
  )
  signatures <- child_query(
    "source_format_signature",
    "CAST(source_format_id AS VARCHAR) AS source_format_id, signature_kind, source_signature_id",
    "source_format_id, signature_kind, source_signature_id"
  )
  add_source_type <- function(rows) {
    if (nrow(rows) == 0L) return(rows)
    merge(
      observations[c("source_format_id", "source_type")],
      rows,
      by = "source_format_id",
      all.y = TRUE,
      sort = FALSE
    )[c("source_type", names(rows))]
  }
  identifiers <- add_source_type(identifiers)
  extensions <- add_source_type(extensions)
  signatures <- add_source_type(signatures)
  droid_signatures <- signatures[
    signatures$source_type == "droid_binary_signature", , drop = FALSE
  ]
  relationships <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT snapshot.source_type, relationship.subject_source_record_id,",
      " relationship.relationship_type, relationship.object_source_record_id,",
      " coalesce(relationship.object_puid, target.puid) AS object_puid,",
      " relationship.original_relationship_type",
      "FROM source_format_relationship AS relationship",
      "JOIN source_snapshot AS snapshot ON snapshot.snapshot_id = relationship.snapshot_id",
      "JOIN source_format AS subject ON subject.snapshot_id = relationship.snapshot_id",
      " AND subject.source_record_id = relationship.subject_source_record_id",
      "LEFT JOIN source_format AS target ON target.snapshot_id = relationship.snapshot_id",
      " AND target.source_record_id = relationship.object_source_record_id",
      "WHERE subject.puid = ? AND relationship.snapshot_id IN (?, ?)",
      "ORDER BY snapshot.source_type, relationship.relationship_type,",
      " relationship.object_source_record_id"
    ),
    params = as.list(c(puid, snapshot_ids))
  )
  summaries <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT snapshot.source_type, summary.summary_code, summary.message, summary.item_count",
      "FROM source_import_summary AS summary",
      "JOIN source_snapshot AS snapshot ON snapshot.snapshot_id = summary.snapshot_id",
      "WHERE summary.snapshot_id IN (?, ?)",
      "ORDER BY snapshot.source_type, summary.summary_code"
    ),
    params = as.list(snapshot_ids)
  )
  source_record_ids <- if (nrow(observations) == 0L) {
    character()
  } else {
    DBI::dbGetQuery(
      connection,
      "SELECT source_record_id FROM source_format WHERE puid = ? AND snapshot_id IN (?, ?)",
      params = as.list(c(puid, snapshot_ids))
    )$source_record_id
  }
  issue_locators <- unique(c(puid, source_record_ids))
  locator_placeholders <- paste(rep("?", length(issue_locators)), collapse = ", ")
  issues <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT snapshot.source_type, issue.severity, issue.validation_layer,",
      " issue.record_locator AS source_locator, issue.issue_code, issue.message",
      "FROM source_import_issue AS issue",
      "JOIN source_snapshot AS snapshot ON snapshot.snapshot_id = issue.snapshot_id",
      sprintf(
        "WHERE issue.snapshot_id IN (?, ?) AND issue.record_locator IN (%s)",
        locator_placeholders
      ),
      "UNION ALL",
      "SELECT snapshot.source_type, issue.severity, issue.validation_layer,",
      " record.source_relative_path, issue.issue_code, issue.message",
      "FROM source_record_issue AS issue",
      "JOIN source_record AS record ON record.source_record_uuid = issue.source_record_uuid",
      "JOIN source_snapshot AS snapshot ON snapshot.snapshot_id = record.snapshot_id",
      "WHERE record.snapshot_id IN (?, ?) AND record.source_record_identifier = ?",
      "ORDER BY source_type, severity DESC, source_locator, issue_code"
    ),
    params = as.list(c(
      snapshot_ids, issue_locators,
      snapshot_ids, puid
    ))
  )
  pronom_raw <- get_pronom_raw_record(
    connection, puid, snapshot_ids[[1L]]
  )
  droid_fragment <- get_droid_format_fragment(
    connection, puid, snapshot_ids[[2L]]
  )
  pronom_relationships <- relationships[
    relationships$source_type %in% c("pronom_repository", "pronom_json"),
    , drop = FALSE
  ]
  droid_priorities <- relationships[
    relationships$source_type == "droid_binary_signature" &
      relationships$relationship_type == "has_priority_over",
    , drop = FALSE
  ]
  preferred_observation <- if (nrow(observations) > 0L) {
    observations[1L, , drop = FALSE]
  } else {
    data.frame()
  }
  preferred_source_type <- if (nrow(preferred_observation) > 0L) {
    preferred_observation$source_type[[1L]]
  } else {
    NA_character_
  }
  preferred_identifiers <- identifiers[
    identifiers$source_type == preferred_source_type, , drop = FALSE
  ]
  list(
    overview = if (nrow(preferred_observation) == 0L) data.frame() else data.frame(
      puid = puid,
      name = preferred_observation$format_name,
      version = preferred_observation$format_version,
      description = pronom_raw$description,
      descriptive_source = preferred_source_type,
      droid_present = any(observations$source_type == "droid_binary_signature"),
      stringsAsFactors = FALSE
    ),
    observations = observations,
    identifiers = identifiers,
    preferred_identifiers = preferred_identifiers,
    mime_types = preferred_identifiers[
      toupper(preferred_identifiers$identifier_type) == "MIME", , drop = FALSE
    ],
    extensions = extensions,
    signatures = droid_signatures,
    relationships = relationships,
    pronom_relationships = pronom_relationships,
    droid_priorities = droid_priorities,
    raw_pronom_json = pronom_raw$raw_json,
    droid_xml_fragment = droid_fragment,
    consistency = format_consistency(observations, identifiers, extensions),
    profile_statements = get_puid_profile_statements(connection, puid),
    unsupported = summaries,
    issues = issues
  )
}

get_pronom_raw_record <- function(connection, puid, snapshot_id) {
  row <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT snapshot.source_type, record.raw_content AS record_content,",
      " snapshot.raw_content AS snapshot_content",
      "FROM source_format AS format",
      "JOIN source_snapshot AS snapshot ON snapshot.snapshot_id = format.snapshot_id",
      "LEFT JOIN source_record AS record ON record.source_record_uuid = format.source_record_uuid",
      "WHERE format.snapshot_id = ? AND format.puid = ?",
      " AND snapshot.source_type IN ('pronom_repository', 'pronom_json')"
    ),
    params = list(snapshot_id, puid)
  )
  if (nrow(row) == 0L) {
    return(list(raw_json = NA_character_, description = NA_character_))
  }
  bytes <- if (!is.null(row$record_content[[1L]])) {
    row$record_content[[1L]]
  } else {
    row$snapshot_content[[1L]]
  }
  raw_json <- rawToChar(bytes)
  record <- tryCatch(
    jsonlite::fromJSON(raw_json, simplifyVector = FALSE),
    error = function(error) NULL
  )
  description <- if (is.null(record)) {
    NA_character_
  } else {
    scalar_character(record$formatDescription)
  }
  list(raw_json = raw_json, description = description)
}

get_droid_format_fragment <- function(connection, puid, snapshot_id) {
  row <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT snapshot.raw_content",
      "FROM source_snapshot AS snapshot",
      "JOIN source_format AS format ON format.snapshot_id = snapshot.snapshot_id",
      "WHERE snapshot.snapshot_id = ? AND format.puid = ?",
      " AND snapshot.source_type = 'droid_binary_signature'"
    ),
    params = list(snapshot_id, puid)
  )
  if (nrow(row) == 0L) return(NA_character_)
  document <- tryCatch(
    xml2::read_xml(rawToChar(row$raw_content[[1L]]), options = "NONET"),
    error = function(error) NULL
  )
  if (is.null(document)) return(NA_character_)
  namespace <- c(
    p = "http://www.nationalarchives.gov.uk/pronom/SignatureFile"
  )
  node <- xml2::xml_find_first(
    document,
    sprintf(".//p:FileFormat[@PUID='%s']", puid),
    namespace
  )
  if (inherits(node, "xml_missing")) return(NA_character_)
  as.character(node)
}

format_consistency <- function(observations, identifiers, extensions) {
  if (nrow(observations) < 2L) {
    return(data.frame(
      field = "Source presence",
      status = "Only one selected source contains this PUID.",
      stringsAsFactors = FALSE
    ))
  }
  source_ids <- observations$source_format_id
  compare_scalar <- function(field, values) {
    normalised <- ifelse(is.na(values) | !nzchar(values), "<absent>", values)
    data.frame(
      field = field,
      status = if (length(unique(normalised)) <= 1L) {
        "Consistent"
      } else {
        "Different source values"
      },
      stringsAsFactors = FALSE
    )
  }
  compare_set <- function(field, rows, value_column) {
    sets <- lapply(source_ids, function(id) {
      sort(unique(rows[rows$source_format_id == id, value_column]))
    })
    data.frame(
      field = field,
      status = if (identical(sets[[1L]], sets[[2L]])) "Consistent" else "Different source sets",
      stringsAsFactors = FALSE
    )
  }
  rbind(
    compare_scalar("Name", observations$format_name),
    compare_scalar("Version", observations$format_version),
    compare_set("MIME types", identifiers[toupper(identifiers$identifier_type) == "MIME", ], "identifier_value"),
    compare_set("Extensions", extensions, "extension")
  )
}

get_snapshot_details <- function(connection, snapshot_id) {
  metadata <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT",
      " CAST(snapshot.snapshot_id AS VARCHAR) AS snapshot_id,",
      " snapshot.source_type, snapshot.source_version, snapshot.source_filename,",
      " snapshot.source_relative_path, snapshot.imported_at,",
      " coalesce(run.parsed_count + run.rejected_count, profile.format_count,",
      "   CASE WHEN (SELECT count(*) FROM source_record WHERE snapshot_id = snapshot.snapshot_id) > 0",
      "     THEN (SELECT count(*) FROM source_record WHERE snapshot_id = snapshot.snapshot_id)",
      "     ELSE (SELECT count(*) FROM source_format WHERE snapshot_id = snapshot.snapshot_id) END",
      " ) AS imported_record_count,",
      " coalesce(run.warning_count,",
      "   (SELECT count(*) FROM source_import_issue",
      "    WHERE snapshot_id = snapshot.snapshot_id AND lower(severity) = 'warning'), 0",
      " ) AS warning_count,",
      " coalesce(run.error_count,",
      "   (SELECT count(*) FROM source_import_issue",
      "    WHERE snapshot_id = snapshot.snapshot_id AND lower(severity) = 'error'), 0",
      " ) AS error_count,",
      " (SELECT count(DISTINCT puid) FROM source_format",
      "   WHERE snapshot_id = snapshot.snapshot_id AND puid LIKE 'fmt/%') AS fmt_count,",
      " (SELECT count(DISTINCT puid) FROM source_format",
      "   WHERE snapshot_id = snapshot.snapshot_id AND puid LIKE 'x-fmt/%') AS x_fmt_count,",
      " (SELECT count(DISTINCT puid) FROM source_format",
      "   WHERE snapshot_id = snapshot.snapshot_id) AS unique_puid_count,",
      " (SELECT count(DISTINCT format.source_format_id)",
      "   FROM source_format AS format",
      "   WHERE format.snapshot_id = snapshot.snapshot_id",
      "    AND EXISTS (SELECT 1 FROM source_format_signature AS signature",
      "      WHERE signature.source_format_id = format.source_format_id",
      "       AND signature.signature_kind = 'binary_internal'))",
      "   AS with_internal_signature_count,",
      " (SELECT count(*) FROM source_format AS format",
      "   WHERE format.snapshot_id = snapshot.snapshot_id",
      "    AND NOT EXISTS (SELECT 1 FROM source_format_identifier AS identifier",
      "      WHERE identifier.source_format_id = format.source_format_id",
      "       AND upper(identifier.identifier_type) = 'MIME')) AS without_mime_count,",
      " (SELECT count(*) FROM source_format AS format",
      "   WHERE format.snapshot_id = snapshot.snapshot_id",
      "    AND NOT EXISTS (SELECT 1 FROM source_format_extension AS extension",
      "      WHERE extension.source_format_id = format.source_format_id))",
      "   AS without_extension_count,",
      " schema.compatibility_id, profile.support_mode AS droid_support_mode,",
      " profile.xml_dialect AS droid_xml_dialect,",
      " profile.format_count AS droid_format_count,",
      " profile.valid_puid_count AS droid_valid_puid_count,",
      " profile.placeholder_puid_count AS droid_placeholder_puid_count,",
      " profile.missing_puid_count AS droid_missing_puid_count,",
      " profile.invalid_puid_count AS droid_invalid_puid_count",
      "FROM source_snapshot AS snapshot",
      "LEFT JOIN import_run AS run ON run.import_run_id = snapshot.import_run_id",
      "LEFT JOIN source_validation_schema AS schema",
      " ON schema.validation_schema_id = snapshot.validation_schema_id",
      "LEFT JOIN droid_snapshot_profile AS profile",
      " ON profile.snapshot_id = snapshot.snapshot_id",
      "WHERE snapshot.snapshot_id = ?"
    ),
    params = list(snapshot_id)
  )
  metadata$imported_at <- format_source_timestamp(metadata$imported_at)
  summaries <- list_import_summaries(connection, snapshot_id)
  summary_count <- function(code) {
    rows <- summaries[summaries$summary_code == code, , drop = FALSE]
    if (nrow(rows) == 0L) return(NA_integer_)
    as.integer(sum(rows$item_count))
  }
  strict_count <- summary_count("pronom_strict_schema_violations")
  compatibility_count <- summary_count(
    "pronom_compatibility_schema_violations"
  )
  validated_count <- summary_count(
    "pronom_compatibility_schema_validated_records"
  )
  compatibility_result <- if (
    !metadata$source_type[[1L]] %in% c("pronom_repository", "pronom_json")
  ) {
    "Not applicable"
  } else if (is.na(compatibility_count)) {
    "Unavailable for this snapshot"
  } else if (compatibility_count > 0L) {
    sprintf("Failed (%s violations)", format(compatibility_count, big.mark = ","))
  } else if (!is.na(validated_count) &&
             validated_count < metadata$imported_record_count[[1L]]) {
    sprintf(
      "Incomplete (%s of %s records validated)",
      format(validated_count, big.mark = ","),
      format(metadata$imported_record_count[[1L]], big.mark = ",")
    )
  } else if (compatibility_count == 0L) {
    "Passed"
  }
  metrics <- data.frame(
    metric = c(
      "Record count", "Warnings", "Errors", "fmt PUIDs", "x-fmt PUIDs",
      "Unique PUIDs", "With internal-signature references",
      "Without MIME type", "Without extension",
      "Strict official-schema violations",
      "Compatibility-schema validation", "Compatibility overlay",
      "DROID support mode", "DROID XML dialect", "Valid PUID records",
      "Placeholder PUID records", "Missing PUID records", "Invalid PUID records"
    ),
    value = c(
      metadata$imported_record_count, metadata$warning_count,
      metadata$error_count, metadata$fmt_count, metadata$x_fmt_count,
      metadata$unique_puid_count, metadata$with_internal_signature_count,
      metadata$without_mime_count, metadata$without_extension_count,
      ifelse(is.na(strict_count), "Unavailable", strict_count),
      compatibility_result,
      ifelse(
        is.na(metadata$compatibility_id),
        ifelse(
          metadata$source_type %in% c("pronom_repository", "pronom_json"),
          "None", "Not applicable"
        ),
        metadata$compatibility_id
      ),
      ifelse(is.na(metadata$droid_support_mode), "Not applicable",
             metadata$droid_support_mode),
      ifelse(is.na(metadata$droid_xml_dialect), "Not applicable",
             metadata$droid_xml_dialect),
      ifelse(is.na(metadata$droid_valid_puid_count), "Not applicable",
             metadata$droid_valid_puid_count),
      ifelse(is.na(metadata$droid_placeholder_puid_count), "Not applicable",
             metadata$droid_placeholder_puid_count),
      ifelse(is.na(metadata$droid_missing_puid_count), "Not applicable",
             metadata$droid_missing_puid_count),
      ifelse(is.na(metadata$droid_invalid_puid_count), "Not applicable",
             metadata$droid_invalid_puid_count)
    ),
    stringsAsFactors = FALSE
  )
  issues <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT severity, validation_layer, record_locator AS source_locator, issue_code, message",
      "FROM source_import_issue WHERE snapshot_id = ?",
      "UNION ALL",
      "SELECT issue.severity, issue.validation_layer,",
      " coalesce(record.source_relative_path, record.source_record_identifier),",
      " issue.issue_code, issue.message",
      "FROM source_record_issue AS issue",
      "JOIN source_record AS record ON record.source_record_uuid = issue.source_record_uuid",
      "WHERE record.snapshot_id = ?",
      "ORDER BY severity DESC, source_locator, issue_code"
    ),
    params = list(snapshot_id, snapshot_id)
  )
  list(
    metadata = metadata,
    metrics = metrics,
    counts = metadata[c(
      "imported_record_count", "warning_count", "error_count"
    )],
    summaries = summaries,
    issues = issues
  )
}

get_snapshot_import_detail <- get_snapshot_details

format_source_timestamp <- function(value) {
  if (length(value) == 0L) return(character())
  vapply(value, function(item) {
    if (is.na(item)) return(NA_character_)
    timestamp <- if (inherits(item, "POSIXt")) {
      as.POSIXct(item, tz = "UTC")
    } else if (is.numeric(item)) {
      as.POSIXct(item, origin = "1970-01-01", tz = "UTC")
    } else {
      suppressWarnings(as.POSIXct(as.character(item), tz = "UTC"))
    }
    if (is.na(timestamp)) {
      as.character(item)
    } else {
      format(timestamp, "%Y-%m-%d %H:%M:%S UTC", tz = "UTC")
    }
  }, character(1))
}

snapshot_parameter <- function(value) {
  if (length(value) == 0L || is.null(value) || is.na(value) || !nzchar(value)) {
    return("00000000-0000-0000-0000-000000000000")
  }
  value
}

`%||%` <- function(left, right) {
  if (is.null(left)) right else left
}
