report_import_progress <- function(callback, stage, current = 0L, total = 0L, message = "") {
  callback(list(stage = stage, current = current, total = total, message = message))
}

discover_pronom_archive <- function(archive_path, extraction_directory) {
  entries <- utils::untar(archive_path, list = TRUE)
  if (length(entries) == 0L) stop("The repository archive is empty.", call. = FALSE)
  unsafe <- grepl("^(?:/|[A-Za-z]:)|(?:^|/)[.][.](?:/|$)", entries)
  if (any(unsafe)) stop("The repository archive contains unsafe paths.", call. = FALSE)
  utils::untar(archive_path, exdir = extraction_directory)
  all_relative <- sub("^[^/]+/", "", entries)
  selected <- grepl("^signatures/(fmt|x-fmt)/[^/]+[.]json$", all_relative)
  paths <- file.path(extraction_directory, entries[selected])
  paths <- paths[file.exists(paths) & !dir.exists(paths)]
  relative <- all_relative[selected][
    file.exists(file.path(extraction_directory, entries[selected]))
  ]
  if (length(paths) == 0L) {
    stop("The archive contains no PRONOM JSON records under signatures/fmt or signatures/x-fmt.", call. = FALSE)
  }
  schema_entries <- entries[all_relative == "format_schema.json"]
  if (length(schema_entries) != 1L) {
    stop(
      "The repository archive must contain exactly one root format_schema.json.",
      call. = FALSE
    )
  }
  data.frame(
    path = paths,
    source_relative_path = gsub("\\\\", "/", relative),
    source_filename = basename(relative),
    stringsAsFactors = FALSE
  ) |>
    (\(records) list(
      records = records,
      schema_path = file.path(extraction_directory, schema_entries[[1L]]),
      excluded_count = length(entries) - nrow(records) - 1L
    ))()
}

expected_puid_from_path <- function(source_relative_path) {
  match <- regexec("^signatures/(fmt|x-fmt)/([0-9]+)[.]json$", source_relative_path)
  parts <- regmatches(source_relative_path, match)[[1L]]
  if (length(parts) != 3L) return(NA_character_)
  sprintf("%s/%s", parts[[2L]], parts[[3L]])
}

parse_pronom_repository_archive <- function(archive_path, extraction_directory,
                                            progress = function(value) NULL) {
  discovery <- discover_pronom_archive(archive_path, extraction_directory)
  schema_bundle <- load_pronom_schema(schema_path = discovery$schema_path)
  records <- vector("list", nrow(discovery$records))
  report_import_progress(progress, "parse", 0L, nrow(discovery$records), "Parsing PRONOM records")
  for (index in seq_len(nrow(discovery$records))) {
    record <- discovery$records[index, , drop = FALSE]
    raw <- readBin(record$path, "raw", file.info(record$path)$size)
    parsed <- tryCatch(
      parse_pronom_json(record$path, schema_bundle = schema_bundle),
      error = identity
    )
    issues <- empty_parser_table(c(
      severity = "character", issue_code = "character",
      message = "character", raw_value = "character",
      validation_layer = "character"
    ))
    status <- "parsed"
    source_identifier <- NA_character_
    if (inherits(parsed, "error")) {
      status <- "rejected"
      issue_code <- if (inherits(parsed, "format_policy_parse_error")) {
        "json_syntax_error"
      } else {
        "record_parse_error"
      }
      layer <- if (inherits(parsed, "format_policy_parse_error")) "syntax" else "structural"
      issues <- data.frame(
        severity = "error", issue_code = issue_code,
        message = conditionMessage(parsed), raw_value = NA_character_,
        validation_layer = layer,
        stringsAsFactors = FALSE
      )
      parsed <- NULL
    } else {
      if (nrow(parsed$formats) > 0L) {
        source_identifier <- parsed$formats$puid[[1L]]
      }
      parser_issues <- parsed$issues
      if (nrow(parser_issues) > 0L) {
        issues <- parser_issues[c(
          "severity", "issue_code", "message", "raw_value", "validation_layer"
        )]
      }
      expected <- expected_puid_from_path(record$source_relative_path)
      if (nrow(parsed$formats) > 0L &&
          (is.na(expected) || is.na(source_identifier) ||
           !identical(expected, source_identifier))) {
        issues <- rbind(issues, data.frame(
          severity = "error", issue_code = "puid_path_mismatch",
          message = sprintf(
            "Source path '%s' requires PUID '%s' but the record contains '%s'.",
            record$source_relative_path, expected, source_identifier
          ),
          raw_value = source_identifier, validation_layer = "semantic",
          stringsAsFactors = FALSE
        ))
      }
      if (any(tolower(issues$severity) == "error")) status <- "rejected"
    }
    records[[index]] <- list(
      source_relative_path = record$source_relative_path,
      source_filename = record$source_filename,
      source_record_identifier = source_identifier,
      checksum_sha256 = digest::digest(raw, algo = "sha256", serialize = FALSE),
      raw_content = raw,
      parse_status = status,
      issues = issues,
      validation_summaries = if (is.null(parsed)) {
        NULL
      } else {
        parsed$summaries[grepl(
          "^pronom_(strict|compatibility)_schema_",
          parsed$summaries$summary_code
        ), , drop = FALSE]
      },
      parsed = if (status == "parsed") parsed else NULL
    )
    report_import_progress(
      progress, "parse", index, nrow(discovery$records),
      sprintf("Parsed %d of %d records", index, nrow(discovery$records))
    )
  }
  issue_rows <- do.call(rbind, lapply(records, `[[`, "issues"))
  parsed_records <- Filter(function(record) record$parse_status == "parsed", records)
  puids <- vapply(records, `[[`, character(1), "source_record_identifier")
  list(
    records = records,
    parsed_records = parsed_records,
    excluded_count = discovery$excluded_count,
    validation_schema = schema_bundle,
    summary = list(
      discovered_count = length(records),
      parsed_count = length(parsed_records),
      rejected_count = length(records) - length(parsed_records),
      fmt_count = sum(grepl("^fmt/", puids), na.rm = TRUE),
      x_fmt_count = sum(grepl("^x-fmt/", puids), na.rm = TRUE),
      warning_count = if (is.null(issue_rows)) 0L else sum(tolower(issue_rows$severity) == "warning"),
      error_count = if (is.null(issue_rows)) 0L else sum(tolower(issue_rows$severity) == "error")
    )
  )
}

