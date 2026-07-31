new_query_test_database <- function() {
  path <- tempfile(fileext = ".duckdb")
  connection <- open_workbench_database(path)
  initialise_workbench_database(connection, project_path("inst", "schema"))
  list(connection = connection, path = path)
}

close_query_test_database <- function(database) {
  DBI::dbDisconnect(database$connection, shutdown = TRUE)
  unlink(database$path)
}

test_that("active source context produces one row per PUID with PRONOM precedence", {
  database <- new_query_test_database()
  on.exit(close_query_test_database(database), add = TRUE)
  pronom_id <- import_pronom_json(
    database$connection, project_path("data", "raw", "104.json")
  )
  droid_id <- import_droid_xml(
    database$connection,
    project_path("data", "raw", "DROID_SignatureFile_V124.xml")
  )

  formats <- list_integrated_formats(database$connection, pronom_id, droid_id)
  selected <- formats[formats$puid == "fmt/104", , drop = FALSE]

  expect_equal(nrow(formats), 2557L)
  expect_equal(anyDuplicated(formats$puid), 0L)
  expect_equal(nrow(selected), 1L)
  expect_true(selected$present_in_pronom)
  expect_true(selected$present_in_droid)
  expect_equal(selected$format_name, "Macromedia Flash")
  expect_equal(selected$mime_types, "application/x-shockwave-flash")
  expect_equal(selected$extensions, "swf")
  expect_gte(selected$droid_internal_signature_references, 0)
})

test_that("coverage and missing-value filters operate on integrated rows", {
  formats <- data.frame(
    puid = c("fmt/1", "fmt/2", "fmt/3"),
    format_name = c("Both", "PRONOM", "DROID"),
    format_version = "",
    mime_types = c("audio/wav", "", "application/test"),
    extensions = c("wav", "prn", ""),
    present_in_pronom = c(TRUE, TRUE, FALSE),
    present_in_droid = c(TRUE, FALSE, TRUE),
    droid_internal_signature_references = c(1L, 0L, 0L)
  )

  expect_equal(
    filter_integrated_formats(formats, "", "both")$puid, "fmt/1"
  )
  expect_equal(
    filter_integrated_formats(formats, "", "pronom_only")$puid, "fmt/2"
  )
  expect_equal(
    filter_integrated_formats(formats, "", "droid_only")$puid, "fmt/3"
  )
  expect_equal(
    filter_integrated_formats(formats, "", missing_mime = TRUE)$puid, "fmt/2"
  )
  expect_equal(
    filter_integrated_formats(formats, "", missing_extension = TRUE)$puid, "fmt/3"
  )
  expect_setequal(
    filter_integrated_formats(formats, "", no_droid_signature = TRUE)$puid,
    c("fmt/2", "fmt/3")
  )
  expect_equal(
    filter_integrated_formats(formats, "application/test")$puid, "fmt/3"
  )
})

test_that("format details retain source provenance and compare source sets", {
  database <- new_query_test_database()
  on.exit(close_query_test_database(database), add = TRUE)
  pronom_id <- import_pronom_json(
    database$connection, project_path("data", "raw", "104.json")
  )
  droid_id <- import_droid_xml(
    database$connection,
    project_path("data", "raw", "DROID_SignatureFile_V124.xml")
  )

  detail <- get_integrated_format_details(
    database$connection, "fmt/104", pronom_id, droid_id
  )

  expect_equal(nrow(detail$observations), 2L)
  expect_setequal(
    detail$observations$source_type,
    c("pronom_json", "droid_binary_signature")
  )
  expect_true(all(c(
    "overview", "identifiers", "mime_types", "extensions", "signatures",
    "pronom_relationships", "droid_priorities", "raw_pronom_json",
    "droid_xml_fragment", "consistency", "unsupported", "issues"
  ) %in% names(detail)))
  expect_setequal(
    detail$consistency$field,
    c("Name", "Version", "MIME types", "Extensions")
  )
  expect_equal(detail$overview$puid, "fmt/104")
  expect_match(detail$overview$description, "Adobe Flash format")
  expect_true(nrow(detail$pronom_relationships) > 0L)
  expect_true(all(
    detail$signatures$source_type == "droid_binary_signature"
  ))
  expect_match(detail$raw_pronom_json, '"formatName": "Macromedia Flash"')
  expect_match(detail$droid_xml_fragment, 'PUID="fmt/104"', fixed = TRUE)
})

test_that("snapshot detail exposes source, coverage and schema metrics", {
  database <- new_query_test_database()
  on.exit(close_query_test_database(database), add = TRUE)
  snapshot_id <- import_pronom_json(
    database$connection, project_path("data", "raw", "104.json")
  )

  detail <- get_snapshot_import_detail(database$connection, snapshot_id)

  expect_equal(detail$counts$imported_record_count, 1)
  expect_equal(detail$counts$warning_count, 0)
  expect_equal(detail$counts$error_count, 0)
  expect_equal(detail$metadata$source_type, "pronom_json")
  expect_match(detail$metadata$imported_at, "^20[0-9]{2}-[0-9]{2}-[0-9]{2} ")
  expect_match(detail$metadata$imported_at, " UTC$")
  metric_value <- function(name) {
    detail$metrics$value[detail$metrics$metric == name]
  }
  expect_equal(metric_value("fmt PUIDs"), "1")
  expect_equal(metric_value("x-fmt PUIDs"), "0")
  expect_equal(metric_value("Unique PUIDs"), "1")
  expect_equal(metric_value("With internal-signature references"), "1")
  expect_equal(metric_value("Without MIME type"), "0")
  expect_equal(metric_value("Without extension"), "0")
  expect_equal(metric_value("Strict official-schema violations"), "7")
  expect_equal(metric_value("Compatibility-schema validation"), "Passed")
  expect_equal(metric_value("Compatibility overlay"), "pronom-develop-2026-07.2")
  expect_equal(nrow(detail$issues), 0L)
})

