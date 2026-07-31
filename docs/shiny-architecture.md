# Minimal Shiny application

## Scope

The first user interface contains only:

- Source Snapshots;
- Format Explorer;
- Import.

It deliberately contains no policy-profile, validation or export functionality.

## Structure

`app.R` assembles the `bs4Dash` shell and owns one DuckDB connection per Shiny session. It locates the project root from the application location or the `FORMAT_INSIGHT_WORKBENCH_ROOT` override rather than relying on the current working directory. The database defaults to `data/format-insight-workbench.duckdb`; `FORMAT_INSIGHT_WORKBENCH_DB` may override it with an absolute path or a path relative to the project root. The temporary `FILE_INSIGHT_WORKBENCH_*` names and the former `FORMAT_POLICY_WORKBENCH_*` names remain supported for compatibility. Existing database files using either earlier filename are reused when no canonical database exists.

Each page is a Shiny module:

- `R/mod-source-snapshots.R` displays immutable import history and selected
  snapshot metrics/issues;
- `R/mod-pronom-explorer.R` displays integrated PUIDs and selected PUID details;
- `R/mod-import.R` imports one of the three bundled example sources.

Read queries are isolated in `R/source-queries.R`. UI modules do not contain SQL or persistence implementation.

## Refresh flow

The main server owns a small reactive revision number. A successful import increments it. Snapshot and explorer modules depend on that revision and re-query DuckDB when it changes. Duplicate or failed imports do not trigger a refresh.

## Explorer semantics

The Explorer displays one row per PUID in the independently selected PRONOM and
DROID snapshots. PRONOM supplies preferred descriptive values; DROID supplies
fallback descriptions for DROID-only PUIDs and release-specific identification
evidence.

The PUID detail panel exposes normalised identifiers, MIME types, extensions,
PRONOM relationships, DROID internal-signature IDs, DROID priority
relationships and provenance. Description and raw PRONOM JSON are read from the
preserved source record. The relevant DROID `FileFormat` element is extracted
from the preserved XML without parsing complete byte-sequence grammar.

Absent source information is labelled separately from structures that are
present in raw source content but intentionally unsupported.

## Snapshot details

The Source Snapshots page derives metrics through `R/source-queries.R` rather
than in the Shiny module. Metrics cover record and issue counts, PUID namespace
coverage, signature-reference coverage, missing MIME/extension values, strict
official-schema violations, effective compatibility validation and overlay
identity.

Schema metrics are shown as unavailable for snapshots imported before audit
summaries were introduced and as not applicable for DROID XML. Import summaries
and record-level issues remain visible as tables. No chart is used because the
small set of exact metrics is clearer as a table.

## Example imports

The Import page exposes files committed under `data/raw/`:

- PRONOM `fmt/1`;
- PRONOM `fmt/104`;
- DROID binary signature version 124.

Exact duplicate imports are reported using the existing snapshot ID. All imports remain local.

It also accepts:

- one or more user-selected PRONOM JSON files;
- one user-selected DROID binary-signature XML file.

The automatic repository section accepts a configured GitHub repository and branch, tag or commit. Resolution is a separate user action so the immutable commit and date can be inspected before import. Import progress reports resolution, archive download, record parsing and completion.

The upload's visible filename and any relative path supplied by the browser are retained separately from Shiny's temporary upload path. Multi-file PRONOM imports report each success, duplicate or validation failure without merging the files into one snapshot. Concise import summaries explain which descriptive or signature structures were preserved in the raw source but not normalised.