combine_parser_tables <- function(records, table) {
  rows <- lapply(records, function(record) record$parsed[[table]])
  if (length(rows) == 0L) return(NULL)
  do.call(rbind, rows)
}

repository_preservation_summaries <- function(parsed_records, repository_summary,
                                              excluded_count, records = NULL) {
  summaries <- combine_parser_tables(parsed_records, "summaries")
  if (!is.null(summaries)) {
    summaries <- summaries[!grepl(
      "^pronom_(strict|compatibility)_schema_",
      summaries$summary_code
    ), , drop = FALSE]
  }
  validation_summaries <- if (is.null(records)) {
    NULL
  } else {
    rows <- lapply(records, `[[`, "validation_summaries")
    rows <- Filter(Negate(is.null), rows)
    if (length(rows) == 0L) NULL else do.call(rbind, rows)
  }
  if (!is.null(validation_summaries) && nrow(validation_summaries) > 0L) {
    validation_summaries <- stats::aggregate(
      item_count ~ summary_code + message, validation_summaries, sum
    )
  }
  if (!is.null(summaries) && nrow(summaries) > 0L) {
    summaries <- stats::aggregate(
      item_count ~ summary_code + message, summaries, sum
    )
  }
  repository_rows <- rbind(
    parser_summary(
      "repository_records",
      sprintf(
        "Discovered %d JSON records; %d parsed and %d rejected.",
        repository_summary$discovered_count,
        repository_summary$parsed_count,
        repository_summary$rejected_count
      ),
      repository_summary$discovered_count
    ),
    parser_summary(
      "repository_files_excluded",
      "Repository archive entries outside signatures/fmt and signatures/x-fmt were excluded.",
      excluded_count
    )
  )
  rbind(summaries, validation_summaries, repository_rows)
}

create_import_run <- function(connection, registry_id, repository_url, reference) {
  id <- database_uuids(connection, 1L)[[1L]]
  DBI::dbExecute(
    connection,
    paste(
      "INSERT INTO import_run",
      "(import_run_id, registry_id, source_type, repository_url, requested_reference, status, started_at)",
      "VALUES (?, ?, 'pronom_repository', ?, ?, 'running', current_timestamp)"
    ),
    params = list(id, registry_id, repository_url, reference)
  )
  id
}