test_that("numeric database timestamps are formatted as readable UTC values", {
  expect_equal(
    format_source_timestamp(1785326013.69),
    "2026-07-29 11:53:33 UTC"
  )
  expect_true(is.na(format_source_timestamp(NA_real_)))
})

test_that("DROID snapshot schema metrics are clearly not applicable", {
  database <- new_query_test_database()
  on.exit(close_query_test_database(database), add = TRUE)
  snapshot_id <- import_droid_xml(
    database$connection,
    project_path("data", "raw", "DROID_SignatureFile_V124.xml")
  )

  detail <- get_snapshot_details(database$connection, snapshot_id)
  metric_value <- function(name) {
    detail$metrics$value[detail$metrics$metric == name]
  }

  expect_equal(detail$metadata$source_type, "droid_binary_signature")
  expect_equal(metric_value("Strict official-schema violations"), "Unavailable")
  expect_equal(metric_value("Compatibility-schema validation"), "Not applicable")
  expect_equal(metric_value("Compatibility overlay"), "Not applicable")
  expect_equal(metric_value("DROID support mode"), "puid_comparison")
  expect_equal(metric_value("Valid PUID records"), "2557")
})

test_that("snapshot-only DROID releases are visible as snapshots but not Explorer choices", {
  database <- new_query_test_database()
  on.exit(close_query_test_database(database), add = TRUE)
  snapshot_id <- import_droid_xml(
    database$connection,
    project_path("data", "raw", "DROID_SignatureFile_V1.xml")
  )

  snapshots <- list_source_snapshots(database$connection)
  detail <- get_snapshot_details(database$connection, snapshot_id)
  choices <- list_source_snapshot_choices(database$connection, "droid")
  metric_value <- function(name) {
    detail$metrics$value[detail$metrics$metric == name]
  }

  expect_equal(snapshots$format_count[snapshots$snapshot_id == snapshot_id], 541L)
  expect_equal(detail$counts$imported_record_count, 541L)
  expect_equal(metric_value("DROID support mode"), "snapshot_only")
  expect_equal(metric_value("Valid PUID records"), "0")
  expect_equal(metric_value("Placeholder PUID records"), "134")
  expect_false(snapshot_id %in% choices$snapshot_id)
})

test_that("DROID release comparison uses explicit PUIDs and rejects snapshot-only releases", {
  database <- new_query_test_database()
  on.exit(close_query_test_database(database), add = TRUE)
  fixture <- function(version, formats) {
    path <- tempfile(fileext = ".xml")
    writeLines(c(
      sprintf('<FFSignatureFile Version="%s">', version),
      "<InternalSignatureCollection />",
      sprintf("<FileFormatCollection>%s</FileFormatCollection>", formats),
      "</FFSignatureFile>"
    ), path, useBytes = TRUE)
    path
  }
  left_path <- fixture(
    "5",
    paste0(
      '<FileFormat ID="1" PUID="fmt/1" Name="One" />',
      '<FileFormat ID="2" PUID="Not yet assigned" Name="Unresolved" />'
    )
  )
  right_path <- fixture(
    "10",
    paste0(
      '<FileFormat ID="1" PUID="fmt/1" Name="One revised" />',
      '<FileFormat ID="3" PUID="fmt/3" Name="Three" />'
    )
  )
  snapshot_only_path <- fixture(
    "1", '<FileFormat ID="9" Name="No PUID" />'
  )
  on.exit(unlink(c(left_path, right_path, snapshot_only_path)), add = TRUE)
  left_id <- import_droid_xml(database$connection, left_path)
  right_id <- import_droid_xml(database$connection, right_path)
  snapshot_only_id <- import_droid_xml(database$connection, snapshot_only_path)

  comparison <- compare_droid_snapshots(
    database$connection, left_id, right_id
  )

  expect_setequal(comparison$puid, c("fmt/1", "fmt/3"))
  expect_true(comparison$present_left[comparison$puid == "fmt/1"])
  expect_false(comparison$present_left[comparison$puid == "fmt/3"])
  expect_error(
    compare_droid_snapshots(database$connection, snapshot_only_id, right_id),
    "snapshot-only"
  )
})

test_that("format identity migration backfills unlinked existing observations", {
  database <- new_query_test_database()
  on.exit(close_query_test_database(database), add = TRUE)
  snapshot_id <- import_pronom_json(
    database$connection, project_path("data", "raw", "104.json")
  )
  DBI::dbExecute(database$connection, "DELETE FROM source_format_identity")
  DBI::dbExecute(
    database$connection,
    paste(readLines(
      project_path("inst", "schema", "004-integrated-format-identity.sql"),
      warn = FALSE
    ), collapse = "\n")
  )

  linked <- DBI::dbGetQuery(
    database$connection,
    paste(
      "SELECT identity.identifier",
      "FROM source_format AS format",
      "JOIN source_format_identity AS link",
      " ON link.source_format_id = format.source_format_id",
      "JOIN format_identity AS identity",
      " ON identity.format_identity_id = link.format_identity_id",
      "WHERE format.snapshot_id = ?"
    ),
    params = list(snapshot_id)
  )
  expect_equal(linked$identifier, "fmt/104")
})
