pronom_schema_cache <- new.env(parent = emptyenv())

default_pronom_schema_paths <- function(project_root = NULL) {
  if (is.null(project_root)) {
    configured_root <- workbench_root_override()
    project_root <- find_workbench_project_root(
      if (nzchar(configured_root)) configured_root else getwd()
    )
  }
  directory <- file.path(project_root, "inst", "extdata", "pronom")
  list(
    schema = file.path(directory, "format_schema.json"),
    compatibility = file.path(directory, "format_schema_compatibility.json")
  )
}

load_pronom_schema <- function(schema_path = NULL, compatibility_path = NULL) {
  defaults <- default_pronom_schema_paths()
  schema_path <- schema_path %||% defaults$schema
  compatibility_path <- compatibility_path %||% defaults$compatibility
  if (!file.exists(schema_path)) {
    stop_schema_error(sprintf("PRONOM JSON Schema does not exist: %s", schema_path))
  }
  if (!file.exists(compatibility_path)) {
    stop_schema_error(sprintf("PRONOM schema compatibility overlay does not exist: %s", compatibility_path))
  }
  schema_bytes <- readBin(schema_path, "raw", file.info(schema_path)$size)
  compatibility_bytes <- readBin(
    compatibility_path, "raw", file.info(compatibility_path)$size
  )
  schema_checksum <- digest::digest(schema_bytes, "sha256", serialize = FALSE)
  compatibility_checksum <- digest::digest(
    compatibility_bytes, "sha256", serialize = FALSE
  )
  cache_key <- paste(schema_checksum, compatibility_checksum, sep = ":")
  if (exists(cache_key, pronom_schema_cache, inherits = FALSE)) {
    return(get(cache_key, pronom_schema_cache, inherits = FALSE))
  }

  schema <- decode_schema_json(schema_path, "official schema")
  compatibility <- decode_schema_json(
    compatibility_path, "compatibility overlay"
  )
  dialect <- scalar_character(schema[["$schema"]])
  if (!identical(dialect, "http://json-schema.org/draft-07/schema#")) {
    stop_schema_error(sprintf(
      "Unsupported PRONOM JSON Schema dialect: %s",
      ifelse(is.na(dialect), "missing", dialect)
    ))
  }
  expected_checksum <- tolower(scalar_character(
    compatibility$officialSchemaSha256
  ))
  overlay_applies <- identical(expected_checksum, schema_checksum)
  effective_schema <- if (overlay_applies) {
    apply_schema_compatibility(schema, compatibility$operations)
  } else {
    schema
  }
  effective_json <- jsonlite::toJSON(
    effective_schema, auto_unbox = TRUE, null = "null", pretty = FALSE
  )
  official_json <- rawToChar(schema_bytes)
  official_validator <- tryCatch(
    jsonvalidate::json_validator(
      official_json, engine = "ajv", strict = TRUE
    ),
    error = function(error) {
      stop_schema_error(sprintf(
        "Could not compile the official PRONOM JSON Schema: %s",
        conditionMessage(error)
      ))
    }
  )
  validator <- tryCatch(
    jsonvalidate::json_validator(effective_json, engine = "ajv", strict = TRUE),
    error = function(error) {
      stop_schema_error(sprintf(
        "Could not compile the effective PRONOM JSON Schema: %s",
        conditionMessage(error)
      ))
    }
  )
  bundle <- list(
    schema_identifier = "nationalarchives/pronom/format_schema.json",
    schema_dialect = dialect,
    schema_checksum_sha256 = schema_checksum,
    compatibility_id = if (overlay_applies) {
      scalar_character(compatibility$compatibilityId)
    } else {
      NA_character_
    },
    compatibility_checksum_sha256 = if (overlay_applies) {
      compatibility_checksum
    } else {
      NA_character_
    },
    effective_schema_checksum_sha256 = digest::digest(
      effective_json, "sha256", serialize = FALSE
    ),
    raw_schema = schema_bytes,
    raw_compatibility = if (overlay_applies) compatibility_bytes else raw(),
    validate_official = official_validator,
    validate = validator
  )
  class(bundle) <- c("pronom_schema_bundle", "list")
  assign(cache_key, bundle, pronom_schema_cache)
  bundle
}

