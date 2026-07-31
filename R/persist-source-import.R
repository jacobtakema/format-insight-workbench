#' Parse and persist one PRONOM JSON source file
#'
#' @return The UUID of the new immutable source snapshot.
import_pronom_json <- function(connection, path, source_filename = basename(path),
                               source_relative_path = NA_character_) {
  parsed <- parse_pronom_json(path)
  persist_source_import(
    connection, parsed, path,
    source_filename = source_filename,
    source_relative_path = source_relative_path
  )
}

#' Parse and persist one DROID binary-signature source file
#'
#' @return The UUID of the new immutable source snapshot.
import_droid_xml <- function(connection, path, source_filename = basename(path),
                             source_relative_path = NA_character_) {
  parsed <- parse_droid_xml(path)
  persist_source_import(
    connection, parsed, path,
    source_filename = source_filename,
    source_relative_path = source_relative_path
  )
}

#' Persist a parsed source import atomically
#'
#' Parsing remains separate: this function accepts the normalised parser result
#' and the source path used for checksum and byte preservation.
#'
#' @return The UUID of the new immutable source snapshot.
persist_source_import <- function(connection, parsed, source_path,
                                  source_filename = basename(source_path),
                                  source_relative_path = NA_character_) {
  validate_persistence_input(parsed, source_path)
  stop_for_source_validation_errors(parsed$issues)
  checksum <- digest::digest(file = source_path, algo = "sha256", serialize = FALSE)
  source_type <- parsed$metadata$source_type[[1L]]

  duplicate <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT snapshot_id FROM source_snapshot",
      "WHERE source_type = ? AND checksum_sha256 = ?"
    ),
    params = list(source_type, checksum)
  )
  if (nrow(duplicate) > 0L) {
    stop_duplicate_snapshot(source_type, checksum, as.character(duplicate$snapshot_id[[1L]]))
  }

  snapshot_id <- database_uuids(connection, 1L)[[1L]]
  source_bytes <- readBin(source_path, what = "raw", n = file.info(source_path)$size)

  DBI::dbWithTransaction(connection, {
    registry_id <- ensure_pronom_registry(connection)
    validation_schema_id <- ensure_source_validation_schema(
      connection, parsed$validation_schema
    )
    insert_snapshot(
      connection, snapshot_id, parsed$metadata, checksum, source_bytes,
      source_filename, source_relative_path, validation_schema_id
    )
    if (identical(source_type, "droid_binary_signature")) {
      DBI::dbExecute(
        connection,
        paste(
          "INSERT INTO signature_set",
          "(signature_set_id, snapshot_id, signature_set_type, signature_version,",
          "released_at, checksum_sha256) VALUES (?, ?, 'droid_binary', ?, ?, ?)"
        ),
        params = list(
          database_uuids(connection, 1L)[[1L]], snapshot_id,
          parsed$metadata$source_version[[1L]],
          parse_source_timestamp(parsed$metadata$source_created_at[[1L]]),
          checksum
        )
      )
      insert_droid_snapshot_profile(connection, snapshot_id, parsed$metadata)
    }
    source_record_map <- insert_droid_source_records(
      connection, snapshot_id, parsed$source_records, source_filename
    )
    format_map <- insert_source_formats(
      connection, snapshot_id, parsed$formats, registry_id, source_record_map
    )
    insert_source_identifiers(connection, parsed$identifiers, format_map)
    insert_source_extensions(connection, parsed$extensions, format_map)
    insert_source_signatures(connection, parsed$signatures, format_map)
    insert_source_relationships(connection, snapshot_id, parsed$relationships)
    insert_source_issues(connection, snapshot_id, parsed$issues)
    insert_source_summaries(connection, snapshot_id, parsed$summaries)
  })

  snapshot_id
}

validate_persistence_input <- function(parsed, source_path) {
  if (!inherits(parsed, "format_policy_import")) {
    stop("'parsed' must be a format_policy_import result.", call. = FALSE)
  }
  if (!file.exists(source_path)) {
    stop(sprintf("Source file does not exist: %s", source_path), call. = FALSE)
  }
  required <- c(
    "metadata", "formats", "identifiers", "extensions",
    "signatures", "relationships", "issues", "summaries", "source_records"
  )
  if (!all(required %in% names(parsed)) || !all(vapply(parsed[required], is.data.frame, logical(1)))) {
    stop("Parser result does not contain the required data frames.", call. = FALSE)
  }
  if (nrow(parsed$metadata) != 1L) {
    stop("Parser metadata must contain exactly one row.", call. = FALSE)
  }
  invisible(TRUE)
}