import_pronom_repository <- function(connection, repository_url, reference,
                                     resolved = NULL,
                                     resolver = resolve_github_reference,
                                     downloader = download_github_archive,
                                     progress = function(value) NULL,
                                     temporary_directory_factory = function() tempfile("pronom-repository-")) {
  repository <- parse_github_repository_url(repository_url)
  registry_id <- ensure_pronom_registry(connection, repository$repository_url)
  import_run_id <- create_import_run(
    connection, registry_id, repository$repository_url, reference
  )
  temporary_directory <- temporary_directory_factory()
  dir.create(temporary_directory, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(temporary_directory, recursive = TRUE, force = TRUE), add = TRUE)
  tryCatch({
    report_import_progress(progress, "resolve", message = "Resolving repository reference")
    if (is.null(resolved)) resolved <- resolver(repository$repository_url, reference)
    duplicate <- DBI::dbGetQuery(
      connection,
      paste(
        "SELECT registry_release_id FROM registry_release",
        "WHERE registry_id = ? AND resolved_reference = ?"
      ),
      params = list(registry_id, resolved$resolved_commit)
    )
    if (nrow(duplicate) > 0L) {
      stop_duplicate_snapshot(
        "pronom_repository_commit", resolved$resolved_commit,
        as.character(duplicate$registry_release_id[[1L]])
      )
    }
    archive_path <- file.path(temporary_directory, "repository.tar.gz")
    report_import_progress(progress, "download", message = "Downloading repository archive")
    downloader(resolved, archive_path)
    archive_checksum <- digest::digest(
      file = archive_path, algo = "sha256", serialize = FALSE
    )
    duplicate_archive <- DBI::dbGetQuery(
      connection,
      paste(
        "SELECT registry_release_id FROM registry_release",
        "WHERE registry_id = ? AND archive_checksum_sha256 = ?"
      ),
      params = list(registry_id, archive_checksum)
    )
    if (nrow(duplicate_archive) > 0L) {
      stop_duplicate_snapshot(
        "pronom_repository_archive", archive_checksum,
        as.character(duplicate_archive$registry_release_id[[1L]])
      )
    }
    extracted <- file.path(temporary_directory, "extracted")
    dir.create(extracted)
    parsed_repository <- parse_pronom_repository_archive(
      archive_path, extracted, progress
    )
    snapshot_id <- persist_pronom_repository(
      connection, registry_id, import_run_id, resolved, archive_path,
      archive_checksum, parsed_repository
    )
    summary <- parsed_repository$summary
    report_import_progress(progress, "complete", summary$parsed_count,
                           summary$discovered_count, "Repository import complete")
    list(
      snapshot_id = snapshot_id,
      import_run_id = import_run_id,
      resolved = resolved,
      archive_checksum_sha256 = archive_checksum,
      summary = summary
    )
  }, error = function(error) {
    DBI::dbExecute(
      connection,
      paste(
        "UPDATE import_run SET status = 'failed', summary_message = ?,",
        "completed_at = current_timestamp WHERE import_run_id = ?"
      ),
      params = list(conditionMessage(error), import_run_id)
    )
    stop(error)
  })
}

persist_pronom_repository <- function(connection, registry_id, import_run_id,
                                      resolved, archive_path, archive_checksum,
                                      repository) {
  snapshot_id <- database_uuids(connection, 1L)[[1L]]
  release_id <- database_uuids(connection, 1L)[[1L]]
  archive <- readBin(archive_path, "raw", file.info(archive_path)$size)
  metadata <- data.frame(
    source_type = "pronom_repository",
    source_version = resolved$resolved_commit,
    source_created_at = resolved$commit_date,
    stringsAsFactors = FALSE
  )
  parsed_records <- repository$parsed_records
  DBI::dbWithTransaction(connection, {
    DBI::dbExecute(
      connection,
      paste(
        "INSERT INTO registry_release",
        "(registry_release_id, registry_id, release_kind, requested_reference,",
        "resolved_reference, released_at, archive_checksum_sha256)",
        "VALUES (?, ?, 'repository_commit', ?, ?, ?, ?)"
      ),
      params = list(
        release_id, registry_id, resolved$requested_reference,
        resolved$resolved_commit, parse_source_timestamp(resolved$commit_date),
        archive_checksum
      )
    )
    validation_schema_id <- ensure_source_validation_schema(
      connection, repository$validation_schema
    )
    insert_snapshot(
      connection, snapshot_id, metadata, archive_checksum, archive,
      sprintf("%s-%s.tar.gz", resolved$repository, substr(resolved$resolved_commit, 1L, 12L)),
      resolved$repository_url, validation_schema_id
    )
    DBI::dbExecute(
      connection,
      paste(
        "UPDATE source_snapshot SET registry_release_id = ?, import_run_id = ?",
        "WHERE snapshot_id = ?"
      ),
      params = list(release_id, import_run_id, snapshot_id)
    )
    record_map <- insert_repository_records(connection, snapshot_id, repository$records)
    format_map <- insert_repository_formats(
      connection, snapshot_id, registry_id, parsed_records, record_map
    )
    identifiers <- combine_parser_tables(parsed_records, "identifiers")
    extensions <- combine_parser_tables(parsed_records, "extensions")
    signatures <- combine_parser_tables(parsed_records, "signatures")
    relationships <- combine_parser_tables(parsed_records, "relationships")
    if (!is.null(identifiers)) insert_source_identifiers(connection, identifiers, format_map)
    if (!is.null(extensions)) insert_source_extensions(connection, extensions, format_map)
    if (!is.null(signatures)) insert_source_signatures(connection, signatures, format_map)
    if (!is.null(relationships)) {
      insert_source_relationships(connection, snapshot_id, relationships)
    }
    summaries <- repository_preservation_summaries(
      parsed_records, repository$summary, repository$excluded_count,
      repository$records
    )
    insert_source_summaries(connection, snapshot_id, summaries)
    summary <- repository$summary
    DBI::dbExecute(
      connection,
      paste(
        "UPDATE import_run SET resolved_commit = ?, resolved_commit_at = ?,",
        "archive_checksum_sha256 = ?, status = 'succeeded',",
        "discovered_count = ?, parsed_count = ?, rejected_count = ?,",
        "warning_count = ?, error_count = ?, completed_at = current_timestamp",
        "WHERE import_run_id = ?"
      ),
      params = list(
        resolved$resolved_commit, parse_source_timestamp(resolved$commit_date),
        archive_checksum, summary$discovered_count, summary$parsed_count,
        summary$rejected_count, summary$warning_count, summary$error_count,
        import_run_id
      )
    )
  })
  snapshot_id
}

