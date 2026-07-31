#' Open a Format Insight Workbench DuckDB database
#'
#' @param path Database file path, or `:memory:` for a transient database.
#' @return A DBI connection. The caller is responsible for disconnecting it.
open_workbench_database <- function(path = ":memory:") {
  DBI::dbConnect(duckdb::duckdb(), dbdir = path)
}

#' Create the current database schema
#'
#' @param connection An open DBI connection to DuckDB.
#' @param schema_path Path to the initial schema SQL file.
#' @return The connection, invisibly.
initialise_workbench_database <- function(
    connection,
    schema_path = file.path("inst", "schema", "001-initial.sql")) {
  if (!file.exists(schema_path)) {
    stop(sprintf("Schema file does not exist: %s", schema_path), call. = FALSE)
  }
  schema_directory <- if (dir.exists(schema_path)) schema_path else dirname(schema_path)
  schema_files <- sort(list.files(
    schema_directory, pattern = "^[0-9]+-.*[.]sql$", full.names = TRUE
  ))
  if (length(schema_files) == 0L) {
    stop(sprintf("No schema files found in: %s", schema_directory), call. = FALSE)
  }
  for (file in schema_files) {
    sql <- paste(readLines(file, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    DBI::dbExecute(connection, sql)
  }
  invisible(connection)
}