insert_snapshot <- function(connection, snapshot_id, metadata, checksum, source_bytes,
                            source_filename, source_relative_path,
                            validation_schema_id = NULL) {
  created_at <- parse_source_timestamp(metadata$source_created_at[[1L]])
  DBI::dbExecute(
    connection,
    paste(
      "INSERT INTO source_snapshot",
      "(snapshot_id, source_type, source_version, source_filename, source_relative_path, source_created_at,",
      "checksum_sha256, imported_at, import_status, raw_content, validation_schema_id)",
      "VALUES (?, ?, ?, ?, ?, ?, ?, current_timestamp, 'succeeded', ?, ?)"
    ),
    params = list(
      snapshot_id,
      metadata$source_type[[1L]],
      metadata$source_version[[1L]],
      source_filename,
      null_if_missing(source_relative_path),
      created_at,
      checksum,
      list(source_bytes),
      if (is.null(validation_schema_id)) NA_character_ else validation_schema_id
    )
  )
}

ensure_source_validation_schema <- function(connection, bundle = NULL) {
  if (is.null(bundle)) return(NULL)
  found <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT validation_schema_id FROM source_validation_schema",
      "WHERE source_type = 'pronom_json'",
      " AND schema_checksum_sha256 = ?",
      " AND effective_schema_checksum_sha256 = ?"
    ),
    params = list(
      bundle$schema_checksum_sha256,
      bundle$effective_schema_checksum_sha256
    )
  )
  if (nrow(found) > 0L) {
    return(as.character(found$validation_schema_id[[1L]]))
  }
  id <- database_uuids(connection, 1L)[[1L]]
  DBI::dbExecute(
    connection,
    paste(
      "INSERT INTO source_validation_schema",
      "(validation_schema_id, source_type, schema_identifier, schema_dialect,",
      "schema_checksum_sha256, compatibility_id, compatibility_checksum_sha256,",
      "effective_schema_checksum_sha256, raw_schema, raw_compatibility)",
      "VALUES (?, 'pronom_json', ?, ?, ?, ?, ?, ?, ?, ?)"
    ),
    params = list(
      id, bundle$schema_identifier, bundle$schema_dialect,
      bundle$schema_checksum_sha256, null_if_missing(bundle$compatibility_id),
      null_if_missing(bundle$compatibility_checksum_sha256),
      bundle$effective_schema_checksum_sha256,
      list(bundle$raw_schema), list(bundle$raw_compatibility)
    )
  )
  id
}

insert_source_summaries <- function(connection, snapshot_id, summaries) {
  if (nrow(summaries) == 0L) return(invisible(NULL))
  rows <- data.frame(
    summary_id = database_uuids(connection, nrow(summaries)),
    snapshot_id = rep(snapshot_id, nrow(summaries)),
    summaries,
    stringsAsFactors = FALSE
  )
  DBI::dbAppendTable(connection, "source_import_summary", rows)
  invisible(NULL)
}

insert_source_formats <- function(connection, snapshot_id, formats, registry_id = NULL,
                                  source_record_map = NULL) {
  if (nrow(formats) == 0L) {
    return(data.frame(source_record_id = character(), source_format_id = character()))
  }
  format_ids <- database_uuids(connection, nrow(formats))
  if (is.null(registry_id)) registry_id <- ensure_pronom_registry(connection)
  identities <- ensure_format_identities(connection, registry_id, formats$puid)
  identity_positions <- match(formats$puid, identities$identifier)
  rows <- data.frame(
    source_format_id = format_ids,
    snapshot_id = rep(snapshot_id, nrow(formats)),
    source_record_id = formats$source_record_id,
    puid = formats$puid,
    format_name = formats$format_name,
    format_version = formats$format_version,
    raw_record = NA_character_,
    format_identity_id = identities$format_identity_id[identity_positions],
    source_record_uuid = if (is.null(source_record_map) || nrow(source_record_map) == 0L) {
      NA_character_
    } else {
      source_record_map$source_record_uuid[
        match(formats$source_record_id, source_record_map$source_record_id)
      ]
    },
    stringsAsFactors = FALSE
  )
  DBI::dbAppendTable(connection, "source_format", rows)
  insert_source_format_identity_links(connection, rows)
  rows[c("source_record_id", "source_format_id")]
}