insert_repository_records <- function(connection, snapshot_id, records) {
  ids <- database_uuids(connection, length(records))
  map <- data.frame(
    source_record_identifier = vapply(
      records, `[[`, character(1), "source_record_identifier"
    ),
    source_record_uuid = ids,
    stringsAsFactors = FALSE
  )
  for (index in seq_along(records)) {
    record <- records[[index]]
    DBI::dbExecute(
      connection,
      paste(
        "INSERT INTO source_record",
        "(source_record_uuid, snapshot_id, source_relative_path, source_filename,",
        "source_record_identifier, checksum_sha256, raw_content, parse_status)",
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
      ),
      params = list(
        ids[[index]], snapshot_id, record$source_relative_path,
        record$source_filename, null_if_missing(record$source_record_identifier),
        record$checksum_sha256, list(record$raw_content), record$parse_status
      )
    )
    if (nrow(record$issues) > 0L) {
      issue_ids <- database_uuids(connection, nrow(record$issues))
      for (issue_index in seq_len(nrow(record$issues))) {
        issue <- record$issues[issue_index, , drop = FALSE]
        DBI::dbExecute(
          connection,
          paste(
            "INSERT INTO source_record_issue",
            "(record_issue_id, source_record_uuid, severity, issue_code, message, raw_value, validation_layer)",
            "VALUES (?, ?, ?, ?, ?, ?, ?)"
          ),
          params = list(
            issue_ids[[issue_index]], ids[[index]], issue$severity,
            issue$issue_code, issue$message, null_if_missing(issue$raw_value),
            issue$validation_layer
          )
        )
      }
    }
  }
  map
}

insert_repository_formats <- function(connection, snapshot_id, registry_id,
                                      parsed_records, record_map) {
  formats <- combine_parser_tables(parsed_records, "formats")
  if (is.null(formats) || nrow(formats) == 0L) {
    return(data.frame(source_record_id = character(), source_format_id = character()))
  }
  identities <- ensure_format_identities(connection, registry_id, formats$puid)
  record_positions <- match(formats$puid, record_map$source_record_identifier)
  identity_positions <- match(formats$puid, identities$identifier)
  rows <- data.frame(
    source_format_id = database_uuids(connection, nrow(formats)),
    snapshot_id = snapshot_id,
    source_record_id = formats$source_record_id,
    puid = formats$puid,
    format_name = formats$format_name,
    format_version = formats$format_version,
    raw_record = NA_character_,
    source_record_uuid = record_map$source_record_uuid[record_positions],
    format_identity_id = identities$format_identity_id[identity_positions],
    stringsAsFactors = FALSE
  )
  DBI::dbAppendTable(connection, "source_format", rows)
  insert_source_format_identity_links(connection, rows)
  rows[c("source_record_id", "source_format_id")]
}
