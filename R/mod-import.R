example_imports <- function(project_root) {
  data.frame(
    key = c(
      "pronom_fmt_1", "pronom_fmt_104", "droid_v1", "droid_v65", "droid_v124"
    ),
    label = c(
      "PRONOM fmt/1 — Broadcast WAVE",
      "PRONOM fmt/104 — Macromedia Flash",
      "DROID binary signature file — version 1 (snapshot only)",
      "DROID binary signature file — version 65",
      "DROID binary signature file — version 124"
    ),
    source_type = c(
      "pronom_json", "pronom_json",
      "droid_binary_signature", "droid_binary_signature",
      "droid_binary_signature"
    ),
    source_filename = c(
      "1.json", "104.json", "DROID_SignatureFile_V1.xml",
      "DROID_SignatureFile_V65.xml", "DROID_SignatureFile_V124.xml"
    ),
    source_relative_path = c(
      "data/raw/1.json",
      "data/raw/104.json",
      "data/raw/DROID_SignatureFile_V1.xml",
      "data/raw/DROID_SignatureFile_V65.xml",
      "data/raw/DROID_SignatureFile_V124.xml"
    ),
    path = file.path(
      project_root,
      "data",
      "raw",
      c(
        "1.json", "104.json", "DROID_SignatureFile_V1.xml",
        "DROID_SignatureFile_V65.xml", "DROID_SignatureFile_V124.xml"
      )
    ),
    stringsAsFactors = FALSE
  )
}

import_page_ui <- function(id, examples) {
  namespace <- shiny::NS(id)
  choices <- stats::setNames(examples$key, examples$label)
  bs4Dash::bs4Card(
    title = "Import example data",
    width = 8,
    shiny::p(
      "Select one of the source files supplied with the prototype.",
      "Each successful import creates an immutable source snapshot."
    ),
    shiny::h4("Automatic PRONOM repository import"),
    shiny::textInput(
      namespace("repository_url"),
      "PRONOM GitHub repository",
      value = "https://github.com/nationalarchives/pronom"
    ),
    shiny::textInput(namespace("repository_reference"), "Branch, tag or commit", value = "develop"),
    shiny::actionButton(namespace("resolve_repository"), "Resolve source"),
    shiny::uiOutput(namespace("resolved_repository")),
    shiny::actionButton(
      namespace("import_repository"),
      "Import resolved repository",
      icon = shiny::icon("download"),
      class = "btn-primary"
    ),
    shiny::tags$hr(),
    shiny::h4("Local examples"),
    shiny::selectInput(namespace("example"), "Example source", choices = choices),
    shiny::actionButton(
      namespace("import"),
      "Import selected source",
      icon = shiny::icon("file-import"),
      class = "btn-primary"
    ),
    shiny::tags$hr(),
    shiny::fileInput(
      namespace("pronom_files"),
      "PRONOM JSON files",
      multiple = TRUE,
      accept = c(".json", "application/json")
    ),
    shiny::actionButton(
      namespace("import_pronom_files"),
      "Import selected PRONOM files",
      icon = shiny::icon("file-import")
    ),
    shiny::tags$hr(),
    shiny::fileInput(
      namespace("droid_file"),
      "DROID binary-signature XML file",
      multiple = FALSE,
      accept = c(".xml", "application/xml", "text/xml")
    ),
    shiny::actionButton(
      namespace("import_droid_file"),
      "Import selected DROID file",
      icon = shiny::icon("file-import")
    ),
    shiny::uiOutput(namespace("status"))
  )
}

