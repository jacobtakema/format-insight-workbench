test_that("valid PRONOM JSON is normalised", {
  result <- parse_pronom_json(project_path("data", "raw", "104.json"))

  expect_s3_class(result, "format_policy_import")
  expect_equal(result$formats$puid, "fmt/104")
  expect_equal(result$formats$source_record_id, "646")
  expect_equal(result$formats$format_name, "Macromedia Flash")
  expect_equal(result$extensions$extension, "swf")
  expect_true("application/x-shockwave-flash" %in% result$identifiers$identifier_value)
  expect_equal(result$signatures$source_signature_id, "42")
  expect_true("has_priority_over" %in% result$relationships$relationship_type)
  expect_equal(nrow(result$issues), 0L)
  expect_true("pronom_descriptive_metadata_preserved" %in% result$summaries$summary_code)
  expect_true("pronom_signature_details_preserved" %in% result$summaries$summary_code)
  strict <- result$summaries[
    result$summaries$summary_code == "pronom_strict_schema_violations",
    , drop = FALSE
  ]
  compatibility <- result$summaries[
    result$summaries$summary_code ==
      "pronom_compatibility_schema_violations",
    , drop = FALSE
  ]
  expect_equal(strict$item_count, 7L)
  expect_equal(compatibility$item_count, 0L)
})

test_that("official schema reports structurally missing PRONOM fields", {
  path <- tempfile(fileext = ".json")
  writeLines('{"fileFormatID": 99, "version": null}', path, useBytes = TRUE)
  on.exit(unlink(path), add = TRUE)

  result <- parse_pronom_json(path)

  expect_equal(nrow(result$formats), 0L)
  expect_true(all(result$issues$issue_code == "schema_required"))
  expect_true(all(result$issues$validation_layer == "structural"))
  expect_true(any(grepl("/formatName", result$issues$record_locator, fixed = TRUE)))
  expect_true(any(grepl("/internalSignatures", result$issues$record_locator, fixed = TRUE)))
})

test_that("malformed PRONOM JSON raises a parser error", {
  path <- tempfile(fileext = ".json")
  writeLines('{"fileFormatID":', path, useBytes = TRUE)
  on.exit(unlink(path), add = TRUE)

  expect_error(parse_pronom_json(path), class = "format_policy_parse_error")
})

test_that("the second supplied PRONOM structure is supported", {
  result <- parse_pronom_json(project_path("data", "raw", "1.json"))

  expect_equal(result$formats$puid, "fmt/1")
  expect_equal(result$formats$format_name, "Broadcast WAVE")
  expect_true(all(c("MIME", "PUID") %in% result$identifiers$identifier_type))
  expect_equal(result$extensions$extension, "wav")
  expect_equal(nrow(result$relationships), 7L)
})

test_that("empty, duplicate, conflicting and invalid PUID identifiers are reported", {
  make_record <- function(identifiers) {
    path <- tempfile(fileext = ".json")
    jsonlite::write_json(
      list(
        fileFormatID = 1, formatName = "Test", identifiers = identifiers,
        internalSignatures = list()
      ),
      path, auto_unbox = TRUE
    )
    path
  }

  empty <- make_record(list())
  duplicate <- make_record(list(
    list(identifierType = "PUID", identifierText = "fmt/1"),
    list(identifierType = "PUID", identifierText = "fmt/1")
  ))
  conflicting <- make_record(list(
    list(identifierType = "PUID", identifierText = "fmt/1"),
    list(identifierType = "PUID", identifierText = "x-fmt/1")
  ))
  invalid <- make_record(list(
    list(identifierType = "PUID", identifierText = "format/1")
  ))
  on.exit(unlink(c(empty, duplicate, conflicting, invalid)), add = TRUE)

  expect_true("empty_identifiers" %in% parse_pronom_json(empty)$issues$issue_code)
  expect_true("duplicate_puid_identifier" %in% parse_pronom_json(duplicate)$issues$issue_code)
  expect_true("conflicting_puid_identifiers" %in% parse_pronom_json(conflicting)$issues$issue_code)
  expect_true("invalid_puid" %in% parse_pronom_json(invalid)$issues$issue_code)
})

test_that("malformed PRONOM array members are reported before persistence", {
  path <- tempfile(fileext = ".json")
  writeLines(
    '{"fileFormatID":1,"formatName":"Test","identifiers":[1],"relationships":[false],"internalSignatures":[]}',
    path,
    useBytes = TRUE
  )
  on.exit(unlink(path), add = TRUE)

  result <- parse_pronom_json(path)
  expect_true(all(result$issues$issue_code == "schema_type"))
  expect_true(all(result$issues$validation_layer == "structural"))
  expect_true(any(grepl("/identifiers/0", result$issues$record_locator, fixed = TRUE)))
  expect_true(any(grepl("/relationships/0", result$issues$record_locator, fixed = TRUE)))
})

test_that("schema compatibility overlay is checksum-bound and preserves official bytes", {
  bundle <- load_pronom_schema()
  official <- readBin(
    project_path("inst", "extdata", "pronom", "format_schema.json"),
    "raw",
    file.info(project_path("inst", "extdata", "pronom", "format_schema.json"))$size
  )

  expect_identical(bundle$raw_schema, official)
  expect_equal(bundle$schema_dialect, "http://json-schema.org/draft-07/schema#")
  expect_equal(bundle$compatibility_id, "pronom-develop-2026-07.2")
  expect_false(identical(
    bundle$schema_checksum_sha256,
    bundle$effective_schema_checksum_sha256
  ))
})

test_that("new optional schema properties do not require parser changes", {
  record <- jsonlite::fromJSON(
    project_path("data", "raw", "104.json"), simplifyVector = FALSE
  )
  record$newOptionalSourceField <- "preserved"
  path <- tempfile(fileext = ".json")
  jsonlite::write_json(record, path, auto_unbox = TRUE, null = "null")
  on.exit(unlink(path), add = TRUE)

  result <- parse_pronom_json(path)

  expect_equal(result$formats$puid, "fmt/104")
  expect_true(
    "pronom_descriptive_metadata_preserved" %in% result$summaries$summary_code
  )
})

test_that("invalid external-signature children warn without rejecting the parent", {
  path <- tempfile(fileext = ".json")
  jsonlite::write_json(
    list(
      fileFormatID = 924,
      formatName = "MPEG-4 Media File",
      identifiers = list(
        list(identifierText = "fmt/199", identifierType = "PUID")
      ),
      internalSignatures = list(),
      externalSignatures = list(
        list(externalSignature = "mp4", signatureType = "File extension"),
        list(externalSignature = NULL, signatureType = "File extension"),
        list(externalSignature = "", signatureType = "File extension"),
        list(externalSignature = "   ", signatureType = "File extension")
      )
    ),
    path,
    auto_unbox = TRUE,
    null = "null"
  )
  on.exit(unlink(path), add = TRUE)

  result <- parse_pronom_json(path)
  issues <- result$issues[
    result$issues$issue_code == "empty_external_signature", , drop = FALSE
  ]

  expect_equal(result$formats$puid, "fmt/199")
  expect_equal(result$extensions$extension, "mp4")
  expect_equal(nrow(issues), 3L)
  expect_true(all(issues$severity == "warning"))
  expect_true(all(issues$validation_layer == "semantic"))
  expect_setequal(
    issues$record_locator,
    c(
      "924 /externalSignatures/1",
      "924 /externalSignatures/2",
      "924 /externalSignatures/3"
    )
  )
})
