# Source analysis

## Scope and method

This analysis covers the four supplied files in `data/raw/`:

| File | Source represented | Observed scope |
|---|---|---|
| `1.json` | PRONOM format record | One record: `fmt/1` / file-format ID 735 |
| `104.json` | PRONOM format record | One record: `fmt/104` / file-format ID 646 |
| `DROID_SignatureFile_V124.xml` | DROID binary-signature release | Version 124, created 9 June 2026 |
| `container-signature-20260119.xml` | DROID container-signature release | Signature version 40, schema version 1.0 |

The counts below describe these samples, not a promise about every historic or future release. The JSON filenames correspond to the numeric part of the PUID, not to `fileFormatID`.

## PRONOM JSON

The JSON files are rich, self-contained registry records. Both contain:

- PRONOM's numeric `fileFormatID`, name and version;
- a long description and registry dates;
- disclosure, provenance, source and other descriptive metadata;
- aliases, types, families and byte order;
- typed identifiers, including PUID and MIME type;
- external signatures such as file extensions;
- internal signatures, their notes and byte sequences;
- typed relationships to other PRONOM format IDs.

The records are not structurally uniform. Fields can be absent or `null`; `104.json` has `supportedBy` and `developedBy`, while `1.json` does not. Several conceptually multi-valued properties are strings in these samples (`formatAliases`, `formatTypes`, `byteOrders` and `formatFamilies`), whereas identifiers, signatures and relationships are arrays. Dates use English display strings such as `19 Jul 2013`, not ISO 8601.

The internal-signature representation is relatively compact: a signature has a PRONOM signature ID, name, note and byte sequences with position, offsets, expression and optional endianness. It does not reproduce all of DROID's compiled matching structures.

## DROID binary-signature XML

`DROID_SignatureFile_V124.xml` uses the default namespace `http://www.nationalarchives.gov.uk/pronom/SignatureFile`. Namespace-aware parsing is therefore required.

The file contains two linked collections:

- 2,258 `InternalSignature` definitions, holding compiled matching instructions;
- 2,557 `FileFormat` records, each with a unique numeric PRONOM format ID and PUID.

The format records contain name, optional version, optional comma-separated MIME-type attribute, zero or more extensions, zero or more internal-signature ID references, and zero or more numeric `HasPriorityOverFileFormatID` references. In this sample:

- 1,142 formats have no version;
- 1,778 have no MIME type;
- 141 have no extension;
- 641 have no internal binary signature;
- 549 have multiple extensions;
- 204 have multiple internal-signature references;
- 198 have multiple priority targets;
- 44 store more than one MIME type in the single `MIMEType` attribute.

All 2,258 signature references resolve, all signatures are referenced, and all 1,224 priority references resolve within this file. This is useful validation evidence, but importers must not assume future inputs have the same integrity.

The compiled signature grammar is richer than a simple byte-expression string. It includes BOF/EOF references, subsequences, minimum and maximum offsets, fragments, shifts, wildcard expressions and occasional endianness. Fully normalising that grammar is unnecessary for the MVP because the application does not identify files.

## DROID container-signature XML

The container file has no XML namespace and is not part of the binary-signature XML. It contains:

- 310 container signatures;
- 310 signature-to-format mappings covering 279 unique PUIDs;
- OLE2 and ZIP container types;
- three trigger PUIDs that tell DROID when to inspect a container type.

A container signature describes required internal paths and may attach binary signatures to individual contained files. A PUID can map to several container signatures: 27 PUIDs do so in this sample. Every mapping resolves to a container signature, and every mapped PUID also exists in the supplied binary file.

The `signatureVersion` (`40`) is independent of binary signature version (`124`). The date in the filename is not represented as a source date inside the XML and should not be treated as authoritative metadata without an explicit convention.

## How the sources relate

PUID is the stable cross-source join key. Numeric PRONOM format ID also appears in the JSON and binary DROID file, but container mappings expose only PUID and signature ID. Signature IDs are local technical identifiers: an internal binary-signature ID must not be confused with a container-signature ID.

