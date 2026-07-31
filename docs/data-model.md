# Data Model

Version: 0.1

---

# Overview

The application separates:

- imported technical reference data
- policy data
- validation results

The imported source data is immutable.

Policy data is editable.

Validation results are derived.

## Source release concepts

- `registry` identifies an external registry such as PRONOM.
- `registry_release` identifies one immutable registry revision. A PRONOM Git commit is one release.
- `import_run` records resolution, download, validation and persistence outcomes, including fatal failures.
- `source_snapshot` preserves one imported archive or signature asset.
- `source_record` preserves one file within a multi-record snapshot, including its relative path, checksum, raw content and parse status.
- `source_validation_schema` preserves the exact JSON Schema and compatibility
  overlay used to validate a source snapshot.
- `format_identity` represents a registry namespace and identifier such as PRONOM `fmt/104`.
- `source_format_identity` links each immutable source observation to its canonical format identity.
- `signature_set` describes a DROID binary or container signature asset without merging it with PRONOM records.
- `droid_snapshot_profile` records the detected XML dialect, support mode and
  PUID coverage counts for one DROID snapshot.
- `release_bundle` and `release_bundle_member` may associate one PRONOM release, one DROID binary release and one DROID container release. Members retain independent versions and dates.

---

# Entity Relationship Diagram

```
Source Snapshot
       │
       │ 1
       │
       ▼
Source Format
       ▲
       │
       │
Policy Entry PUID
       ▲
       │
Policy Entry
       ▲
       │
Policy Profile

Validation Result
```

---

# Source Snapshot

Represents one imported external source.

Examples:

- DROID Signature File V119
- DROID Signature File V120

Fields

- snapshot_id
- source_type
- source_version
- filename
- checksum
- imported_at
- import_status

Snapshots are immutable.

A PRONOM snapshot references an immutable `source_validation_schema`. This
stores the official schema identifier, dialect, official checksum,
compatibility identifier and checksum, effective-schema checksum, and original
schema/overlay bytes. DROID XML snapshots have no JSON validation schema.

Import issues distinguish `syntax`, `structural` and `semantic` validation
layers. Existing issue rows created before this distinction may have a null
layer.

---

# Source Format

Represents one imported format.

Fields

- source_format_id
- snapshot_id
- source_record_id
- puid
- format_name
- format_version
- raw_record

One snapshot contains many formats.

A PRONOM repository snapshot also contains many `source_record` rows. Valid records can produce a `source_format`; rejected records remain preserved with `source_record_issue` rows but produce no normalised format.

For historical DROID, `source_format` contains only records with an explicit,
syntactically valid PUID. A DROID `FileFormat` without a usable PUID is retained
as a `source_record` fragment and in the complete snapshot XML, but no
`format_identity` or `source_format_identity` is created. Numeric DROID
`FileFormat/@ID` values remain source record identifiers and are never converted
to PUIDs.

`droid_snapshot_profile.support_mode` is one of `puid_comparison`,
`partial_historical` or `snapshot_only`. Its coverage counts distinguish valid,
placeholder, missing and invalid PUID values. Snapshot-only releases do not
appear as selectable canonical Explorer sources.

`source_format` is a source observation, not the canonical technical-format
identity. Multiple snapshots and source types may therefore contain separate
`source_format` rows for the same PUID. `source_format_identity` links those
observations to one `format_identity` row per registry and complete identifier.
For PRONOM, `identifier_namespace` is `fmt` or `x-fmt` and `identifier` is the
complete PUID.

The Format Explorer projects selected observations through this identity model.
It does not merge, update or discard the source rows. PRONOM JSON is the
preferred descriptive observation. A DROID binary-signature observation records
identification support in that selected signature release.

Repeating technical values are stored separately:

- `source_format_identifier` stores typed identifiers such as MIME types;
- `source_format_extension` stores one extension per row;
- `source_format_signature` stores internal or container signature evidence;
- `source_format_relationship` stores directional relationships such as identification priority.

Internal- and container-signature flags are derived from signature evidence. Extensions and MIME types are not stored in delimited fields.

## Active source context

An active analysis context contains, independently:

- zero or one selected PRONOM repository/JSON snapshot;
- zero or one selected DROID binary-signature snapshot.

The DROID selection contains only `puid_comparison` and `partial_historical`
snapshots. Partial snapshots contribute only explicitly PUID-resolved records.

No correspondence between their release numbers or dates is inferred. The
integrated Explorer contains the union of PUIDs observed in the selected
snapshots and presents one row per PUID.

---

# Policy Profile

Represents one configurable policy.

Examples

- National Archives Preferred Formats
- Local Policy

Fields

- profile_id
- name
- description
- version
- created_at
- modified_at

---

# Policy Entry

Represents one recommendation.

Examples

PNG

TIFF

XML

Matroska

Fields

- entry_id
- profile_id
- information_category
- display_name
- preferred_status
- notes
- condition
- valid_from
- valid_to

One profile contains many entries.

---

# Policy Entry PUID

Links policy entries to imported formats.

Fields

- mapping_id
- entry_id
- puid
- relationship_type
- required

A policy entry may reference:

- zero PUIDs
- one PUID
- many PUIDs

A PUID may be referenced by multiple policy entries.

This is therefore a many-to-many relationship.

---

# Validation Result

Derived information.

Fields

- validation_id
- profile_id
- snapshot_id
- rule_code
- severity
- message
- entry_id
- puid
- created_at

Validation results are never edited manually.

---

# Relationship Types

Possible values include:

- exact
- accepted_version
- legacy
- container
- codec
- component
- related

Additional relationship types may be introduced later.

---

# Preferred Status

Possible values:

- preferred
- acceptable
- under_review
- prohibited

---

# Information Category

Examples:

- Text
- Spreadsheet
- Raster Image
- Vector Image
- Audio
- Video
- Database
- GIS
- Archive
- Metadata

---

# Import Principles

The original imported values are preserved.

Normalised values are stored separately where required.

Imports must never overwrite previous snapshots.

Every import is reproducible.

The persistence API is append-only for source snapshots and their child rows. An import is committed in one transaction. Failed persistence attempts are rolled back completely, and an exact duplicate successful snapshot is rejected using source type plus SHA-256 checksum.

---

# Future Extensions

The model is designed to support:

- multiple source registries
- local policy inheritance
- profile versioning
- review workflows
- automated policy suggestions
- codec/container relationships
- preservation planning
# Published format profiles

Published guidance is represented separately from technical source metadata.
`policy_profile` identifies the publication and its immutable source snapshot;
`policy_entry` preserves each contextual statement; and `policy_entry_puid`
stores zero, one, or many source-asserted PUID mappings without delimited
database values. `profile_rationale` preserves supporting worksheet rows and
`profile_entry_rationale` records deterministic links with their link method.

Profile mapping status is derived from imported PRONOM observations. It does
not change the source assertion and it is not a validation or compliance
result. Workbook sheet names, row numbers, raw row data, filenames, URLs and
the complete source bytes provide provenance.
