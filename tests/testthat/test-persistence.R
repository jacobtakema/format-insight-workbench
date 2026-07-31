new_test_database <- function() {
  path <- tempfile(fileext = ".duckdb")
  connection <- open_workbench_database(path)
  initialise_workbench_database(connection, project_path("inst", "schema", "001-initial.sql"))
  list(connection = connection, path = path)
}

close_test_database <- function(database) {
  DBI::dbDisconnect(database$connection, shutdown = TRUE)
  unlink(database$path)
}

test_that("successful PRONOM and DROID imports create immutable snapshots", {
  database <- new_test_database()
  on.exit(close_test_database(database), add = TRUE)

  pronom_id <- import_pronom_json(
    database$connection,
    project_path("data", "raw", "104.json")
  )
  droid_id <- import_droid_xml(
    database$connection,
    project_path("data", "raw", "DROID_SignatureFile_V124.xml")
  )

  snapshots <- DBI::dbGetQuery(
    database$connection,
    "SELECT snapshot_id, source_type, import_status, octet_length(raw_content) AS raw_size FROM source_snapshot"
  )
  expect_setequal(as.character(snapshots$snapshot_id), c(pronom_id, droid_id))
  expect_setequal(snapshots$source_type, c("pronom_json", "droid_binary_signature"))
  expect_true(all(snapshots$import_status == "succeeded"))
  expect_true(all(snapshots$raw_size > 0L))

  identity_links <- DBI::dbGetQuery(
    database$connection,
    paste(
      "SELECT snapshot.source_type, count(link.format_identity_id) AS linked_count",
      "FROM source_snapshot AS snapshot",
      "JOIN source_format AS format ON format.snapshot_id = snapshot.snapshot_id",
      "JOIN source_format_identity AS link ON link.source_format_id = format.source_format_id",
      "GROUP BY snapshot.source_type"
    )
  )
  expect_true(all(identity_links$linked_count > 0L))

  schema_provenance <- DBI::dbGetQuery(
    database$connection,
    paste(
      "SELECT snapshot.source_type, snapshot.validation_schema_id,",
      " schema.schema_dialect, schema.compatibility_id,",
      " octet_length(schema.raw_schema) AS raw_schema_size",
      "FROM source_snapshot AS snapshot",
      "LEFT JOIN source_validation_schema AS schema",
      " ON schema.validation_schema_id = snapshot.validation_schema_id"
    )
  )
  pronom_schema <- schema_provenance[
    schema_provenance$source_type == "pronom_json", , drop = FALSE
  ]
  droid_schema <- schema_provenance[
    schema_provenance$source_type == "droid_binary_signature", , drop = FALSE
  ]
  expect_false(is.na(pronom_schema$validation_schema_id))
  expect_equal(
    pronom_schema$schema_dialect,
    "http://json-schema.org/draft-07/schema#"
  )
  expect_equal(pronom_schema$compatibility_id, "pronom-develop-2026-07.2")
  expect_gt(pronom_schema$raw_schema_size, 0)
  expect_true(is.na(droid_schema$validation_schema_id))

  counts <- DBI::dbGetQuery(
    database$connection,
    "SELECT snapshot_id, count(*) AS format_count FROM source_format GROUP BY snapshot_id"
  )
  expect_equal(counts$format_count[match(pronom_id, as.character(counts$snapshot_id))], 1)
  expect_equal(counts$format_count[match(droid_id, as.character(counts$snapshot_id))], 2557)
})

test_that("a failed persistence transaction rolls back the entire snapshot", {
  database <- new_test_database()
  on.exit(close_test_database(database), add = TRUE)
  source_path <- project_path("data", "raw", "104.json")
  parsed <- parse_pronom_json(source_path)
  parsed$formats <- rbind(parsed$formats, parsed$formats)

  expect_error(persist_source_import(database$connection, parsed, source_path))
  expect_equal(DBI::dbGetQuery(database$connection, "SELECT count(*) AS n FROM source_snapshot")$n, 0)
  expect_equal(DBI::dbGetQuery(database$connection, "SELECT count(*) AS n FROM source_format")$n, 0)
})

test_that("an exact duplicate successful snapshot is rejected", {
  database <- new_test_database()
  on.exit(close_test_database(database), add = TRUE)
  source_path <- project_path("data", "raw", "104.json")

  original_id <- import_pronom_json(database$connection, source_path)
  error <- expect_error(
    import_pronom_json(database$connection, source_path),
    class = "format_policy_duplicate_snapshot"
  )

  expect_equal(error$existing_snapshot_id, original_id)
  expect_equal(DBI::dbGetQuery(database$connection, "SELECT count(*) AS n FROM source_snapshot")$n, 1)
})

test_that("source validation errors precede database constraint errors", {
  database <- new_test_database()
  on.exit(close_test_database(database), add = TRUE)
  path <- tempfile(fileext = ".json")
  writeLines(
    '{"fileFormatID":1,"formatName":"","identifiers":[],"internalSignatures":[]}',
    path,
    useBytes = TRUE
  )
  on.exit(unlink(path), add = TRUE)

  error <- expect_error(
    import_pronom_json(database$connection, path),
    class = "format_policy_source_validation_error"
  )
  expect_true(nrow(error$issues) > 0L)
  expect_equal(DBI::dbGetQuery(database$connection, "SELECT count(*) AS n FROM source_snapshot")$n, 0)
})

