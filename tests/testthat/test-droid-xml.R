test_that("valid DROID XML is normalised", {
  result <- parse_droid_xml(project_path("data", "raw", "DROID_SignatureFile_V124.xml"))

  expect_s3_class(result, "format_policy_import")
  expect_equal(result$metadata$source_version, "124")
  expect_equal(result$metadata$droid_support_mode, "puid_comparison")
  expect_equal(result$metadata$droid_xml_dialect, "pronom_signature_namespace")
  expect_equal(result$metadata$droid_valid_puid_count, 2557L)
  expect_equal(nrow(result$formats), 2557L)
  flash <- result$formats[result$formats$puid == "fmt/104", ]
  expect_equal(flash$source_record_id, "646")
  expect_equal(flash$format_name, "Macromedia Flash")
  expect_true(any(result$extensions$puid == "fmt/104" & result$extensions$extension == "swf"))
  expect_true(any(result$signatures$puid == "fmt/104" & result$signatures$source_signature_id == "42"))
  expect_equal(nrow(result$issues), 0L)
})

test_that("malformed DROID XML raises a parser error", {
  path <- tempfile(fileext = ".xml")
  writeLines('<FFSignatureFile><FileFormat>', path, useBytes = TRUE)
  on.exit(unlink(path), add = TRUE)

  expect_error(parse_droid_xml(path), class = "format_policy_parse_error")
})

test_that("missing DROID fields are retained and reported", {
  path <- tempfile(fileext = ".xml")
  writeLines(c(
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<FFSignatureFile Version="1" xmlns="http://www.nationalarchives.gov.uk/pronom/SignatureFile">',
    '<FileFormatCollection><FileFormat ID="7" /></FileFormatCollection>',
    '</FFSignatureFile>'
  ), path, useBytes = TRUE)
  on.exit(unlink(path), add = TRUE)

  result <- parse_droid_xml(path)

  expect_equal(nrow(result$formats), 0L)
  expect_equal(nrow(result$source_records), 1L)
  expect_setequal(result$issues$issue_code, c("missing_puids", "missing_name"))
})

write_droid_fixture <- function(file_formats = "", signatures = "") {
  path <- tempfile(fileext = ".xml")
  writeLines(c(
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<FFSignatureFile Version="1" DateCreated="2026-01-01T00:00:00" xmlns="http://www.nationalarchives.gov.uk/pronom/SignatureFile">',
    sprintf("<InternalSignatureCollection>%s</InternalSignatureCollection>", signatures),
    sprintf("<FileFormatCollection>%s</FileFormatCollection>", file_formats),
    "</FFSignatureFile>"
  ), path, useBytes = TRUE)
  path
}

test_that("DROID multiple identifiers, extensions, signatures and priorities are supported", {
  path <- write_droid_fixture(
    paste0(
      '<FileFormat ID="1" PUID="fmt/1" Name="One" MIMEType="text/plain, application/test">',
      "<InternalSignatureID>10</InternalSignatureID>",
      "<Extension>TXT</Extension><Extension>dat</Extension>",
      "<HasPriorityOverFileFormatID>2</HasPriorityOverFileFormatID>",
      "</FileFormat>",
      '<FileFormat ID="2" PUID="x-fmt/2" Name="Two" />'
    ),
    '<InternalSignature ID="10"><ByteSequence Reference="BOFoffset" /></InternalSignature>'
  )
  on.exit(unlink(path), add = TRUE)

  result <- parse_droid_xml(path)
  expect_equal(nrow(result$issues), 0L)
  expect_setequal(
    result$identifiers$identifier_value[result$identifiers$identifier_type == "MIME"],
    c("text/plain", "application/test")
  )
  expect_setequal(result$extensions$extension, c("txt", "dat"))
  expect_equal(result$signatures$source_signature_id, "10")
  expect_equal(result$relationships$object_source_record_id, "2")
  expect_true("droid_signature_definitions_preserved" %in% result$summaries$summary_code)
})

test_that("DROID zero formats and unresolved references are reported", {
  empty <- write_droid_fixture()
  unresolved <- write_droid_fixture(paste0(
    '<FileFormat ID="1" PUID="fmt/1" Name="One">',
    "<InternalSignatureID>999</InternalSignatureID>",
    "<HasPriorityOverFileFormatID>999</HasPriorityOverFileFormatID>",
    "</FileFormat>"
  ))
  on.exit(unlink(c(empty, unresolved)), add = TRUE)

  expect_true("zero_formats" %in% parse_droid_xml(empty)$issues$issue_code)
  unresolved_issues <- parse_droid_xml(unresolved)$issues$issue_code
  expect_true("unresolved_internal_signature_reference" %in% unresolved_issues)
  expect_true("unresolved_priority_target" %in% unresolved_issues)
})

