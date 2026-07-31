# Import strategy

## Objective

The smallest MVP import design should preserve immutable source evidence, support browsing and release comparison, and validate policy PUID mappings. It should not attempt to recreate DROID's identification engine or turn PRONOM technical data into policy.

## Import boundaries

Use one snapshot per imported file. Recommended `source_type` values are `droid_binary_signature`, `droid_container_signature`, `pronom_json` and `policy_csv`. Binary and container files must remain separate snapshots because their versions are independent.

Only DROID binary XML import is required by the present MVP. Container XML and PRONOM JSON should initially be treated as analysed future inputs unless their import is explicitly added to scope. The schema can accommodate them without implementing those importers now.

## Minimal normalised DuckDB schema

Types below are DuckDB-oriented. UUIDs may be generated in R or DuckDB; timestamps should be stored in UTC.

### Immutable technical-source tables

| Table | Essential columns | Purpose and constraints |
|---|---|---|
| `source_snapshot` | `snapshot_id UUID PK`, `source_type VARCHAR`, `source_filename VARCHAR`, `source_version VARCHAR NULL`, `source_created_at TIMESTAMP NULL`, `imported_at TIMESTAMP`, `checksum_sha256 VARCHAR`, `import_status VARCHAR`, `raw_content BLOB` | One immutable import attempt. Unique checksum within source type prevents accidental exact duplicates. Status is constrained to explicit states such as `pending`, `succeeded`, `failed`. |
| `source_import_issue` | `issue_id UUID PK`, `snapshot_id UUID FK`, `severity VARCHAR`, `issue_code VARCHAR`, `record_locator VARCHAR NULL`, `message VARCHAR`, `raw_value VARCHAR NULL` | Preserves warnings and errors instead of silently dropping values. |
| `source_format` | `source_format_id UUID PK`, `snapshot_id UUID FK`, `source_record_id VARCHAR`, `puid VARCHAR`, `format_name VARCHAR`, `format_version VARCHAR NULL`, `raw_record VARCHAR NULL` | Snapshot-specific normalised format. Unique on `(snapshot_id, puid)` and, when present, `(snapshot_id, source_record_id)`. IDs are strings because their semantics are source-defined. |
| `source_format_identifier` | `source_format_id UUID FK`, `identifier_type VARCHAR`, `identifier_value VARCHAR`, `original_value VARCHAR`, `ordinal INTEGER` | Holds MIME types and permits later typed PRONOM identifiers without schema change. Unique normalised value per format/type. |
| `source_format_extension` | `source_format_id UUID FK`, `extension VARCHAR`, `original_value VARCHAR`, `ordinal INTEGER` | One extension per row; normalised comparison can be case-insensitive while source spelling is retained. |
| `source_format_signature` | `source_format_id UUID FK`, `signature_kind VARCHAR`, `source_signature_id VARCHAR`, `raw_signature VARCHAR NULL` | Evidence for binary or container signatures. Multiple rows are allowed. It supports derived `has_*_signature` flags without normalising the matching grammar. |
| `source_format_relationship` | `snapshot_id UUID FK`, `subject_source_record_id VARCHAR`, `relationship_type VARCHAR`, `object_source_record_id VARCHAR NULL`, `object_puid VARCHAR NULL`, `original_relationship_type VARCHAR` | Directional priority evidence and optional future PRONOM relationships. Require at least one object identifier. |

For the DROID binary MVP, `source_format_identifier` needs only `mime`, `source_format_signature` needs only `binary_internal`, and `source_format_relationship` needs only `has_priority_over`. `raw_content` is the authoritative preserved input; `raw_record` and `raw_signature` are diagnostic conveniences and may be omitted if storage simplicity is paramount.

### Editable policy tables

