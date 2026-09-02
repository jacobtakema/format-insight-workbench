create_repository_archive <- function(files) {
  workspace <- tempfile("repository-fixture-")
  root <- file.path(workspace, "pronom-fixture")
  dir.create(root, recursive = TRUE)
  for (relative_path in names(files)) {
    destination <- file.path(root, relative_path)
    dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
    if (length(files[[relative_path]]) == 1L && file.exists(files[[relative_path]])) {
      file.copy(files[[relative_path]], destination)
    } else {
      writeLines(files[[relative_path]], destination, useBytes = TRUE)
    }
  }
  if (!"format_schema.json" %in% names(files)) {
    file.copy(
      project_path("inst", "extdata", "pronom", "format_schema.json"),
      file.path(root, "format_schema.json")
    )
  }
  archive <- tempfile(fileext = ".tar.gz")
  old <- setwd(workspace)
  on.exit(setwd(old), add = TRUE)
  utils::tar(archive, basename(root), compression = "gzip", tar = "internal")
  unlink(workspace, recursive = TRUE)
  archive
}

repository_resolution <- function() {
  list(
    repository_url = "https://github.com/nationalarchives/pronom",
    owner = "nationalarchives",
    repository = "pronom",
    requested_reference = "develop",
    resolved_commit = paste(rep("a", 40L), collapse = ""),
    commit_date = "2026-07-01T12:00:00Z",
    archive_url = "mock://archive"
  )
}

test_that("GitHub repository references resolve to immutable commits without Git", {
  mock_request <- function(url, ...) {
    structure(list(
      url = url,
      status_code = 200L,
      headers = list(`content-type` = "application/json"),
      all_headers = list(),
      cookies = data.frame(),
      content = charToRaw(paste0(
        '{"sha":"', paste(rep("b", 40L), collapse = ""),
        '","commit":{"committer":{"date":"2026-07-02T10:00:00Z"}}}'
      )),
      date = Sys.time(),
      times = numeric(),
      request = list()
    ), class = "response")
  }
  resolved <- resolve_github_reference(
    "https://github.com/nationalarchives/pronom.git", "develop",
    request = mock_request
  )
  expect_equal(resolved$resolved_commit, paste(rep("b", 40L), collapse = ""))
  expect_equal(resolved$commit_date, "2026-07-02T10:00:00Z")
  expect_match(resolved$archive_url, "/tarball/")
})

test_that("archive discovery handles fmt, x-fmt and excluded files", {
  archive <- create_repository_archive(list(
    "signatures/fmt/1.json" = project_path("data", "raw", "1.json"),
    "signatures/x-fmt/2.json" = '{"fileFormatID":2,"formatName":"X","identifiers":[{"identifierType":"PUID","identifierText":"x-fmt/2"}],"internalSignatures":[]}',
    "README.md" = "ignored"
  ))
  extraction <- tempfile("extract-")
  dir.create(extraction)
  on.exit(unlink(c(archive, extraction), recursive = TRUE), add = TRUE)

  discovered <- discover_pronom_archive(archive, extraction)
  expect_setequal(
    discovered$records$source_relative_path,
    c("signatures/fmt/1.json", "signatures/x-fmt/2.json")
  )
  expect_true(discovered$excluded_count > 0L)
})

test_that("repository parsing rejects malformed records and PUID path mismatches", {
  archive <- create_repository_archive(list(
    "signatures/fmt/1.json" = project_path("data", "raw", "1.json"),
    "signatures/fmt/999.json" = "{broken",
    "signatures/fmt/105.json" = project_path("data", "raw", "104.json")
  ))
  extraction <- tempfile("extract-")
  dir.create(extraction)
  on.exit(unlink(c(archive, extraction), recursive = TRUE), add = TRUE)

  parsed <- parse_pronom_repository_archive(archive, extraction)
  expect_equal(parsed$summary$discovered_count, 3L)
  expect_equal(parsed$summary$parsed_count, 1L)
  expect_equal(parsed$summary$rejected_count, 2L)
  issue_codes <- unlist(lapply(parsed$records, function(record) record$issues$issue_code))
  expect_true("json_syntax_error" %in% issue_codes)
  expect_true("puid_path_mismatch" %in% issue_codes)
})

test_that("repository parsing retains a parent with an empty external signature", {
  archive <- create_repository_archive(list(
    "signatures/fmt/199.json" = paste0(
      '{"fileFormatID":924,"formatName":"MPEG-4 Media File",',
      '"identifiers":[{"identifierText":"fmt/199","identifierType":"PUID"}],',
      '"internalSignatures":[],"externalSignatures":[',
      '{"externalSignature":"mp4","signatureType":"File extension"},',
      '{"externalSignature":"","signatureType":"File extension"}]}'
    )
  ))
  extraction <- tempfile("extract-")
  dir.create(extraction)
  on.exit(unlink(c(archive, extraction), recursive = TRUE), add = TRUE)

  parsed <- parse_pronom_repository_archive(archive, extraction)
  record <- parsed$parsed_records[[1L]]$parsed

  expect_equal(parsed$summary$parsed_count, 1L)
  expect_equal(parsed$summary$rejected_count, 0L)
  expect_equal(parsed$summary$warning_count, 1L)
  expect_equal(record$formats$puid, "fmt/199")
  expect_equal(record$extensions$extension, "mp4")
})