insert_droid_snapshot_profile <- function(connection, snapshot_id, metadata) {
  DBI::dbExecute(
    connection,
    paste(
      "INSERT INTO droid_snapshot_profile",
      "(snapshot_id, support_mode, xml_dialect, format_count, valid_puid_count,",
      "placeholder_puid_count, missing_puid_count, invalid_puid_count)",
      "VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
    ),
    params = list(
      snapshot_id,
      metadata$droid_support_mode[[1L]],
      metadata$droid_xml_dialect[[1L]],
      metadata$droid_format_count[[1L]],
      metadata$droid_valid_puid_count[[1L]],
      metadata$droid_placeholder_puid_count[[1L]],
      metadata$droid_missing_puid_count[[1L]],
      metadata$droid_invalid_puid_count[[1L]]
    )
  )
  invisible(NULL)
}

insert_droid_source_records <- function(connection, snapshot_id, records,
                                        source_filename) {
  if (nrow(records) == 0L) {
    return(data.frame(
      source_record_id = character(), source_record_uuid = character()
    ))
  }
  record_ids <- database_uuids(connection, nrow(records))
  for (index in seq_len(nrow(records))) {
    content <- charToRaw(enc2utf8(records$raw_content[[index]]))
    DBI::dbExecute(
      connection,
      paste(
        "INSERT INTO source_record",
        "(source_record_uuid, snapshot_id, source_relative_path, source_filename,",
        "source_record_identifier, checksum_sha256, raw_content, parse_status)",
        "VALUES (?, ?, ?, ?, ?, ?, ?, 'parsed')"
      ),
      params = list(
        record_ids[[index]], snapshot_id,
        records$source_relative_path[[index]],
        source_filename,
        null_if_missing(records$source_record_id[[index]]),
        digest::digest(content, algo = "sha256", serialize = FALSE),
        list(content)
      )
    )
  }
  data.frame(
    source_record_id = records$source_record_id,
    source_record_uuid = record_ids,
    stringsAsFactors = FALSE
  )
}

insert_source_format_identity_links <- function(connection, rows) {
  if (nrow(rows) == 0L) return(invisible(NULL))
  links <- rows[c("source_format_id", "format_identity_id")]
  DBI::dbAppendTable(connection, "source_format_identity", links)
  invisible(NULL)
}

ensure_pronom_registry <- function(
    connection,
    repository_url = "https://github.com/nationalarchives/pronom") {
  found <- DBI::dbGetQuery(
    connection, "SELECT registry_id FROM registry WHERE registry_code = 'pronom'"
  )
  if (nrow(found) > 0L) return(as.character(found$registry_id[[1L]]))
  id <- database_uuids(connection, 1L)[[1L]]
  DBI::dbExecute(
    connection,
    paste(
      "INSERT INTO registry",
      "(registry_id, registry_code, name, identifier_namespace, repository_url)",
      "VALUES (?, 'pronom', 'PRONOM', 'fmt|x-fmt', ?)"
    ),
    params = list(id, repository_url)
  )
  id
}

ensure_format_identities <- function(connection, registry_id, puids) {
  puids <- unique(puids)
  existing <- DBI::dbGetQuery(
    connection,
    "SELECT format_identity_id, identifier FROM format_identity WHERE registry_id = ?",
    params = list(registry_id)
  )
  missing <- setdiff(puids, existing$identifier)
  if (length(missing) > 0L) {
    rows <- data.frame(
      format_identity_id = database_uuids(connection, length(missing)),
      registry_id = registry_id,
      identifier_namespace = sub("/.*$", "", missing),
      identifier = missing,
      stringsAsFactors = FALSE
    )
    DBI::dbAppendTable(connection, "format_identity", rows)
    existing <- rbind(existing, rows[c("format_identity_id", "identifier")])
  }
  existing
}

