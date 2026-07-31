format_explorer_ui <- function(id) {
  namespace <- shiny::NS(id)
  shiny::tagList(
    bs4Dash::bs4Card(
      title = "Active source context",
      width = 12,
      shiny::fluidRow(
        shiny::column(
          6,
          shiny::selectInput(
            namespace("pronom_snapshot"), "PRONOM repository snapshot",
            choices = character()
          )
        ),
        shiny::column(
          6,
          shiny::selectInput(
            namespace("droid_snapshot"), "DROID binary-signature snapshot",
            choices = character()
          )
        )
      ),
      shiny::p(
        class = "text-muted",
        "Snapshots are selected independently; matching dates or versions are not assumed."
      )
    ),
    bs4Dash::bs4Card(
      title = "Formats",
      width = 12,
      shiny::textInput(
        namespace("search"), "Search formats",
        placeholder = "PUID, name, version, MIME type or extension"
      ),
      shiny::fluidRow(
        shiny::column(
          4,
          shiny::selectInput(
            namespace("coverage"), "Source coverage",
            choices = c(
              "All formats" = "all",
              "Present in both sources" = "both",
              "PRONOM only" = "pronom_only",
              "DROID only" = "droid_only"
            )
          )
        ),
        shiny::column(
          8,
          shiny::checkboxGroupInput(
            namespace("missing_filters"), "Additional filters",
            choices = c(
              "Missing MIME type" = "missing_mime",
              "Missing extension" = "missing_extension",
              "No DROID internal-signature reference" = "no_droid_signature"
            ),
            inline = TRUE
          )
        )
      ),
      shiny::uiOutput(namespace("result_summary")),
      shiny::uiOutput(namespace("empty_state")),
      shiny::tableOutput(namespace("format_table")),
      shiny::selectInput(
        namespace("selected_puid"), "Inspect PUID", choices = character()
      )
    ),
    shiny::uiOutput(namespace("details"))
  )
}

format_explorer_server <- function(id, connection, refresh) {
  shiny::moduleServer(id, function(input, output, session) {
    pronom_snapshots <- shiny::reactive({
      refresh()
      list_source_snapshot_choices(connection, "pronom")
    })
    droid_snapshots <- shiny::reactive({
      refresh()
      list_source_snapshot_choices(connection, "droid")
    })

    shiny::observe({
      update_snapshot_selection(
        session, "pronom_snapshot", pronom_snapshots(), input$pronom_snapshot
      )
      update_snapshot_selection(
        session, "droid_snapshot", droid_snapshots(), input$droid_snapshot
      )
    })

    formats <- shiny::reactive({
      list_integrated_formats(
        connection, input$pronom_snapshot, input$droid_snapshot
      )
    })

    filtered_formats <- shiny::reactive({
      selected <- input$missing_filters %||% character()
      filter_integrated_formats(
        formats(), input$search, input$coverage,
        missing_mime = "missing_mime" %in% selected,
        missing_extension = "missing_extension" %in% selected,
        no_droid_signature = "no_droid_signature" %in% selected
      )
    })

    shiny::observe({
      choices <- filtered_formats()$puid
      selected <- if (length(choices) == 0L) {
        character()
      } else if (input$selected_puid %in% choices) {
        input$selected_puid
      } else {
        choices[[1L]]
      }
      shiny::updateSelectInput(
        session, "selected_puid", choices = choices, selected = selected
      )
    })

    output$result_summary <- shiny::renderUI({
      rows <- formats()
      if (nrow(rows) > 0L) {
        both <- sum(rows$present_in_pronom & rows$present_in_droid)
        pronom_only <- sum(rows$present_in_pronom & !rows$present_in_droid)
        droid_only <- sum(!rows$present_in_pronom & rows$present_in_droid)
        shiny::p(
          class = "text-muted",
          sprintf(
            paste0(
              "Showing %s of %s unique PUIDs. Coverage: %s in both, ",
              "%s PRONOM only, %s DROID only."
            ),
            format(nrow(filtered_formats()), big.mark = ","),
            format(nrow(rows), big.mark = ","),
            format(both, big.mark = ","),
            format(pronom_only, big.mark = ","),
            format(droid_only, big.mark = ",")
          )
        )
      }
    })

    output$empty_state <- shiny::renderUI({
      if (nrow(pronom_snapshots()) == 0L && nrow(droid_snapshots()) == 0L) {
        shiny::div(
          class = "empty-state",
          "No source snapshots are available. Import source data first."
        )
      } else if (nrow(formats()) == 0L) {
        shiny::div(
          class = "empty-state",
          "Select at least one available source snapshot."
        )
      } else if (nrow(filtered_formats()) == 0L) {
        shiny::div(class = "empty-state", "No formats match these filters.")
      }
    })

    output$format_table <- shiny::renderTable({
      rows <- filtered_formats()
      shiny::req(nrow(rows) > 0L)
      rows$present_in_pronom <- ifelse(rows$present_in_pronom, "Yes", "No")
      rows$present_in_droid <- ifelse(rows$present_in_droid, "Yes", "No")
      names(rows) <- c(
        "PUID", "Name", "Version", "MIME types", "Extensions",
        "In PRONOM", "In DROID", "DROID signature references"
      )
      rows
    }, striped = TRUE, hover = TRUE, bordered = FALSE, spacing = "s")

    details <- shiny::reactive({
      shiny::req(input$selected_puid)
      get_integrated_format_details(
        connection, input$selected_puid,
        input$pronom_snapshot, input$droid_snapshot
      )
    })

    output$details <- shiny::renderUI({
      shiny::req(input$selected_puid)
      detail <- details()
      shiny::tagList(
        bs4Dash::bs4Card(
          title = sprintf("Format details — %s", input$selected_puid),
          width = 12,
          detail_presence_ui(detail$observations),
          detail_table_ui("Preferred descriptive values", detail$overview),
          detail_table_ui("Source observations and provenance", detail$observations),
          detail_table_ui("Identifiers", detail$identifiers),
          detail_table_ui(
            "MIME types", detail$mime_types,
            "No MIME type is available from the preferred descriptive source."
          ),
          detail_table_ui("Extensions", detail$extensions),
          detail_table_ui(
            "PRONOM relationships", detail$pronom_relationships,
            "No PRONOM relationships are present for this PUID."
          ),
          detail_table_ui(
            "DROID internal-signature IDs", detail$signatures,
            "DROID is absent or has no internal-signature reference for this PUID."
          ),
          detail_table_ui(
            "DROID priority relationships", detail$droid_priorities,
            "DROID is absent or has no priority relationship for this PUID."
          ),
          detail_table_ui("Source consistency", detail$consistency),
          detail_table_ui(
            "Preserved but unsupported source structures", detail$unsupported,
            "No unsupported structures were reported for the active snapshots."
          ),
          detail_table_ui(
            "Malformed or unresolved source references", detail$issues,
            "No malformed or unresolved references were recorded for this PUID."
          ),
          raw_source_ui(
            "Raw PRONOM JSON", detail$raw_pronom_json,
            "PRONOM is absent from the active context."
          ),
          raw_source_ui(
            "Relevant DROID XML fragment", detail$droid_xml_fragment,
            "DROID is absent from the active context."
          ),
          shiny::p(
            class = "text-muted",
            paste(
              "Complete DROID byte-sequence grammar is preserved in the source",
              "snapshot but remains intentionally unsupported."
            )
          )
        ),
        bs4Dash::bs4Card(
          title = "Contextual profile statements",
          width = 12,
          shiny::p(
            class = "text-muted",
            "These are assertions from imported profiles, not intrinsic PRONOM metadata."
          ),
          detail_table_ui(
            "Profile references", detail$profile_statements,
            "No imported profile references this PUID."
          )
        )
      )
    })
  })
}

