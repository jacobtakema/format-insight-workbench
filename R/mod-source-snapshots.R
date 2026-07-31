source_snapshots_ui <- function(id) {
  namespace <- shiny::NS(id)
  shiny::tagList(
    bs4Dash::bs4Card(
      title = "Imported source snapshots",
      width = 12,
      shiny::uiOutput(namespace("empty_state")),
      shiny::tableOutput(namespace("snapshot_table"))
    ),
    bs4Dash::bs4Card(
      title = "Snapshot import details",
      width = 12,
      shiny::selectInput(
        namespace("selected_snapshot"), "Snapshot", choices = character()
      ),
      shiny::uiOutput(namespace("snapshot_metadata")),
      shiny::tableOutput(namespace("metric_table")),
      shiny::h4("Preserved import summaries"),
      shiny::uiOutput(namespace("summary_state")),
      shiny::tableOutput(namespace("summary_table")),
      shiny::h4("Import issues"),
      shiny::uiOutput(namespace("issue_state")),
      shiny::tableOutput(namespace("issue_table"))
    )
  )
}

source_snapshots_server <- function(id, connection, refresh) {
  shiny::moduleServer(id, function(input, output, session) {
    snapshots <- shiny::reactive({
      refresh()
      list_source_snapshots(connection)
    })

    shiny::observe({
      rows <- snapshots()
      choices <- if (nrow(rows) == 0L) character() else stats::setNames(
        rows$snapshot_id,
        sprintf("%s — %s", rows$source_filename, rows$source_type)
      )
      selected <- if (length(choices) == 0L) {
        character()
      } else if (input$selected_snapshot %in% unname(choices)) {
        input$selected_snapshot
      } else {
        unname(choices)[[1L]]
      }
      shiny::updateSelectInput(
        session, "selected_snapshot", choices = choices, selected = selected
      )
    })

    import_detail <- shiny::reactive({
      shiny::req(input$selected_snapshot)
      get_snapshot_import_detail(connection, input$selected_snapshot)
    })

    output$empty_state <- shiny::renderUI({
      if (nrow(snapshots()) == 0L) {
        shiny::div(
          class = "empty-state",
          "No source snapshots have been imported. Use the Import page to add an example."
        )
      }
    })

    output$snapshot_table <- shiny::renderTable({
      rows <- snapshots()
      shiny::req(nrow(rows) > 0L)
      names(rows) <- c(
        "Snapshot ID", "Source type", "Version", "Filename", "Source path",
        "Imported at", "Status", "Formats"
      )
      rows
    }, striped = TRUE, hover = TRUE, bordered = FALSE, spacing = "s")

    output$snapshot_metadata <- shiny::renderUI({
      metadata <- import_detail()$metadata
      shiny::req(nrow(metadata) == 1L)
      version <- metadata$source_version[[1L]]
      shiny::tagList(
        shiny::p(
          shiny::strong("Source type: "), metadata$source_type[[1L]],
          shiny::br(),
          shiny::strong("Version or commit: "),
          ifelse(is.na(version) || !nzchar(version), "Unavailable", version),
          shiny::br(),
          shiny::strong("Imported: "), metadata$imported_at[[1L]]
        )
      )
    })

    output$metric_table <- shiny::renderTable({
      rows <- import_detail()$metrics
      names(rows) <- c("Metric", "Value")
      rows
    }, striped = TRUE, hover = TRUE, bordered = FALSE, spacing = "s")

    output$summary_state <- shiny::renderUI({
      if (nrow(import_detail()$summaries) == 0L) {
        shiny::p(
          class = "text-muted",
          "No preserved-source summaries were recorded for this snapshot."
        )
      }
    })

    output$summary_table <- shiny::renderTable({
      rows <- import_detail()$summaries
      shiny::req(nrow(rows) > 0L)
      names(rows) <- c("Summary code", "Message", "Count")
      rows
    }, striped = TRUE, hover = TRUE, bordered = FALSE, spacing = "s")

    output$issue_state <- shiny::renderUI({
      if (nrow(import_detail()$issues) == 0L) {
        shiny::p(class = "text-muted", "No import issues were recorded for this snapshot.")
      }
    })

    output$issue_table <- shiny::renderTable({
      rows <- import_detail()$issues
      shiny::req(nrow(rows) > 0L)
      names(rows) <- c(
        "Severity", "Validation layer", "Source path or record",
        "Issue code", "Message"
      )
      rows
    }, striped = TRUE, hover = TRUE, bordered = FALSE, spacing = "s")
  })
}