insert_source_identifiers <- function(connection, identifiers, format_map) {
  rows <- attach_format_ids(identifiers, format_map)
  if (nrow(rows) == 0L) return(invisible(NULL))
  DBI::dbAppendTable(connection, "source_format_identifier", rows[c(
    "source_format_id", "identifier_type", "identifier_value", "original_value", "ordinal"
  )])
  invisible(NULL)
}

insert_source_extensions <- function(connection, extensions, format_map) {
  rows <- attach_format_ids(extensions, format_map)
  if (nrow(rows) == 0L) return(invisible(NULL))
  DBI::dbAppendTable(connection, "source_format_extension", rows[c(
    "source_format_id", "extension", "original_value", "ordinal"
  )])
  invisible(NULL)
}

insert_source_signatures <- function(connection, signatures, format_map) {
  rows <- attach_format_ids(signatures, format_map)
  if (nrow(rows) == 0L) return(invisible(NULL))
  rows$raw_signature <- NA_character_
  DBI::dbAppendTable(connection, "source_format_signature", rows[c(
    "source_format_id", "signature_kind", "source_signature_id", "raw_signature"
  )])
  invisible(NULL)
}

insert_source_relationships <- function(connection, snapshot_id, relationships) {
  if (nrow(relationships) == 0L) return(invisible(NULL))
  rows <- relationships[c(
    "subject_source_record_id", "relationship_type", "object_source_record_id",
    "object_puid", "original_relationship_type"
  )]
  rows$snapshot_id <- snapshot_id
  rows <- rows[c("snapshot_id", names(rows)[names(rows) != "snapshot_id"])]
  DBI::dbAppendTable(connection, "source_format_relationship", rows)
  invisible(NULL)
}

insert_source_issues <- function(connection, snapshot_id, issues) {
  if (nrow(issues) == 0L) return(invisible(NULL))
  rows <- data.frame(
    issue_id = database_uuids(connection, nrow(issues)),
    snapshot_id = rep(snapshot_id, nrow(issues)),
    issues,
    stringsAsFactors = FALSE
  )
  DBI::dbAppendTable(connection, "source_import_issue", rows)
  invisible(NULL)
}

attach_format_ids <- function(rows, format_map) {
  if (nrow(rows) == 0L) {
    rows$source_format_id <- character()
    return(rows)
  }
  positions <- match(rows$source_record_id, format_map$source_record_id)
  if (anyNA(positions)) {
    stop("A child source row does not match an imported format record.", call. = FALSE)
  }
  rows$source_format_id <- format_map$source_format_id[positions]
  rows
}

database_uuids <- function(connection, count) {
  if (count == 0L) return(character())
  query <- sprintf("SELECT CAST(uuid() AS VARCHAR) AS id FROM range(%d)", as.integer(count))
  DBI::dbGetQuery(connection, query)$id
}

parse_source_timestamp <- function(value) {
  if (length(value) == 0L || is.na(value) || !nzchar(value)) return(as.POSIXct(NA))
  parsed <- as.POSIXct(value, format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")
  if (is.na(parsed)) NA_POSIXct_ else parsed
}

null_if_missing <- function(value) {
  if (length(value) == 0L || is.na(value) || !nzchar(trimws(value))) NA_character_ else value
}

stop_for_source_validation_errors <- function(issues) {
  errors <- issues[tolower(issues$severity) == "error", , drop = FALSE]
  if (nrow(errors) == 0L) return(invisible(TRUE))
  displayed <- head(errors$message, 5L)
  suffix <- if (nrow(errors) > length(displayed)) {
    sprintf(" (%d additional errors)", nrow(errors) - length(displayed))
  } else {
    ""
  }
  condition <- structure(
    list(
      message = paste0(
        "Source validation failed: ",
        paste(displayed, collapse = " "),
        suffix
      ),
      call = NULL,
      issues = errors
    ),
    class = c("format_policy_source_validation_error", "error", "condition")
  )
  stop(condition)
}

stop_duplicate_snapshot <- function(source_type, checksum, snapshot_id) {
  condition <- structure(
    list(
      message = sprintf("This %s source has already been imported.", source_type),
      call = NULL,
      source_type = source_type,
      checksum_sha256 = checksum,
      existing_snapshot_id = snapshot_id
    ),
    class = c("format_policy_duplicate_snapshot", "error", "condition")
  )
  stop(condition)
}