update_snapshot_selection <- function(session, input_id, snapshots, current) {
  choices <- snapshot_choice_labels(snapshots)
  selected <- if (length(choices) == 0L) {
    character()
  } else if (current %in% unname(choices)) {
    current
  } else {
    unname(choices)[[1L]]
  }
  shiny::updateSelectInput(session, input_id, choices = choices, selected = selected)
}

detail_presence_ui <- function(observations) {
  source_types <- observations$source_type
  pronom_present <- any(source_types %in% c("pronom_repository", "pronom_json"))
  droid_present <- any(source_types == "droid_binary_signature")
  shiny::p(
    sprintf(
      "Source presence — PRONOM: %s; DROID: %s.",
      if (pronom_present) "present" else "absent",
      if (droid_present) "present" else "absent"
    )
  )
}

detail_table_ui <- function(title, rows, empty_message = "No source information is available.") {
  shiny::tagList(
    shiny::h4(title),
    if (nrow(rows) == 0L) {
      shiny::p(class = "text-muted", empty_message)
    } else {
      shiny::tags$table(
        class = "table table-sm table-striped",
        shiny::tags$thead(shiny::tags$tr(lapply(names(rows), shiny::tags$th))),
        shiny::tags$tbody(lapply(seq_len(nrow(rows)), function(index) {
          shiny::tags$tr(lapply(rows[index, , drop = TRUE], function(value) {
            shiny::tags$td(ifelse(is.na(value), "Absent", as.character(value)))
          }))
        }))
      )
    }
  )
}

raw_source_ui <- function(title, value, absent_message) {
  shiny::tagList(
    shiny::h4(title),
    if (length(value) == 0L || is.na(value) || !nzchar(value)) {
      shiny::p(class = "text-muted", absent_message)
    } else {
      shiny::tags$details(
        shiny::tags$summary("Show preserved source content"),
        shiny::tags$pre(
          style = "max-height: 28rem; overflow: auto; white-space: pre-wrap;",
          value
        )
      )
    }
  )
}

# Compatibility aliases for existing callers.
pronom_explorer_ui <- format_explorer_ui
pronom_explorer_server <- format_explorer_server