test_that("invalid DROID PUIDs and container files are rejected", {
  invalid <- write_droid_fixture('<FileFormat ID="1" PUID="bad/1" Name="One" />')
  on.exit(unlink(invalid), add = TRUE)

  result <- parse_droid_xml(invalid)
  expect_equal(result$metadata$droid_support_mode, "snapshot_only")
  expect_true("invalid_puids" %in% result$issues$issue_code)
  expect_error(
    parse_droid_xml(project_path("data", "raw", "container-signature-20260119.xml")),
    class = "format_policy_parse_error"
  )
})

test_that("DROID V1 is recognised as a namespace-less snapshot-only release", {
  result <- parse_droid_xml(
    project_path("data", "raw", "DROID_SignatureFile_V1.xml")
  )

  expect_equal(result$metadata$droid_xml_dialect, "historical_namespace_less")
  expect_equal(result$metadata$droid_support_mode, "snapshot_only")
  expect_equal(result$metadata$droid_format_count, 541L)
  expect_equal(result$metadata$droid_valid_puid_count, 0L)
  expect_equal(result$metadata$droid_placeholder_puid_count, 134L)
  expect_equal(result$metadata$droid_missing_puid_count, 407L)
  expect_equal(result$metadata$droid_invalid_puid_count, 0L)
  expect_equal(nrow(result$formats), 0L)
  expect_equal(nrow(result$source_records), 541L)
  expect_false(any(result$issues$severity == "error"))
})

test_that("partial historical releases normalise only explicit valid PUID records", {
  path <- tempfile(fileext = ".xml")
  writeLines(c(
    '<FFSignatureFile Version="5">',
    '<InternalSignatureCollection />',
    '<FileFormatCollection>',
    '<FileFormat ID="1" PUID="fmt/1" Name="Resolved"><Extension>one</Extension></FileFormat>',
    '<FileFormat ID="2" PUID="Not yet assigned" Name="Placeholder"><Extension>two</Extension></FileFormat>',
    '<FileFormat ID="3" Name="Missing"><Extension>three</Extension></FileFormat>',
    '<FileFormat ID="4" PUID="bad/4" Name="Invalid"><Extension>four</Extension></FileFormat>',
    '</FileFormatCollection></FFSignatureFile>'
  ), path, useBytes = TRUE)
  on.exit(unlink(path), add = TRUE)

  result <- parse_droid_xml(path)

  expect_equal(result$metadata$droid_support_mode, "partial_historical")
  expect_equal(result$metadata$droid_valid_puid_count, 1L)
  expect_equal(result$metadata$droid_placeholder_puid_count, 1L)
  expect_equal(result$metadata$droid_missing_puid_count, 1L)
  expect_equal(result$metadata$droid_invalid_puid_count, 1L)
  expect_equal(result$formats$puid, "fmt/1")
  expect_equal(result$extensions$extension, "one")
  expect_equal(nrow(result$source_records), 3L)
  expect_false(any(result$issues$severity == "error"))
})

test_that("DROID V65 has complete valid PUID coverage", {
  result <- parse_droid_xml(
    project_path("data", "raw", "DROID_SignatureFile_V65.xml")
  )

  expect_equal(result$metadata$droid_support_mode, "puid_comparison")
  expect_equal(result$metadata$droid_valid_puid_count, 934L)
  expect_equal(nrow(result$formats), 934L)
  expect_equal(nrow(result$source_records), 0L)
  expect_setequal(
    result$issues$issue_code[result$issues$severity == "warning"],
    c("empty_extensions", "duplicate_extensions")
  )
  empty_summary <- result$summaries[
    result$summaries$summary_code == "droid_empty_extension_count", ,
    drop = FALSE
  ]
  expect_equal(empty_summary$item_count, 2L)
  duplicate_summary <- result$summaries[
    result$summaries$summary_code == "droid_duplicate_extension_count", ,
    drop = FALSE
  ]
  expect_equal(duplicate_summary$item_count, 1L)
  expect_equal(
    sum(result$extensions$source_record_id == "784" &
        result$extensions$extension == "wav"),
    1L
  )
})

test_that("unknown non-empty DROID namespaces remain unsupported", {
  path <- tempfile(fileext = ".xml")
  writeLines(
    '<FFSignatureFile xmlns="https://example.invalid/droid"><FileFormatCollection /></FFSignatureFile>',
    path,
    useBytes = TRUE
  )
  on.exit(unlink(path), add = TRUE)

  expect_error(parse_droid_xml(path), class = "format_policy_parse_error")
})
