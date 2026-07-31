parse_github_repository_url <- function(repository_url) {
  match <- regexec(
    "^https://github[.]com/([^/]+)/([^/]+?)(?:[.]git)?/?$",
    trimws(repository_url),
    ignore.case = TRUE
  )
  parts <- regmatches(trimws(repository_url), match)[[1L]]
  if (length(parts) != 3L) {
    stop("Repository must be a GitHub URL such as https://github.com/owner/repository.", call. = FALSE)
  }
  list(
    repository_url = sprintf("https://github.com/%s/%s", parts[[2L]], parts[[3L]]),
    owner = parts[[2L]],
    repository = parts[[3L]]
  )
}

github_headers <- function(token = Sys.getenv("GITHUB_TOKEN", unset = "")) {
  headers <- c(
    Accept = "application/vnd.github+json",
    `X-GitHub-Api-Version` = "2022-11-28",
    `User-Agent` = "Format-Insight-Workbench"
  )
  if (nzchar(token)) headers <- c(headers, Authorization = paste("Bearer", token))
  headers
}

resolve_github_reference <- function(repository_url, reference,
                                     request = httr::GET,
                                     token = Sys.getenv("GITHUB_TOKEN", unset = "")) {
  repository <- parse_github_repository_url(repository_url)
  if (!nzchar(trimws(reference))) stop("Repository reference must not be empty.", call. = FALSE)
  url <- sprintf(
    "https://api.github.com/repos/%s/%s/commits/%s",
    repository$owner,
    repository$repository,
    utils::URLencode(reference, reserved = TRUE)
  )
  response <- request(url, httr::add_headers(.headers = github_headers(token)))
  if (httr::status_code(response) != 200L) {
    stop(sprintf(
      "GitHub could not resolve reference '%s' (HTTP %d).",
      reference, httr::status_code(response)
    ), call. = FALSE)
  }
  content <- httr::content(response, as = "parsed", type = "application/json")
  commit_date <- scalar_character(content$commit$committer$date)
  list(
    repository_url = repository$repository_url,
    owner = repository$owner,
    repository = repository$repository,
    requested_reference = reference,
    resolved_commit = scalar_character(content$sha),
    commit_date = commit_date,
    archive_url = sprintf(
      "https://api.github.com/repos/%s/%s/tarball/%s",
      repository$owner, repository$repository, scalar_character(content$sha)
    )
  )
}

download_github_archive <- function(resolved, destination,
                                    request = httr::GET,
                                    token = Sys.getenv("GITHUB_TOKEN", unset = "")) {
  response <- request(
    resolved$archive_url,
    httr::add_headers(.headers = github_headers(token)),
    httr::write_disk(destination, overwrite = TRUE)
  )
  if (httr::status_code(response) != 200L) {
    stop(sprintf("GitHub archive download failed (HTTP %d).", httr::status_code(response)), call. = FALSE)
  }
  if (!file.exists(destination) || file.info(destination)$size == 0L) {
    stop("GitHub returned an empty repository archive.", call. = FALSE)
  }
  destination
}