test_that("repository parsing preserves and rejects duplicate PRONOM record IDs", {
  record <- function(puid, name) paste0(
    '{"fileFormatID":3983,"formatName":"', name, '",',
    '"identifiers":[{"identifierText":"', puid,
    '","identifierType":"PUID"}],"internalSignatures":[]}'
  )
  archive <- create_repository_archive(list(
    "signatures/fmt/2106.json" = record("fmt/2106", "First format"),
    "signatures/fmt/2107.json" = record("fmt/2107", "Second format")
  ))
  extraction <- tempfile("extract-")
  dir.create(extraction)
  on.exit(unlink(c(archive, extraction), recursive = TRUE), add = TRUE)

  parsed <- parse_pronom_repository_archive(archive, extraction)

  expect_equal(parsed$summary$parsed_count, 0L)
  expect_equal(parsed$summary$rejected_count, 2L)
  expect_equal(parsed$summary$error_count, 2L)
  expect_true(all(vapply(parsed$records, function(value) {
    "duplicate_source_record_id" %in% value$issues$issue_code
  }, logical(1))))
  expect_true(all(vapply(parsed$records, function(value) {
    identical(value$parse_status, "rejected") && is.null(value$parsed)
  }, logical(1))))
})

test_that("repository import is transactional, rejects duplicates and cleans temporary files", {
  archive <- create_repository_archive(list(
    "signatures/fmt/1.json" = project_path("data", "raw", "1.json"),
    "signatures/fmt/104.json" = project_path("data", "raw", "104.json")
  ))
  database_path <- tempfile(fileext = ".duckdb")
  connection <- open_workbench_database(database_path)
  initialise_workbench_database(connection, project_path("inst", "schema"))
  on.exit({
    DBI::dbDisconnect(connection, shutdown = TRUE)
    unlink(c(archive, database_path))
  }, add = TRUE)
  temporary <- tempfile("repository-import-")
  downloader <- function(resolved, destination) {
    file.copy(archive, destination)
    destination
  }

  imported <- import_pronom_repository(
    connection,
    "https://github.com/nationalarchives/pronom",
    "develop",
    resolved = repository_resolution(),
    downloader = downloader,
    temporary_directory_factory = function() temporary
  )
  expect_false(dir.exists(temporary))
  expect_equal(imported$summary$parsed_count, 2L)
  expect_equal(
    DBI::dbGetQuery(connection, "SELECT count(*) AS n FROM source_record")$n,
    2
  )
  expect_equal(
    DBI::dbGetQuery(connection, "SELECT count(*) AS n FROM source_format")$n,
    2
  )
  expect_error(
    import_pronom_repository(
      connection,
      "https://github.com/nationalarchives/pronom",
      "develop",
      resolved = repository_resolution(),
      downloader = downloader
    ),
    class = "format_policy_duplicate_snapshot"
  )
  expect_equal(
    DBI::dbGetQuery(connection, "SELECT count(*) AS n FROM source_snapshot")$n,
    1
  )
})

test_that("fatal archive failures are recorded and temporary files are cleaned", {
  database_path <- tempfile(fileext = ".duckdb")
  connection <- open_workbench_database(database_path)
  initialise_workbench_database(connection, project_path("inst", "schema"))
  on.exit({
    DBI::dbDisconnect(connection, shutdown = TRUE)
    unlink(database_path)
  }, add = TRUE)
  temporary <- tempfile("repository-failure-")
  failing_downloader <- function(resolved, destination) stop("download failed")

  expect_error(import_pronom_repository(
    connection,
    "https://github.com/nationalarchives/pronom",
    "develop",
    resolved = repository_resolution(),
    downloader = failing_downloader,
    temporary_directory_factory = function() temporary
  ), "download failed")
  expect_false(dir.exists(temporary))
  expect_equal(
    DBI::dbGetQuery(connection, "SELECT status FROM import_run")$status,
    "failed"
  )
  expect_equal(
    DBI::dbGetQuery(connection, "SELECT count(*) AS n FROM source_snapshot")$n,
    0
  )
})

test_that("repository snapshot persistence rolls back all release rows", {
  archive <- create_repository_archive(list(
    "signatures/fmt/1.json" = project_path("data", "raw", "1.json")
  ))
  extraction <- tempfile("extract-")
  dir.create(extraction)
  database_path <- tempfile(fileext = ".duckdb")
  connection <- open_workbench_database(database_path)
  initialise_workbench_database(connection, project_path("inst", "schema"))
  on.exit({
    DBI::dbDisconnect(connection, shutdown = TRUE)
    unlink(c(archive, extraction, database_path), recursive = TRUE)
  }, add = TRUE)
  repository <- parse_pronom_repository_archive(archive, extraction)
  repository$records <- c(repository$records, repository$records)
  registry_id <- ensure_pronom_registry(
    connection, "https://github.com/nationalarchives/pronom"
  )
  run_id <- create_import_run(
    connection, registry_id, "https://github.com/nationalarchives/pronom", "develop"
  )

  expect_error(persist_pronom_repository(
    connection, registry_id, run_id, repository_resolution(), archive,
    digest::digest(file = archive, algo = "sha256", serialize = FALSE),
    repository
  ))
  expect_equal(DBI::dbGetQuery(connection, "SELECT count(*) AS n FROM source_snapshot")$n, 0)
  expect_equal(DBI::dbGetQuery(connection, "SELECT count(*) AS n FROM registry_release")$n, 0)
  expect_equal(DBI::dbGetQuery(connection, "SELECT count(*) AS n FROM source_record")$n, 0)
})
