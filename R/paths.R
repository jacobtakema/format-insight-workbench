find_workbench_project_root <- function(start_path) {
  current <- normalizePath(start_path, winslash = "/", mustWork = TRUE)
  if (!dir.exists(current)) current <- dirname(current)
  repeat {
    has_project <- length(list.files(current, pattern = "[.]Rproj$", full.names = TRUE)) > 0L
    if (has_project && file.exists(file.path(current, "AGENTS.md"))) return(current)
    parent <- dirname(current)
    if (identical(parent, current)) break
    current <- parent
  }
  stop("Could not locate the Format Insight Workbench project root.", call. = FALSE)
}

workbench_root_override <- function() {
  current <- Sys.getenv("FORMAT_INSIGHT_WORKBENCH_ROOT", unset = "")
  if (nzchar(trimws(current))) return(current)
  current <- Sys.getenv("FILE_INSIGHT_WORKBENCH_ROOT", unset = "")
  if (nzchar(trimws(current))) return(current)
  Sys.getenv("FORMAT_POLICY_WORKBENCH_ROOT", unset = "")
}

workbench_database_override <- function() {
  current <- Sys.getenv("FORMAT_INSIGHT_WORKBENCH_DB", unset = "")
  if (nzchar(trimws(current))) return(current)
  current <- Sys.getenv("FILE_INSIGHT_WORKBENCH_DB", unset = "")
  if (nzchar(trimws(current))) return(current)
  Sys.getenv("FORMAT_POLICY_WORKBENCH_DB", unset = "")
}

workbench_database_path <- function(project_root,
                                    override = workbench_database_override()) {
  if (!nzchar(trimws(override))) {
    current <- file.path(project_root, "data", "format-insight-workbench.duckdb")
    file_name_alias <- file.path(
      project_root, "data", "file-insight-workbench.duckdb"
    )
    legacy <- file.path(project_root, "data", "format-policy-workbench.duckdb")
    if (!file.exists(current) && file.exists(file_name_alias)) {
      return(file_name_alias)
    }
    if (!file.exists(current) && file.exists(legacy)) return(legacy)
    return(current)
  }
  if (grepl("^(?:[A-Za-z]:[/\\\\]|/)", override)) {
    return(normalizePath(override, winslash = "/", mustWork = FALSE))
  }
  normalizePath(file.path(project_root, override), winslash = "/", mustWork = FALSE)
}

source_relative_path <- function(path, project_root) {
  normal_path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  normal_root <- normalizePath(project_root, winslash = "/", mustWork = TRUE)
  prefix <- paste0(normal_root, "/")
  if (startsWith(normal_path, prefix)) {
    return(substring(normal_path, nchar(prefix) + 1L))
  }
  NA_character_
}
