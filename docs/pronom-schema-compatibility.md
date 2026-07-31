# PRONOM JSON Schema compatibility

## Purpose

The Workbench vendors the official `format_schema.json` from the PRONOM
`develop` branch without modification. The official bytes and SHA-256 checksum
are preserved.

The schema currently contradicts records published on the same branch. A
declarative compatibility overlay is therefore applied only when the official
schema checksum is:

`c4c74f1326fc17d667bc1e165653118e11a5afc4e0ffc4b076ccf1621cb616cf`

The overlay is not applied automatically to a new schema checksum. A new
official schema is first compiled and used unchanged.

## Corpus audit

Audit date: 28 July 2026.

Source: all 2,557 JSON records under `signatures/fmt/` and
`signatures/x-fmt/` on the PRONOM `develop` branch.

Against the unmodified official schema:

- 2,103 records were invalid;
- 20,739 validation violations were returned.

Prominent contradictions included:

- `formatSourceDate` and `lastUpdatedDate` use display dates such as
  `14 Sep 2018`, while the schema declares JSON Schema `format: date`;
- fields declared as strings are frequently null, including
  `formatDisclosure`, `byteOrders`, `binaryFileFormat`, `version` and
  `formatTypes`;
- internal signatures do not contain the flat `positionType`, `offset` and
  `byteSequence` properties marked as required by the schema;
- 28 records omit `formatDescription`, although it is required;
- container signature identifiers are strings in records but integers in the
  schema;
- several container byte-sequence properties marked as required are absent in
  published records.

After applying the compatibility overlay, all 2,557 records passed structural
validation. Workbench semantic validation remains separate and may still
reject records for PUID, path or cross-record inconsistencies.

## Suggested upstream issue

### Title

`format_schema.json does not validate JSON records on the same develop branch`

### Body

The root `format_schema.json` currently does not validate many records under
`signatures/fmt/` and `signatures/x-fmt/` on the same `develop` branch.

I validated all 2,557 format JSON files with a Draft 7 validator. The result
was:

- 2,103 invalid records;
- 20,739 individual schema violations.

A small reproducible example is `signatures/fmt/104.json`. It fails because:

1. `lastUpdatedDate` is `14 Sep 2018`, but the schema declares
   `format: date`;
2. `formatSourceDate` is `11 Mar 2005`, but the schema declares
   `format: date`;
3. `formatDisclosure` is null, but the schema requires a string;
4. `formatTypes` is null, but the schema requires a string;
5. its internal signature lacks the required `positionType`;
6. it lacks the required `offset`;
7. it lacks the required flat `byteSequence`.

Other frequent corpus-wide mismatches include nullable values for fields
declared as strings, missing `formatDescription`, string-valued container
signature IDs, and required container byte-sequence properties that are absent
from the records.

Could the schema be updated to describe the JSON representation actually
published in the repository, and could repository CI validate every
`signatures/fmt/*.json` and `signatures/x-fmt/*.json` file against it?

It would also help downstream consumers if schema changes had a stable version
or `$id`, and if the schema and records were tested together for each release.
