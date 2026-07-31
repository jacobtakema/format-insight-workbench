# Parser architecture

## Purpose

The import layer converts external PRONOM and DROID representations into a common set of normalised R data frames. It performs no DuckDB access and has no knowledge of future persistence identifiers or transactions.

## Public parsers

- `parse_pronom_json(path)` parses one JSON record from the PRONOM repository.
- `parse_droid_xml(path)` parses one DROID binary-signature XML release.
- `parse_pronom_repository_archive()` discovers and parses all direct JSON records under `signatures/fmt/` and `signatures/x-fmt/` in one repository archive.

Both return an object with class `format_policy_import`. This is a named list whose elements are data frames:

| Element | Content |
|---|---|
| `metadata` | Source type, source version, creation value and filename |
| `formats` | Source record ID, PUID, name and version |
| `identifiers` | Typed identifiers, including PUID and MIME values |
| `extensions` | One normalised extension per row, with its original value |
| `signatures` | Format-to-signature evidence without decomposing byte grammar |
| `relationships` | Directional relationships between source records |
| `issues` | Non-fatal missing or malformed values with stable issue codes |
| `summaries` | Aggregated information about well-formed source content that is preserved but not normalised |
| `source_records` | DROID `FileFormat` fragments that have no usable PUID and therefore cannot enter the canonical projection |

The tables have stable columns even when they contain zero rows. Source record IDs and signature IDs are character values because their meaning is source-specific; they are not application database keys.

## PRONOM JSON validation pipeline

PRONOM JSON import has four explicit stages:

1. decode JSON syntax;
2. validate source structure using the official Draft 7 JSON Schema and a
   checksum-bound compatibility overlay;
3. validate application semantics;
4. project valid structure into normalised data frames.

`R/pronom-schema.R` owns schema loading, dialect checking, compatibility
operations, validator compilation and translation of validator output into
stable parser issues. `R/import-pronom-json.R` owns semantic validation and
normalised projection.

Structural validation covers schema-defined object, array, property, type and
required-property constraints. A structurally invalid record produces no
normalised rows. Semantic validation covers Workbench invariants that are not
the source representation contract, including required `fileFormatID`,
identifier/PUID cardinality, supported PUID syntax and required internal
signature identifiers.

Semantic validation is child-scoped where a malformed nested value does not
invalidate the parent. A null, empty or whitespace-only
`externalSignature` produces an `empty_external_signature` warning at its
array path. That child is skipped during normalisation, while the rest of the
PRONOM record remains importable. The complete JSON, including the invalid
child, remains preserved in the immutable source content.

Every syntactically readable PRONOM record is also evaluated against the
unmodified official schema for audit purposes. The strict violation count,
effective compatibility violation count and number of schema-validated records
are persisted as snapshot summaries. Strict violations are informational and
do not replace compatibility-schema structural validation.

Repository-level semantic validation additionally checks that the PUID agrees
with the `signatures/fmt/` or `signatures/x-fmt/` source path. The repository
schema is loaded from the same downloaded archive as its records.

## Separation from persistence

The parsers only read and transform a supplied local file. They do not:

- calculate checksums;
- decide whether a snapshot is a duplicate;
- generate database keys;
- start transactions;
- insert or update database rows;
- decide whether non-fatal issues permit persistence.

The persistence service owns those responsibilities. It validates a parser result, attaches a snapshot ID to each table and commits the resulting rows atomically.

The service is implemented in `R/persist-source-import.R`. The parser API remains independent: parsing can still be tested and used without opening a database. `import_pronom_json()` and `import_droid_xml()` are thin coordinators that parse first and then pass the result to `persist_source_import()`.

## Error model

Unreadable or syntactically malformed input raises `format_policy_parse_error`.
An unreadable, incompatible or unsupported schema raises
`format_policy_schema_error`. Structurally invalid and semantically invalid
records return issue rows with `validation_layer` set to `structural` or
`semantic`. Repository syntax failures are stored with layer `syntax`.
Persistence refuses any result containing error-severity issues and raises
`format_policy_source_validation_error` before opening a transaction.

Validation includes JSON Schema constraints, required semantic scalar values,
empty or conflicting PUID identifiers, PUID syntax, empty DROID format
collections, and resolution of DROID signature and priority references.

The DROID parser requires the `FFSignatureFile` root and accepts either the
PRONOM signature namespace or the known historical namespace-less dialect. An
unknown non-empty namespace is rejected. Queries use constrained local element
names after dialect recognition, and network access is disabled during XML
parsing. Container-signature XML remains a separate unsupported source.

Support mode is derived from actual `FileFormat/@PUID` coverage, never from the
release number:

- `puid_comparison`: every record has a valid PUID and is projected into the
  canonical model;
- `partial_historical`: valid explicit PUID records are projected, while
  unresolved fragments remain source records;
- `snapshot_only`: no usable PUID exists, so only the immutable snapshot,
  unresolved source records, statistics and issues are persisted.

Missing PUIDs, the historical `Not yet assigned` placeholder and other invalid
values are counted separately and reported as aggregated warnings. No mapping
is inferred. DROID V10 is the earliest published release currently known to
have complete valid PUID coverage; this is documentation, not parser logic.

An empty, well-formed DROID `Extension` element is preserved in the source XML
but produces no normalised extension row. Empty extensions are reported once
per snapshot as an aggregated warning. They do not invalidate an otherwise
usable official signature release; V65 contains two such elements.

Repeated identical extension values are likewise preserved in raw XML but
stored once because normalised multi-valued fields are sets. V65 contains one
repeated `wav` value for `fmt/141`; it is reported as an aggregated warning
rather than left for a database uniqueness constraint to reject.

## Normalisation decisions

- PUIDs remain character values and support both `fmt/` and `x-fmt/`.
- Repeating extensions, signatures and relationships become separate rows.
- DROID's comma-delimited MIME attribute becomes one identifier row per MIME value. Its complete original attribute is retained on every resulting row.
- Extensions are lower-cased for comparison while source spelling is retained.
- PRONOM relationship labels are converted to lower snake case and also retained verbatim.
- Detailed internal byte sequences remain outside the normalised result because the MVP does not identify files. The source file will later be preserved at snapshot level.
- Unsupported but well-formed descriptive and byte-signature structures produce aggregated summary rows. They remain available in the preserved original source content.

## Extensibility

The repository adapter reuses the one-record PRONOM parser. It validates the path-derived PUID, retains malformed records and their issues, and continues with valid records. New official schema checksums are first compiled without the compatibility overlay, which is applied only to the official checksum for which it was written. Compatible optional properties are preserved without parser changes. A breaking change to fields used by the normalised projection requires an explicit projection version rather than silent coercion. A future container adapter can create a `droid_container` signature set without being conflated with binary DROID releases.

## Tests

The tests exercise supplied DROID versions 1, 65 and 124, a compact partial
historical fixture, and malformed or unsupported XML. They assert tier
classification, canonical projection and preservation of unresolved records.
