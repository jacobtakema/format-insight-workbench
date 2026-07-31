test_that("profile PUID values support lists and explicit ranges", {
  parsed <- parse_profile_puid_value("fmt/1\nfmt/21-23 x-fmt/5", 10L)
  expect_equal(parsed$mappings$puid, c("fmt/1", "fmt/21", "fmt/22", "fmt/23", "x-fmt/5"))
  expect_true(all(parsed$mappings$syntax_status == "valid"))
})

test_that("profile PUID placeholders and invalid values remain explicit", {
  expect_equal(parse_profile_puid_value("Geen", 2L)$kind, "none")
  parsed <- parse_profile_puid_value("TSS-fmt/9", 3L)
  expect_true(is.na(parsed$mappings$puid[[1L]]))
  expect_equal(parsed$issues[[1L]]$issue_code, "profile_invalid_puid")
})

test_that("category rows are propagated and missing status is retained", {
  rows <- data.frame(
    Informatiesoort = c("Audio", NA, NA), Extensie = c(NA, "wav", "xml"),
    `Versie en/of profiel` = c(NA, "1", NA), `Formaat naam` = c(NA, "WAVE", "XML"),
    Status = c(NA, "Voorkeur", NA), PUID = c(NA, "fmt/1", "Geen"),
    Opmerkingen = NA_character_, check.names = FALSE, stringsAsFactors = FALSE
  )
  parsed <- parse_preferred_format_rows(rows)
  expect_equal(parsed$entries$category, c("Audio", "Audio"))
  expect_equal(parsed$entries$preference_status, c("preferred", "under_review"))
  expect_true("profile_missing_status" %in% parsed$issues$issue_code)
})

test_that("profile persistence is atomic, immutable and queryable", {
  connection <- open_workbench_database(":memory:")
  on.exit(DBI::dbDisconnect(connection, shutdown = TRUE), add = TRUE)
  initialise_workbench_database(connection, project_path("inst", "schema"))
  import_pronom_json(connection, project_path("data", "raw", "1.json"))
  source_path <- tempfile(fileext = ".xlsx")
  writeBin(charToRaw("workbook fixture"), source_path)
  parsed <- list(
    metadata = data.frame(profile_name = nl_profile_name, profile_version = "2024",
      publisher = "Nationaal Archief", publication_date = as.Date("2024-01-01"),
      source_name = basename(source_path), source_url = nl_profile_source_url),
    entries = data.frame(source_sheet = "Lijst Voorkeursformaten", source_row = 2L,
      category = "Audio", information_subtype = NA_character_, format_label = "WAVE",
      extension_label = "wav", version_label = NA_character_, preference_status = "preferred",
      source_status = "Voorkeur", notes = NA_character_, rationale = NA_character_,
      raw_source_data = "{}", mapping_status = "unmapped", stringsAsFactors = FALSE),
    mappings = data.frame(entry_source_row = 2L, puid = "fmt/1", raw_puid = "fmt/1",
      syntax_status = "valid", ordinal = 1L, stringsAsFactors = FALSE),
    rationales = empty_parser_table(profile_rationale_columns()),
    rationale_links = empty_parser_table(c(entry_source_row="integer", rationale_source_row="integer", link_method="character")),
    issues = empty_parser_table(parser_issue_columns()),
    summaries = parser_summary("profile_entry_count", "1 entry", 1L)
  )
  class(parsed) <- c("format_profile_import", "list")
  imported <- persist_profile_import(connection, parsed, source_path)
  expect_equal(nrow(list_format_profiles(connection)), 1L)
  overview <- get_profile_overview(connection, imported$profile_id)
  expect_equal(nrow(overview$entries), 1L)
  expect_equal(overview$entries$mapping_status, "mapped")
  statements <- get_puid_profile_statements(connection, "fmt/1")
  expect_equal(statements$preferred_status, "preferred")
  expect_error(persist_profile_import(connection, parsed, source_path), class = "format_policy_duplicate_snapshot")
  expect_equal(DBI::dbGetQuery(connection, "SELECT count(*) n FROM policy_profile")$n, 1)
})

test_that("missing workbook fails before persistence", {
  expect_error(parse_nl_profile_xlsx(tempfile(fileext = ".xlsx")), "file does not exist")
})
