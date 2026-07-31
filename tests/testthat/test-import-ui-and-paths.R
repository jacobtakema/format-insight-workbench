test_that("uploaded source records preserve visible names and relative paths", {
  upload <- data.frame(
    name = c("fmt/1.json", "x-fmt/2.json"),
    datapath = c("temporary-a", "temporary-b"),
    stringsAsFactors = FALSE
  )

  records <- uploaded_source_records(upload, "pronom_json")
  expect_equal(records$source_filename, c("1.json", "2.json"))
  expect_equal(records$source_relative_path, c("fmt/1.json", "x-fmt/2.json"))
  expect_equal(records$source_type, rep("pronom_json", 2L))
})

test_that("project and database paths do not depend on the working directory", {
  nested <- project_path("tests", "testthat")
  expect_equal(find_workbench_project_root(project_root), project_root)
  expect_equal(find_workbench_project_root(nested), project_root)
  empty_project <- tempfile("format-insight-workbench-")
  dir.create(file.path(empty_project, "data"), recursive = TRUE)
  on.exit(unlink(empty_project, recursive = TRUE), add = TRUE)
  expect_equal(
    workbench_database_path(empty_project),
    file.path(empty_project, "data", "format-insight-workbench.duckdb")
  )
  legacy_database <- file.path(
    empty_project, "data", "format-policy-workbench.duckdb"
  )
  file.create(legacy_database)
  expect_equal(workbench_database_path(empty_project), legacy_database)
  file_name_alias <- file.path(
    empty_project, "data", "file-insight-workbench.duckdb"
  )
  file.create(file_name_alias)
  expect_equal(workbench_database_path(empty_project), file_name_alias)
  current_database <- file.path(
    empty_project, "data", "format-insight-workbench.duckdb"
  )
  file.create(current_database)
  expect_equal(workbench_database_path(empty_project), current_database)
  expect_equal(
    workbench_database_path(project_root, "data/custom.duckdb"),
    normalizePath(
      file.path(project_root, "data", "custom.duckdb"),
      winslash = "/",
      mustWork = FALSE
    )
  )
  expect_equal(
    source_relative_path(project_path("data", "raw", "1.json"), project_root),
    "data/raw/1.json"
  )
})

test_that("multiple uploaded PRONOM records report success and validation failures", {
  database_path <- tempfile(fileext = ".duckdb")
  connection <- open_workbench_database(database_path)
  initialise_workbench_database(
    connection,
    project_path("inst", "schema", "001-initial.sql")
  )
  on.exit({
    DBI::dbDisconnect(connection, shutdown = TRUE)
    unlink(database_path)
  }, add = TRUE)
  invalid <- tempfile(fileext = ".json")
  writeLines(
    '{"fileFormatID":1,"formatName":"Broken","identifiers":[],"internalSignatures":[]}',
    invalid
  )
  on.exit(unlink(invalid), add = TRUE)
  records <- data.frame(
    source_type = c("pronom_json", "pronom_json"),
    source_filename = c("104.json", "broken.json"),
    source_relative_path = c("fmt/104.json", "fmt/broken.json"),
    path = c(project_path("data", "raw", "104.json"), invalid),
    stringsAsFactors = FALSE
  )

  result <- import_source_records(connection, records)
  expect_equal(result$success_count, 1L)
  expect_equal(result$status$kind, "danger")
  expect_true(any(grepl("validation failed", result$status$messages, ignore.case = TRUE)))
})
