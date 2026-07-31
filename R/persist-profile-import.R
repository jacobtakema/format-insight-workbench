import_nl_profile_xlsx <- function(connection, path,
                                   source_filename = basename(path),
                                   source_relative_path = source_filename) {
  parsed <- parse_nl_profile_xlsx(path)
  persist_profile_import(connection, parsed, path, source_filename,
                         source_relative_path)
}

persist_profile_import <- function(connection, parsed, source_path,
                                   source_filename = basename(source_path),
                                   source_relative_path = source_filename) {
  if (!inherits(parsed, "format_profile_import")) {
    stop("'parsed' must be a format_profile_import result.", call. = FALSE)
  }
  checksum <- digest::digest(file = source_path, algo = "sha256", serialize = FALSE)
  duplicate <- DBI::dbGetQuery(connection, paste(
    "SELECT snapshot_id FROM source_snapshot",
    "WHERE source_type = 'format_profile_xlsx' AND checksum_sha256 = ?"
  ), params = list(checksum))
  if (nrow(duplicate)) {
    stop_duplicate_snapshot("format_profile_xlsx", checksum,
                            as.character(duplicate$snapshot_id[[1L]]))
  }
  snapshot_id <- database_uuids(connection, 1L)[[1L]]
  profile_id <- database_uuids(connection, 1L)[[1L]]
  source_bytes <- readBin(source_path, "raw", file.info(source_path)$size)
  metadata <- data.frame(
    source_type = "format_profile_xlsx", source_version = parsed$metadata$profile_version,
    source_created_at = NA_character_, stringsAsFactors = FALSE
  )

  DBI::dbWithTransaction(connection, {
    insert_snapshot(connection, snapshot_id, metadata, checksum, source_bytes,
                    source_filename, source_relative_path)
    DBI::dbExecute(connection, paste(
      "INSERT INTO policy_profile",
      "(profile_id, name, description, version, created_at, modified_at, publisher,",
      "publication_date, source_name, source_url, source_snapshot_id)",
      "VALUES (?, ?, ?, ?, current_timestamp, current_timestamp, ?, ?, ?, ?, ?)"
    ), params = list(
      profile_id, parsed$metadata$profile_name[[1L]],
      "Published preferred-format profile imported from its source workbook.",
      parsed$metadata$profile_version[[1L]], parsed$metadata$publisher[[1L]],
      parsed$metadata$publication_date[[1L]], source_filename,
      parsed$metadata$source_url[[1L]], snapshot_id
    ))

    entry_ids <- database_uuids(connection, nrow(parsed$entries))
    entry_map <- data.frame(source_row = parsed$entries$source_row,
                            entry_id = entry_ids, stringsAsFactors = FALSE)
    entry_status <- profile_entry_mapping_status(connection, parsed$mappings,
                                                 parsed$entries$source_row)
    entry_rows <- data.frame(
      entry_id = entry_ids, profile_id = profile_id,
      information_category = parsed$entries$category,
      display_name = parsed$entries$format_label,
      preferred_status = parsed$entries$preference_status,
      notes = parsed$entries$notes, condition = NA_character_,
      valid_from = as.Date(NA), valid_to = as.Date(NA),
      source_sheet = parsed$entries$source_sheet,
      source_row = parsed$entries$source_row,
      information_subtype = parsed$entries$information_subtype,
      extension_label = parsed$entries$extension_label,
      version_label = parsed$entries$version_label,
      source_status = parsed$entries$source_status,
      rationale = parsed$entries$rationale,
      raw_source_data = parsed$entries$raw_source_data,
      mapping_status = entry_status, stringsAsFactors = FALSE
    )
    DBI::dbAppendTable(connection, "policy_entry", entry_rows)

    resolved <- profile_mapping_resolution(connection, parsed$mappings)
    if (nrow(parsed$mappings)) {
      mapping_rows <- data.frame(
        mapping_id = database_uuids(connection, nrow(parsed$mappings)),
        entry_id = entry_map$entry_id[match(parsed$mappings$entry_source_row,
                                            entry_map$source_row)],
        puid = ifelse(is.na(parsed$mappings$puid), parsed$mappings$raw_puid,
                      parsed$mappings$puid),
        relationship_type = "source_asserted", required = FALSE,
        raw_puid = parsed$mappings$raw_puid,
        mapping_status = resolved, stringsAsFactors = FALSE
      )
      DBI::dbAppendTable(connection, "policy_entry_puid", mapping_rows)
    }

    rationale_ids <- database_uuids(connection, nrow(parsed$rationales))
    if (length(rationale_ids)) {
      rationale_rows <- data.frame(
        profile_rationale_id = rationale_ids, profile_id = profile_id,
        source_sheet = parsed$rationales$source_sheet,
        source_row = parsed$rationales$source_row,
        information_category = parsed$rationales$category,
        information_subtype = parsed$rationales$information_subtype,
        format_label = parsed$rationales$format_label,
        open_standard = parsed$rationales$open_standard,
        adoption_support = parsed$rationales$adoption_support,
        independence_interoperability = parsed$rationales$independence_interoperability,
        transparency = parsed$rationales$transparency,
        self_documenting = parsed$rationales$self_documenting,
        patents_licences = parsed$rationales$patents_licences,
        rationale = parsed$rationales$rationale,
        raw_source_data = parsed$rationales$raw_source_data,
        stringsAsFactors = FALSE
      )
      DBI::dbAppendTable(connection, "profile_rationale", rationale_rows)
    }
    if (nrow(parsed$rationale_links)) {
      links <- data.frame(
        profile_entry_id = entry_map$entry_id[match(
          parsed$rationale_links$entry_source_row, entry_map$source_row)],
        profile_rationale_id = rationale_ids[match(
          parsed$rationale_links$rationale_source_row,
          parsed$rationales$source_row)],
        link_method = parsed$rationale_links$link_method,
        stringsAsFactors = FALSE
      )
      DBI::dbAppendTable(connection, "profile_entry_rationale", links)
    }
    issues <- parsed$issues
    unknown <- which(resolved == "unknown_puid")
    if (length(unknown)) {
      derived <- lapply(unknown, function(index) parser_issue(
        "warning", "profile_unknown_puid",
        as.character(parsed$mappings$entry_source_row[[index]]),
        sprintf("PUID '%s' is not present in the currently imported PRONOM data.",
                parsed$mappings$puid[[index]]),
        parsed$mappings$raw_puid[[index]]
      ))
      issues <- rbind(issues, bind_parser_rows(derived, parser_issue_columns()))
    }
    insert_source_issues(connection, snapshot_id, issues)
    insert_source_summaries(connection, snapshot_id, parsed$summaries)
  })
  list(snapshot_id = snapshot_id, profile_id = profile_id)
}