The two JSON records match their binary DROID records on PUID, numeric format ID, name, version, MIME type, extension, internal-signature ID and priority-over relationships. For example, `fmt/104` is file-format ID 646 in both, and both connect it to internal signature 42. The JSON additionally says it is a previous version of another record; the DROID binary file does not carry that relationship.

The sources should therefore be understood as separate views:

- PRONOM JSON is registry-centred descriptive data;
- DROID binary XML is a release snapshot optimised for byte-level identification;
- DROID container XML is a separately versioned identification source for structured containers.

None is the policy source of truth. Policy entries must continue to exist independently and may legitimately have no PUID.

## Information observed only in PRONOM JSON

Relative to the supplied DROID XML files, the JSON provides:

- descriptions, notes, aliases, format families and format types;
- release, withdrawal, source and last-updated dates;
- binary/text classification, disclosure, environment and risk fields;
- provenance text and provenance organisation;
- byte order at format level;
- typed identifiers rather than only PUID and a MIME attribute;
- internal-signature names and notes;
- relationship types beyond identification priority, including version succession;
- organisation links such as developer and supporter identifiers when present;
- related-format names alongside numeric IDs.

These conclusions are based on two JSON examples. Nulls do not establish that a property is universally unavailable.

## Information observed only in DROID XML

Relative to the supplied JSON records, DROID provides:

- release-level binary signature version and creation timestamp;
- compiled matching details such as fragments, shifts, specificity and detailed offset mechanics;
- a complete release-wide collection suitable for snapshot comparison rather than isolated records;
- container types, required internal paths, contained-file signatures and trigger PUIDs;
- container signature version and schema version.

The JSON examples contain byte-sequence expressions, so byte signatures are not DROID-only; the DROID-only distinction is their compiled operational representation and release packaging.

## Import edge cases

1. XML namespace handling differs between the binary and container files.
2. Optional attributes and JSON nulls are common and must not become empty strings silently.
3. PUID namespaces include both `fmt/` and `x-fmt/`; validation must not accept only one prefix.
4. MIME types are an array in JSON but a comma-separated XML attribute in DROID. Splitting should be conservative, trim whitespace and retain the original value.
5. Extensions and signature references are genuinely multi-valued.
6. Numeric format IDs and signature IDs are not globally interchangeable and may only be meaningful in their source context.
7. A PUID may have no binary signature, no extension, no MIME type, or several container signatures; none automatically makes the format invalid.
8. Priority is directional and release-specific. `A has priority over B` is not a generic semantic relationship.
9. JSON dates are locale-shaped display values; XML dates use ISO-like forms. Parse strictly and preserve source text when parsing fails.
10. PRONOM JSON fields may be conditionally absent, newly introduced or differently shaped in other API versions.
11. Signature expressions contain whitespace, quoted text, ranges, wildcards and XML escaping. They must be treated as opaque source data unless identification is deliberately implemented later.
12. Duplicate detection by checksum is exact-file detection only. The same logical release could be serialised differently, while different filenames could contain identical bytes.
13. A failed import still needs a recorded snapshot attempt and useful issues, but must not expose partially loaded normalised rows as a successful snapshot.
14. Binary and container releases have independent versions. Pairing them merely because they were supplied together could produce false provenance.

## Recommended changes to the current data model

The current model has the right separation of source, policy and derived validation data, but four changes are advisable:

1. Replace `Source Format.extensions` with a child table. The source contains multiple extensions and comparison must operate on sets, not delimited text.
2. Treat MIME types the same way. The DROID attribute is sometimes comma-delimited, while PRONOM uses typed identifier rows.
3. Replace the ambiguous `priority` scalar with a directional format-relationship table, at least for `has_priority_over`.
4. Do not store `has_internal_signature` or `has_container_signature` as independent facts that can drift. Derive them from source evidence, or store explicit evidence rows. Container evidence belongs to its own snapshot.

`raw_xml` on each format is useful for DROID format fragments but cannot reproduce all referenced signature definitions by itself. Preserve the complete imported file (or its bytes/text) at snapshot level, and retain a raw record fragment only when it aids diagnostics. Likewise, validation results should link to an entry where relevant but allow snapshot-level results with no entry or PUID.