test_that("visible filename, relative path, summaries and raw bytes are persisted", {
  database <- new_test_database()
  on.exit(close_test_database(database), add = TRUE)
  path <- project_path("data", "raw", "104.json")
  snapshot_id <- import_pronom_json(
    database$connection,
    path,
    source_filename = "uploaded-104.json",
    source_relative_path = "selected/fmt/104.json"
  )

  snapshot <- DBI::dbGetQuery(
    database$connection,
    paste(
      "SELECT source_filename, source_relative_path, checksum_sha256, raw_content",
      "FROM source_snapshot WHERE snapshot_id = ?"
    ),
    params = list(snapshot_id)
  )
  summaries <- list_import_summaries(database$connection, snapshot_id)
  expect_equal(snapshot$source_filename, "uploaded-104.json")
  expect_equal(snapshot$source_relative_path, "selected/fmt/104.json")
  expect_equal(
    snapshot$checksum_sha256,
    digest::digest(file = path, algo = "sha256", serialize = FALSE)
  )
  expect_identical(snapshot$raw_content[[1L]], readBin(path, "raw", file.info(path)$size))
  expect_true(nrow(summaries) > 0L)
})

test_that("snapshot-only DROID imports preserve records without canonical formats", {
  database <- new_test_database()
  on.exit(close_test_database(database), add = TRUE)
  path <- project_path("data", "raw", "DROID_SignatureFile_V1.xml")

  snapshot_id <- import_droid_xml(database$connection, path)
  profile <- DBI::dbGetQuery(
    database$connection,
    "SELECT * FROM droid_snapshot_profile WHERE snapshot_id = ?",
    params = list(snapshot_id)
  )

  expect_equal(profile$support_mode, "snapshot_only")
  expect_equal(profile$format_count, 541L)
  expect_equal(profile$valid_puid_count, 0L)
  expect_equal(profile$placeholder_puid_count, 134L)
  expect_equal(
    DBI::dbGetQuery(
      database$connection,
      "SELECT count(*) AS n FROM source_record WHERE snapshot_id = ?",
      params = list(snapshot_id)
    )$n,
    541L
  )
  expect_equal(
    DBI::dbGetQuery(
      database$connection,
      "SELECT count(*) AS n FROM source_format WHERE snapshot_id = ?",
      params = list(snapshot_id)
    )$n,
    0L
  )
})

test_that("partial historical DROID imports separate resolved and unresolved records", {
  database <- new_test_database()
  on.exit(close_test_database(database), add = TRUE)
  path <- tempfile(fileext = ".xml")
  writeLines(c(
    '<FFSignatureFile Version="5"><InternalSignatureCollection />',
    '<FileFormatCollection>',
    '<FileFormat ID="1" PUID="fmt/1" Name="Resolved" />',
    '<FileFormat ID="2" PUID="Not yet assigned" Name="Unresolved" />',
    '</FileFormatCollection></FFSignatureFile>'
  ), path, useBytes = TRUE)
  on.exit(unlink(path), add = TRUE)

  snapshot_id <- import_droid_xml(database$connection, path)
  profile <- DBI::dbGetQuery(
    database$connection,
    "SELECT * FROM droid_snapshot_profile WHERE snapshot_id = ?",
    params = list(snapshot_id)
  )
  formats <- DBI::dbGetQuery(
    database$connection,
    "SELECT puid FROM source_format WHERE snapshot_id = ?",
    params = list(snapshot_id)
  )
  records <- DBI::dbGetQuery(
    database$connection,
    "SELECT source_record_identifier FROM source_record WHERE snapshot_id = ?",
    params = list(snapshot_id)
  )

  expect_equal(profile$support_mode, "partial_historical")
  expect_equal(profile$valid_puid_count, 1L)
  expect_equal(profile$placeholder_puid_count, 1L)
  expect_equal(formats$puid, "fmt/1")
  expect_equal(records$source_record_identifier, "2")
})

test_that("complete DROID V65 persists despite preserved source extension quirks", {
  database <- new_test_database()
  on.exit(close_test_database(database), add = TRUE)

  snapshot_id <- import_droid_xml(
    database$connection,
    project_path("data", "raw", "DROID_SignatureFile_V65.xml")
  )
  counts <- DBI::dbGetQuery(
    database$connection,
    paste(
      "SELECT",
      " (SELECT count(*) FROM source_format WHERE snapshot_id = ?) AS formats,",
      " (SELECT count(*) FROM source_import_issue WHERE snapshot_id = ?",
      "   AND severity = 'warning') AS warnings"
    ),
    params = list(snapshot_id, snapshot_id)
  )
  wav <- DBI::dbGetQuery(
    database$connection,
    paste(
      "SELECT count(*) AS n FROM source_format_extension AS extension",
      "JOIN source_format AS format",
      " ON format.source_format_id = extension.source_format_id",
      "WHERE format.snapshot_id = ? AND format.source_record_id = '784'",
      " AND extension.extension = 'wav'"
    ),
    params = list(snapshot_id)
  )

  expect_equal(counts$formats, 934L)
  expect_equal(counts$warnings, 2L)
  expect_equal(wav$n, 1L)
})