profile_mapping_resolution <- function(connection, mappings) {
  result <- rep("invalid_puid", nrow(mappings))
  valid <- mappings$syntax_status == "valid" & !is.na(mappings$puid)
  if (!any(valid)) return(result)
  known <- DBI::dbGetQuery(connection, paste(
    "SELECT DISTINCT format.identifier AS puid FROM format_identity AS format",
    "JOIN source_format AS observed ON observed.format_identity_id = format.format_identity_id",
    "JOIN source_snapshot AS snapshot ON snapshot.snapshot_id = observed.snapshot_id",
    "WHERE snapshot.source_type IN ('pronom_json', 'pronom_repository')"
  ))$puid
  result[valid] <- ifelse(mappings$puid[valid] %in% known, "mapped", "unknown_puid")
  result
}

profile_entry_mapping_status <- function(connection, mappings, source_rows) {
  result <- rep("no_puid", length(source_rows))
  if (!nrow(mappings)) return(result)
  resolved <- profile_mapping_resolution(connection, mappings)
  for (index in seq_along(source_rows)) {
    values <- resolved[mappings$entry_source_row == source_rows[[index]]]
    if (!length(values)) next
    result[[index]] <- if (any(values == "invalid_puid")) "invalid_puid" else
      if (all(values == "mapped")) "mapped" else "unknown_puid"
  }
  result
}