import_page_server <- function(id, connection, examples, refresh,
                               repository_resolver = resolve_github_reference,
                               repository_downloader = download_github_archive) {
  shiny::moduleServer(id, function(input, output, session) {
    status <- shiny::reactiveVal(NULL)
    resolved_repository <- shiny::reactiveVal(NULL)

    shiny::observeEvent(input$resolve_repository, {
      resolution <- tryCatch(
        repository_resolver(input$repository_url, input$repository_reference),
        error = identity
      )
      if (inherits(resolution, "error")) {
        resolved_repository(NULL)
        status(list(kind = "danger", messages = conditionMessage(resolution)))
      } else {
        resolved_repository(resolution)
        status(NULL)
      }
    })

    output$resolved_repository <- shiny::renderUI({
      value <- resolved_repository()
      if (is.null(value)) return(NULL)
      shiny::div(
        class = "alert alert-info",
        shiny::strong("Resolved commit: "),
        shiny::code(value$resolved_commit),
        shiny::br(),
        sprintf("Commit date: %s", value$commit_date)
      )
    })

    shiny::observeEvent(input$import_repository, {
      resolution <- resolved_repository()
      shiny::req(!is.null(resolution))
      result <- tryCatch({
        imported <- shiny::withProgress(
          message = "Importing PRONOM repository",
          value = 0,
          {
            callback <- function(update) {
              value <- if (update$total > 0L) update$current / update$total else 0.1
              shiny::setProgress(value = min(value, 0.95), detail = update$message)
            }
            import_pronom_repository(
              connection,
              input$repository_url,
              input$repository_reference,
              resolved = resolution,
              downloader = repository_downloader,
              progress = callback
            )
          }
        )
        refresh(refresh() + 1L)
        summary <- imported$summary
        list(kind = if (summary$rejected_count > 0L) "warning" else "success", messages = c(
          sprintf("Resolved commit: %s", imported$resolved$resolved_commit),
          sprintf(
            "Discovered %d JSON files: %d parsed, %d rejected; %d fmt and %d x-fmt.",
            summary$discovered_count, summary$parsed_count, summary$rejected_count,
            summary$fmt_count, summary$x_fmt_count
          ),
          sprintf(
            "Warnings: %d; errors: %d. Preserved but non-normalised fields are listed in the snapshot summaries.",
            summary$warning_count, summary$error_count
          )
        ))
      }, format_policy_duplicate_snapshot = function(error) {
        list(kind = "warning", messages = conditionMessage(error))
      }, error = function(error) {
        list(kind = "danger", messages = conditionMessage(error))
      })
      status(result)
    })

    shiny::observeEvent(input$import, {
      selected <- examples[examples$key == input$example, , drop = FALSE]
      shiny::req(nrow(selected) == 1L)
      status(list(kind = "working", messages = "Importing source…"))

      result <- tryCatch({
        snapshot_id <- import_source_record(connection, selected)
        refresh(refresh() + 1L)
        list(
          kind = "success",
          messages = import_success_messages(connection, selected$source_filename, snapshot_id)
        )
      }, format_policy_duplicate_snapshot = function(error) {
        list(
          kind = "warning",
          messages = sprintf(
            "This source is already imported as snapshot %s.",
            error$existing_snapshot_id
          )
        )
      }, error = function(error) {
        list(kind = "danger", messages = conditionMessage(error))
      })
      status(result)
    })

    shiny::observeEvent(input$import_pronom_files, {
      shiny::req(!is.null(input$pronom_files), nrow(input$pronom_files) > 0L)
      records <- uploaded_source_records(input$pronom_files, "pronom_json")
      result <- import_source_records(connection, records)
      if (result$success_count > 0L) refresh(refresh() + 1L)
      status(result$status)
    })

    shiny::observeEvent(input$import_droid_file, {
      shiny::req(!is.null(input$droid_file), nrow(input$droid_file) == 1L)
      records <- uploaded_source_records(input$droid_file, "droid_binary_signature")
      result <- import_source_records(connection, records)
      if (result$success_count > 0L) refresh(refresh() + 1L)
      status(result$status)
    })

    output$status <- shiny::renderUI({
      value <- status()
      if (is.null(value)) return(NULL)
      class <- switch(
        value$kind,
        success = "alert alert-success",
        warning = "alert alert-warning",
        danger = "alert alert-danger",
        "alert alert-info"
      )
      shiny::div(
        class = class,
        role = "status",
        if (length(value$messages) == 1L) {
          value$messages
        } else {
          shiny::tags$ul(lapply(value$messages, shiny::tags$li))
        }
      )
    })
  })
}

uploaded_source_records <- function(upload, source_type) {
  data.frame(
    source_type = rep(source_type, nrow(upload)),
    source_filename = basename(upload$name),
    source_relative_path = gsub("\\\\", "/", upload$name),
    path = upload$datapath,
    stringsAsFactors = FALSE
  )
}

import_source_record <- function(connection, record) {
  if (record$source_type[[1L]] == "pronom_json") {
    import_pronom_json(
      connection,
      record$path[[1L]],
      source_filename = record$source_filename[[1L]],
      source_relative_path = record$source_relative_path[[1L]]
    )
  } else if (record$source_type[[1L]] == "droid_binary_signature") {
    import_droid_xml(
      connection,
      record$path[[1L]],
      source_filename = record$source_filename[[1L]],
      source_relative_path = record$source_relative_path[[1L]]
    )
  } else {
    stop(sprintf("Unsupported source type: %s", record$source_type[[1L]]), call. = FALSE)
  }
}

import_success_messages <- function(connection, filename, snapshot_id) {
  summaries <- list_import_summaries(connection, snapshot_id)
  messages <- sprintf("%s imported as snapshot %s.", filename, snapshot_id)
  if (nrow(summaries) > 0L) {
    messages <- c(
      messages,
      sprintf("%s: %s", filename, summaries$message)
    )
  }
  messages
}

import_source_records <- function(connection, records) {
  messages <- character()
  success_count <- 0L
  has_error <- FALSE
  has_duplicate <- FALSE
  for (index in seq_len(nrow(records))) {
    record <- records[index, , drop = FALSE]
    result <- tryCatch({
      snapshot_id <- import_source_record(connection, record)
      success_count <- success_count + 1L
      import_success_messages(connection, record$source_filename[[1L]], snapshot_id)
    }, format_policy_duplicate_snapshot = function(error) {
      has_duplicate <<- TRUE
      sprintf(
        "%s is already imported as snapshot %s.",
        record$source_filename[[1L]], error$existing_snapshot_id
      )
    }, error = function(error) {
      has_error <<- TRUE
      sprintf("%s was not imported: %s", record$source_filename[[1L]], conditionMessage(error))
    })
    messages <- c(messages, result)
  }
  kind <- if (has_error) "danger" else if (has_duplicate) "warning" else "success"
  list(
    success_count = success_count,
    status = list(kind = kind, messages = messages)
  )
}
