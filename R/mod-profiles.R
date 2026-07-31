profiles_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::selectInput(ns("profile"), "Profile", choices = character()),
    shiny::uiOutput(ns("content"))
  )
}

profiles_server <- function(id, connection, refresh) {
  shiny::moduleServer(id, function(input, output, session) {
    profiles <- shiny::reactive({ refresh(); list_format_profiles(connection) })
    shiny::observe({
      rows <- profiles()
      choices <- if (nrow(rows)) stats::setNames(rows$profile_id,
                                                  paste(rows$name, rows$version)) else character()
      selected <- if (!is.null(input$profile) && input$profile %in% choices) {
        input$profile
      } else if (length(choices)) choices[[1L]] else character()
      shiny::updateSelectInput(session, "profile", choices = choices, selected = selected)
    })
    output$content <- shiny::renderUI({
      shiny::req(input$profile)
      detail <- get_profile_overview(connection, input$profile)
      metadata <- detail$metadata
      bs4Dash::bs4Card(
        title = metadata$name[[1L]], width = 12,
        shiny::p(sprintf("Publisher: %s | Version: %s | Source: %s | Imported: %s",
                         metadata$publisher[[1L]], metadata$version[[1L]],
                         metadata$source_name[[1L]],
                         format_source_timestamp(metadata$imported_at[[1L]]))),
        shiny::tags$a(href = metadata$source_url[[1L]], "Published source", target = "_blank"),
        shiny::h4("Summary"), shiny::tableOutput(session$ns("metrics")),
        shiny::h4("Status distribution"), shiny::tableOutput(session$ns("status")),
        shiny::h4("Category distribution"), shiny::tableOutput(session$ns("category")),
        shiny::h4("Profile entries"), shiny::tableOutput(session$ns("entries")),
        shiny::h4("Duplicate PUID references"), shiny::tableOutput(session$ns("duplicates")),
        shiny::h4("Import issues"), shiny::tableOutput(session$ns("issues"))
      )
    })
    detail <- shiny::reactive({ shiny::req(input$profile); get_profile_overview(connection, input$profile) })
    output$metrics <- shiny::renderTable(detail()$metrics, striped = TRUE)
    output$status <- shiny::renderTable(detail()$status, striped = TRUE)
    output$category <- shiny::renderTable(detail()$category, striped = TRUE)
    output$entries <- shiny::renderTable(detail()$entries, striped = TRUE)
    output$duplicates <- shiny::renderTable(detail()$duplicates, striped = TRUE)
    output$issues <- shiny::renderTable(detail()$issues, striped = TRUE)
  })
}