pronom_schema_audit_summaries <- function(json_text, schema_bundle,
                                          compatibility_violation_count) {
  official_result <- schema_bundle$validate_official(
    json_text, verbose = TRUE, greedy = TRUE, error = FALSE
  )
  official_errors <- attr(official_result, "errors")
  official_count <- if (isTRUE(official_result) || is.null(official_errors)) {
    0L
  } else {
    nrow(official_errors)
  }
  rbind(
    parser_summary(
      "pronom_strict_schema_violations",
      "Violations reported by the unmodified official PRONOM JSON Schema.",
      official_count
    ),
    parser_summary(
      "pronom_compatibility_schema_violations",
      "Violations reported after applying the checksum-bound compatibility overlay.",
      compatibility_violation_count
    ),
    parser_summary(
      "pronom_compatibility_schema_validated_records",
      "Records validated against the effective PRONOM compatibility schema.",
      1L
    )
  )
}

decode_schema_json <- function(path, label) {
  tryCatch(
    jsonlite::fromJSON(path, simplifyVector = FALSE),
    error = function(error) {
      stop_schema_error(sprintf(
        "Could not decode the PRONOM %s: %s", label, conditionMessage(error)
      ))
    }
  )
}

apply_schema_compatibility <- function(schema, operations) {
  if (!is.list(operations)) {
    stop_schema_error("The PRONOM compatibility overlay has no operations array.")
  }
  for (operation in operations) {
    action <- scalar_character(operation$op)
    path <- scalar_character(operation$path)
    if (!action %in% c("remove", "replace") || is.na(path)) {
      stop_schema_error("The PRONOM compatibility overlay contains an unsupported operation.")
    }
    schema <- modify_json_pointer(
      schema, json_pointer_parts(path), action, operation$value
    )
  }
  schema
}

json_pointer_parts <- function(path) {
  if (!startsWith(path, "/")) {
    stop_schema_error(sprintf("Invalid JSON Pointer in compatibility overlay: %s", path))
  }
  parts <- strsplit(sub("^/", "", path), "/", fixed = TRUE)[[1L]]
  gsub("~1", "/", gsub("~0", "~", parts, fixed = TRUE), fixed = TRUE)
}

modify_json_pointer <- function(value, parts, action, replacement = NULL) {
  key <- parts[[1L]]
  if (is.null(value[[key]])) {
    stop_schema_error(sprintf(
      "Compatibility overlay path does not exist: %s", paste(parts, collapse = "/")
    ))
  }
  if (length(parts) == 1L) {
    if (identical(action, "remove")) {
      value[[key]] <- NULL
    } else {
      value[key] <- list(replacement)
    }
    return(value)
  }
  value[[key]] <- modify_json_pointer(
    value[[key]], parts[-1L], action, replacement
  )
  value
}

validate_pronom_structure <- function(json_text, schema_bundle, locator) {
  result <- schema_bundle$validate(
    json_text, verbose = TRUE, greedy = TRUE, error = FALSE
  )
  errors <- attr(result, "errors")
  if (isTRUE(result) || is.null(errors) || nrow(errors) == 0L) {
    return(empty_parser_table(c(
      severity = "character", issue_code = "character",
      record_locator = "character", message = "character",
      raw_value = "character", validation_layer = "character"
    )))
  }
  rows <- lapply(seq_len(nrow(errors)), function(index) {
    error <- errors[index, , drop = FALSE]
    pointer <- error$instancePath[[1L]]
    missing <- if ("params" %in% names(errors) &&
                   "missingProperty" %in% names(errors$params)) {
      errors$params$missingProperty[[index]]
    } else {
      NA_character_
    }
    if (!is.na(missing) && nzchar(missing)) {
      pointer <- paste0(pointer, "/", missing)
    }
    parser_issue(
      "error",
      paste0("schema_", gsub("[^a-z0-9]+", "_", tolower(error$keyword[[1L]]))),
      if (nzchar(pointer)) pointer else locator,
      sprintf(
        "PRONOM JSON Schema validation failed at '%s': %s.",
        if (nzchar(pointer)) pointer else "/",
        error$message[[1L]]
      ),
      validation_layer = "structural"
    )
  })
  do.call(rbind, rows)
}

pronom_schema_metadata <- function(bundle) {
  data.frame(
    validation_schema_identifier = bundle$schema_identifier,
    validation_schema_dialect = bundle$schema_dialect,
    validation_schema_checksum_sha256 = bundle$schema_checksum_sha256,
    validation_schema_compatibility_id = bundle$compatibility_id,
    validation_schema_effective_checksum_sha256 =
      bundle$effective_schema_checksum_sha256,
    stringsAsFactors = FALSE
  )
}

stop_schema_error <- function(message) {
  condition <- structure(
    list(message = message, call = NULL),
    class = c("format_policy_schema_error", "error", "condition")
  )
  stop(condition)
}