| Table | Essential columns | Purpose and constraints |
|---|---|---|
| `policy_profile` | `profile_id UUID PK`, `name VARCHAR`, `description VARCHAR NULL`, `profile_version VARCHAR NULL`, `created_at TIMESTAMP`, `modified_at TIMESTAMP` | Editable profile metadata. |
| `policy_entry` | `entry_id UUID PK`, `profile_id UUID FK`, `information_category VARCHAR NULL`, `display_name VARCHAR`, `policy_status VARCHAR`, `notes VARCHAR NULL`, `conditions VARCHAR NULL`, `effective_from DATE NULL`, `effective_to DATE NULL` | One organisational recommendation. Constrain status to the four agreed values and require `effective_to >= effective_from` when both exist. |
| `policy_entry_puid` | `mapping_id UUID PK`, `entry_id UUID FK`, `puid VARCHAR`, `relationship_type VARCHAR NULL`, `is_required BOOLEAN` | Many-to-many policy mapping. Unique on `(entry_id, puid, relationship_type)`; no foreign key to `source_format`, because unknown or currently absent PUIDs must remain representable and source formats are snapshot-specific. |
| `validation_result` | `validation_id UUID PK`, `profile_id UUID FK`, `snapshot_id UUID FK`, `rule_code VARCHAR`, `severity VARCHAR`, `message VARCHAR`, `entry_id UUID NULL`, `puid VARCHAR NULL`, `created_at TIMESTAMP` | Replaceable derived output for one profile/snapshot validation run. |

This is the minimal normalised schema for the whole MVP. It intentionally omits separate tables for byte sequences, aliases, format families, provenance organisations and container paths because none is needed for browsing, policy validation or the specified comparisons.

## DROID binary import sequence

1. Parse XML without network access. Validate the `FFSignatureFile` root and
   recognise either the PRONOM namespace or the known historical
   namespace-less dialect.
2. Stage all normalised rows in memory. Parsing performs no persistence.
3. Read the source bytes, calculate SHA-256 and reject an already successful import with the same source type and checksum.
4. Begin a database transaction and create the immutable snapshot.
5. Inspect actual PUID coverage and assign `puid_comparison`,
   `partial_historical` or `snapshot_only`; never infer support from the release
   number.
6. Extract each `FileFormat`. Project only records with explicit valid PUIDs
   into the canonical tables. Preserve unresolved historical fragments as
   source records and report valid, placeholder, missing and invalid counts.
7. Split extensions into rows. Split the DROID `MIMEType` attribute on commas only, trim surrounding whitespace, validate conservatively, and preserve the unsplit source value.
   Empty extension elements are preserved in the raw source, omitted from the
   normalised extension set and reported as one aggregated warning.
   Repeated identical extensions are preserved in the source, deduplicated in
   the normalised set and also reported as one aggregated warning.
8. Extract internal-signature references and priority relationships for
   canonical records. Verify references against the complete source release.
9. Preserve the complete original bytes and PUID coverage profile.
10. Commit only after every child row succeeds. On any persistence error, roll back the snapshot and all child rows. Parser failures occur before the transaction and therefore create no database rows.

## Optional future source adapters

### PRONOM JSON

Extract identifiers, extensions, signature evidence and relationships into the same normalised tables. Preserve all richer JSON in `raw_content`/`raw_record`; do not prematurely add columns for fields that the MVP does not use. Treat missing properties and explicit nulls equivalently for normalised optional values but preserve the raw distinction.

Recoverable validation of nested collections does not reject an otherwise
usable parent. A null, empty or whitespace-only `externalSignature` is reported
as an `empty_external_signature` warning and omitted from normalised
extensions. Other valid identifiers, extensions, signatures and relationships
from that format are still imported.

### DROID container XML

Import it as its own snapshot. Map each `FileFormatMapping` PUID to `container` signature evidence and keep the signature definition opaque in `raw_signature`. If container paths become browsable, add container-specific tables then; do not overload extensions or relationships. Never copy a container flag onto a binary snapshot.

## Snapshot comparison

Compare only compatible snapshot types. For two successful DROID binary snapshots:

- join formats by exact normalised PUID;
- report PUIDs present only on either side as added or removed;
- compare names and versions as scalar values;
- compare MIME types and extensions as normalised sets, while displaying preserved originals;
- optionally compare signature-presence evidence, but do not label changed byte signatures unless that requirement is added.

`snapshot_only` releases cannot participate in canonical comparison.
`partial_historical` releases contribute only their explicitly PUID-resolved
records. Source-native identity reconciliation, fuzzy matching and name-only
linkage are reserved for post-MVP Registry Analytics.

`compare_droid_snapshots()` enforces this boundary outside Shiny and returns
the two source descriptions separately; it does not select an arbitrary value
when releases disagree.

A renamed record retains its PUID. A changed numeric PRONOM format ID for the same PUID should be reported as an integrity warning rather than treated as remove/add.

## Validation consequences

Policy mappings should be checked against a chosen successful technical snapshot by PUID, not by a foreign key. This permits unknown PUID detection, preserves policy across snapshot changes, and allows entries without PUIDs. A policy entry without a mapping is a review result, not an import failure. Name mismatch must be advisory because policy display names may intentionally group several formats.

## Assumptions

- SHA-256 is the required checksum algorithm.
- One imported file creates one immutable snapshot, including a failed attempt.
- PUID comparison is exact after trimming surrounding whitespace; case is not rewritten.
- DROID V10 is the earliest published release currently known to have complete
  valid PUID coverage. Import behaviour does not depend on that version number.
- Full source bytes are acceptable to store in DuckDB at the observed file sizes.
- Policy CSV column design will be specified separately.

## Risks

- Future DROID namespaces or historical dialects other than the recognised
  namespace-less structure may require an explicit parser adapter.
- PRONOM JSON appears API-shaped but its contract and version are not documented in the repository.
- Comma-splitting MIME values is based on the observed DROID encoding and could encounter malformed values.
- DuckDB constraints and cascade behaviour need to be verified through DBI tests rather than assumed.
- Failed attempts are reported to the caller but are not retained in DuckDB; operational logging may be needed later if an audit trail of failed attempts becomes a requirement.
- Source-file pairing could be misrepresented if binary and container releases are combined without explicit provenance.
- Storing raw bytes inside the database simplifies reproducibility but increases database size across many snapshots.

## Questions before implementation

1. Is container-signature import part of the MVP, or should `has_container_signature` be removed from the first UI and derived only when that adapter is later added?
2. Are PRONOM JSON imports intended functionality, or are the files supplied only to explain DROID provenance?
3. What is the supported range of DROID binary-signature versions and namespaces?
4. Should an exact duplicate import be blocked, recorded as a failed/duplicate attempt, or return the existing snapshot?
5. Must the complete source file live inside DuckDB, or is an immutable managed file copy plus checksum acceptable?
6. Which policy CSV columns, delimiters, encodings and status spellings form the import contract?
7. Should source comparison include version and signature changes in addition to the product specification's names, MIME types and extensions?
8. Are MIME and extension comparisons case-sensitive for reporting purposes?
9. Should successful imports with non-fatal warnings be represented by a separate status such as `succeeded_with_warnings`?
10. How long should derived validation results be retained, and should repeated runs be grouped by a validation-run identifier?
# Published profile workbook adapter

The Nationaal Archief 2024 workbook is parsed by a dedicated source adapter.
It returns normalised R data frames for profile metadata, entries, PUID
mappings, rationale rows, deterministic rationale links, issues and summaries.
The parser does not open DuckDB. Persistence receives that parser result and
stores it in one transaction together with the immutable workbook snapshot.

The adapter preserves worksheet names, source row numbers, raw row JSON,
unrecognised or absent PUID values, duplicate assertions and all rationale
rows. Only explicit PUID syntax and explicit numeric ranges are interpreted;
names and extensions are never used to infer a PUID.
