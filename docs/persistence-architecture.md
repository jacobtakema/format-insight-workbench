# Persistence architecture

## Scope

The persistence layer stores normalised PRONOM JSON and DROID binary-signature imports in DuckDB. It also creates the policy and validation tables defined by the MVP data model, but it does not yet provide policy-management operations.

The schema is defined in `inst/schema/001-initial.sql`.

Migration `003-repository-releases.sql` adds registries, releases, import runs, source records, shared format identities, signature sets and release bundles.

## Responsibilities

`R/database.R` opens DuckDB connections and applies the schema. `R/persist-source-import.R` coordinates persistence through:

- `import_pronom_json(connection, path)`;
- `import_droid_xml(connection, path)`;
- `persist_source_import(connection, parsed, source_path)`.

The first two functions invoke the existing pure parsers and accept optional user-visible filename and source-relative-path values. The third accepts an existing `format_policy_import` result, which keeps parsing and persistence independently testable.

## Transaction boundary

Parsing completes before persistence begins. Persistence then:

1. calculates the source file's SHA-256 checksum;
2. rejects parser results containing error-severity validation issues;
3. checks for an existing snapshot with the same source type and checksum;
4. reads the complete source bytes;
5. starts one DuckDB transaction;
6. inserts the snapshot, summaries and every normalised child table;
7. commits only after all rows succeed.

Any database error rolls back the entire snapshot. Parser failures happen before the transaction and do not create database rows.

For repository imports, fatal resolution, download or archive errors leave a failed `import_run` but no snapshot. Record-level errors do not abort the archive: rejected records and raw JSON are committed alongside valid normalised formats. The registry release, snapshot, records, identities, formats, summaries and successful import-run status are committed in one transaction.

Every successfully normalised PRONOM or DROID format observation is linked to a
canonical PRONOM `format_identity` through `source_format_identity`. The link
does not replace the source-specific row. The schema migration backfills links
for existing observations from their validated complete PUIDs without rewriting
referenced source rows.

Integrated Format Explorer queries are read models outside the Shiny modules.
They take explicit PRONOM and DROID snapshot identifiers. PRONOM supplies
descriptive values when present; DROID supplies fallback descriptive values only
for DROID-only PUIDs and supplies signature-support evidence for its selected
release.

## Snapshot identity and immutability

Snapshots use UUID primary keys. Exact duplicate successful imports are prevented by a unique constraint on `(source_type, checksum_sha256)` and reported as `format_policy_duplicate_snapshot`. The condition contains the existing snapshot ID so callers can direct users to it.

The source tables are append-only through the application persistence API: it exposes insertion but no update or deletion operation. DuckDB does not provide row-level permissions for an embedded local database, so direct SQL access by a user with filesystem access cannot be made physically immutable. The checksum and preserved raw bytes provide evidence for detecting unintended changes.

## Raw and normalised values

The full original file is stored as a BLOB on `source_snapshot`. Repeating values are stored in child tables rather than delimited fields:

- typed identifiers;
- extensions;
- signature evidence;
- directional format relationships;
- import issues.
- aggregated import summaries for preserved but non-normalised content.
- strict and compatibility JSON Schema audit counts for PRONOM snapshots.

Snapshot and PUID detail queries remain derived read models. They calculate
coverage from normalised child rows and retrieve descriptions, raw PRONOM JSON
and relevant DROID `FileFormat` fragments from immutable source bytes; they do
not copy these derived display values into new columns.

Format and signature identifiers originating from external sources remain character values. Application UUIDs are separate from those source identifiers.

## Failure behaviour

Missing or conflicting required source values are reported as source-validation errors before persistence. Database constraints remain a defensive second layer. Non-fatal parser issues can be stored in `source_import_issue`.

Schema files under `inst/schema/` are applied in numeric order. Migration `002-source-provenance.sql` adds source-relative paths and import summaries to databases created by the earlier prototype.

Tests deliberately duplicate a format row to trigger a uniqueness violation after the snapshot insert and verify that neither snapshot nor format rows remain.

## Automatic GitHub repository import

The importer resolves one requested branch, tag or commit through GitHub's commit endpoint and downloads one tar archive for the immutable commit. It never requests individual JSON files. A `GITHUB_TOKEN` environment value is used when present.

The archive is listed and checked for unsafe paths before extraction into a temporary directory. Temporary content is removed after success or failure. Duplicate resolved commits are rejected before download, and the archive SHA-256 is stored.

## Release bundles and DROID

Current DROID binary imports create a separate `signature_set`. A future DROID container importer will create a `droid_container` signature set and its own snapshot. To create an analytical bundle, insert `release_bundle_member` rows with roles `pronom_repository`, `droid_binary` and `droid_container`, each pointing to its existing snapshot. No version or date is copied between members.
