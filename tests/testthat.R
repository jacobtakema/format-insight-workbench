library(testthat)
options(warn = 2)

project_root <- normalizePath(".", winslash = "/")
project_path <- function(...) file.path(project_root, ...)
source(project_path("R", "parser-common.R"))
source(project_path("R", "paths.R"))
source(project_path("R", "pronom-schema.R"))
source(project_path("R", "import-pronom-json.R"))
source(project_path("R", "import-droid-xml.R"))
source(project_path("R", "database.R"))
source(project_path("R", "persist-source-import.R"))
source(project_path("R", "github-repository.R"))
source(project_path("R", "import-pronom-repository.R"))
source(project_path("R", "source-queries.R"))
source(project_path("R", "mod-source-snapshots.R"))
source(project_path("R", "mod-pronom-explorer.R"))
source(project_path("R", "mod-import.R"))

test_dir(
  "tests/testthat",
  reporter = "summary",
  env = environment(),
  load_helpers = FALSE
)
