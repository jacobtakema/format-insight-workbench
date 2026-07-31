list_format_profiles <- function(connection) {
  DBI::dbGetQuery(connection, paste(
    "SELECT CAST(profile_id AS VARCHAR) AS profile_id, name, version, publisher,",
    "CAST(publication_date AS VARCHAR) AS publication_date, source_name, source_url,",
    "CAST(profile.source_snapshot_id AS VARCHAR) AS source_snapshot_id, snapshot.imported_at",
    "FROM policy_profile AS profile LEFT JOIN source_snapshot AS snapshot",
    "ON snapshot.snapshot_id = profile.source_snapshot_id ORDER BY profile.created_at DESC"
  ))
}

get_profile_overview <- function(connection, profile_id) {
  profiles <- list_format_profiles(connection)
  metadata <- profiles[profiles$profile_id == profile_id, , drop = FALSE]
  entries <- DBI::dbGetQuery(connection, paste(
    "SELECT CAST(entry.entry_id AS VARCHAR) AS entry_id, entry.source_row, entry.information_category, entry.information_subtype,",
    "entry.display_name, entry.extension_label, entry.version_label,",
    "entry.source_status, entry.preferred_status, entry.notes, entry.rationale,",
    "entry.mapping_status, string_agg(mapping.puid, ', ' ORDER BY mapping.puid) AS puids",
    "FROM policy_entry AS entry LEFT JOIN policy_entry_puid AS mapping",
    "ON mapping.entry_id = entry.entry_id WHERE entry.profile_id = ?",
    "GROUP BY ALL ORDER BY entry.source_row"
  ), params = list(profile_id))
  if (nrow(entries)) {
    mappings <- DBI::dbGetQuery(connection, paste(
      "SELECT CAST(mapping.entry_id AS VARCHAR) AS entry_id, mapping.puid, mapping.mapping_status",
      "FROM policy_entry_puid AS mapping JOIN policy_entry AS entry ON entry.entry_id = mapping.entry_id",
      "WHERE entry.profile_id = ?"
    ), params = list(profile_id))
    known <- DBI::dbGetQuery(connection, paste(
      "SELECT DISTINCT identity.identifier AS puid FROM format_identity AS identity",
      "JOIN source_format AS observed ON observed.format_identity_id = identity.format_identity_id",
      "JOIN source_snapshot AS snapshot ON snapshot.snapshot_id = observed.snapshot_id",
      "WHERE snapshot.source_type IN ('pronom_json', 'pronom_repository')"
    ))$puid
    entries$mapping_status <- vapply(entries$entry_id, function(entry_id) {
      values <- mappings[mappings$entry_id == entry_id, , drop = FALSE]
      if (!nrow(values)) return("no_puid")
      if (any(values$mapping_status == "invalid_puid")) return("invalid_puid")
      if (all(values$puid %in% known)) "mapped" else "unknown_puid"
    }, character(1))
  }
  issues <- if (!nrow(metadata)) data.frame() else DBI::dbGetQuery(connection, paste(
    "SELECT severity, record_locator AS source_row, issue_code, message",
    "FROM source_import_issue WHERE snapshot_id = ? ORDER BY severity DESC, record_locator"
  ), params = list(metadata$source_snapshot_id[[1L]]))
  duplicate <- DBI::dbGetQuery(connection, paste(
    "SELECT puid, count(DISTINCT entry_id) AS entry_count FROM policy_entry_puid",
    "WHERE entry_id IN (SELECT entry_id FROM policy_entry WHERE profile_id = ?)",
    "AND mapping_status <> 'invalid_puid' GROUP BY puid HAVING count(DISTINCT entry_id) > 1",
    "ORDER BY puid"
  ), params = list(profile_id))
  status <- if (nrow(entries)) as.data.frame(table(entries$preferred_status),
                                             stringsAsFactors = FALSE) else data.frame()
  category <- if (nrow(entries)) as.data.frame(table(entries$information_category,
                                                      useNA = "ifany"),
                                               stringsAsFactors = FALSE) else data.frame()
  metrics <- data.frame(metric = c(
    "Entries", "Mapped to imported PRONOM", "Unmapped entries", "Unknown PUID", "Invalid PUID",
    "No PUID", "Duplicate PUID references", "Mapping coverage"
  ), value = c(
    nrow(entries), sum(entries$mapping_status == "mapped"), sum(entries$mapping_status != "mapped"),
    sum(entries$mapping_status == "unknown_puid"),
    sum(entries$mapping_status == "invalid_puid"),
    sum(entries$mapping_status == "no_puid"), nrow(duplicate),
    if (nrow(entries)) sprintf("%.1f%%", 100 * sum(entries$mapping_status == "mapped") / nrow(entries)) else "0.0%"
  ), stringsAsFactors = FALSE)
  list(metadata = metadata, metrics = metrics, status = status,
       category = category, entries = entries, duplicates = duplicate, issues = issues)
}

get_puid_profile_statements <- function(connection, puid) {
  DBI::dbGetQuery(connection, paste(
    "SELECT profile.name AS profile_name, profile.version AS profile_version,",
    "entry.preferred_status, entry.source_status, entry.information_category,",
    "entry.information_subtype, entry.display_name, entry.extension_label,",
    "entry.version_label, entry.notes, entry.rationale, entry.source_sheet,",
    "entry.source_row, CASE WHEN EXISTS (SELECT 1 FROM format_identity AS identity",
    " JOIN source_format AS observed ON observed.format_identity_id = identity.format_identity_id",
    " JOIN source_snapshot AS snapshot ON snapshot.snapshot_id = observed.snapshot_id",
    " WHERE identity.identifier = mapping.puid",
    " AND snapshot.source_type IN ('pronom_json', 'pronom_repository'))",
    " THEN 'mapped' ELSE 'unknown_puid' END AS mapping_status,",
    "mapping.raw_puid, profile.source_name,",
    "profile.source_url FROM policy_entry_puid AS mapping",
    "JOIN policy_entry AS entry ON entry.entry_id = mapping.entry_id",
    "JOIN policy_profile AS profile ON profile.profile_id = entry.profile_id",
    "WHERE mapping.puid = ? AND mapping.mapping_status <> 'invalid_puid'",
    "ORDER BY profile.name, entry.source_row"
  ), params = list(puid))
}
