# ADR 013: published format profiles

## Decision

The first profile adapter imports the Nationaal Archief workbook *Norm
Voorkeursformaten 2024*. A profile is contextual policy guidance and is not
PRONOM format metadata. Its source workbook is stored as an immutable
`format_profile_xlsx` snapshot.

The adapter recognises the worksheets `Lijst Voorkeursformaten` and
`Onderbouwing`. Category-only rows establish context for subsequent entries.
Rows containing format data become profile entries. Dutch source statuses are
preserved and normalised to `preferred`, `acceptable`, or `under_review` when
the source status is missing or unknown.

PUIDs are split on explicit whitespace, line, comma, and semicolon separators.
Explicit ranges such as `fmt/21-36` are expanded. `Geen`, blank values, and
invalid values such as `TSS-fmt/9` are preserved and reported; they are never
invented or fuzzily matched. Duplicate PUID references remain separate profile
assertions.

The rationale worksheet is preserved in a separate table. Entries are linked
only by deterministic, normalised exact source labels. Unlinked rationale rows
remain available with their workbook row provenance.

Mapping states are derived against imported PRONOM observations:

- `mapped`: all syntactically valid PUIDs for the entry exist in imported PRONOM;
- `unknown_puid`: at least one valid PUID is not in imported PRONOM;
- `invalid_puid`: at least one source value is syntactically invalid;
- `no_puid`: the source is blank or explicitly says `Geen`.

These states do not alter the original assertion. Raw rows and the complete
workbook remain available for audit.

## Consequences

The implementation is deliberately source-specific but uses the existing
generic profile, entry, and entry-to-PUID tables. It does not add generic rule
evaluation, fuzzy mapping, conformance claims, or compliance workflows.
