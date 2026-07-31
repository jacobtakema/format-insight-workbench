# Format Insight Workbench
## Product Specification

Version: 0.1 (MVP)

---

# 1. Purpose

Format Insight Workbench is a local desktop application for managing configurable file-format policy profiles.

The application separates technical format information from preservation policy.

Technical format information is imported from external sources such as DROID signature files (derived from PRONOM).

Policy profiles define which formats are preferred, acceptable or prohibited within a particular organisation or preservation policy.

The application validates policy profiles against imported technical reference data and assists with maintaining those profiles over time.

The application is not intended to replace PRONOM or DROID.

---

# 2. Background

Many preservation policies reference PRONOM PUIDs.

Maintaining these references manually is time-consuming because:

- new PRONOM releases introduce new formats;
- format names may change;
- versions may be added;
- DROID signature files evolve;
- organisations maintain their own policy profiles.

There is currently no lightweight tool for maintaining these mappings.

---

# 3. Goals

The MVP shall enable a user to:

- import DROID signature files;
- maintain one or more policy profiles;
- associate policy entries with one or more PUIDs;
- validate those associations;
- compare imported source releases;
- export policy profiles.

---

# 4. Non-goals

The MVP does not:

- identify files;
- replace DROID;
- replace PRONOM;
- edit PRONOM data;
- automatically classify formats;
- perform preservation actions;
- require an internet connection.

---

# 5. Users

Primary users:

- Digital preservation specialists
- Archivists
- Records managers
- Collection managers

Users are assumed to understand concepts such as:

- file formats
- MIME types
- PRONOM
- PUIDs

Programming knowledge is not required.

---

# 6. Core Concepts

The application distinguishes between:

## Technical reference

Imported data originating from external sources.

Examples:

- DROID signature XML
- PRONOM

These sources are read-only.

---

## Policy profile

A configurable set of organisational rules.

Examples:

- National Archives Preferred Formats
- Local Archive Profile
- Project-specific Profile

A profile consists of policy entries.

---

## Policy entry

Represents a preservation recommendation.

Examples:

- PNG
- TIFF
- PDF/A
- XML

A policy entry may reference:

- zero PUIDs
- one PUID
- multiple PUIDs

A policy entry may also contain:

- conditions
- explanatory notes
- validity dates

---

# 7. Functional Requirements

The MVP shall provide:

## Source Import

- Import DROID signature XML.
- Preserve imported source metadata.
- Store immutable snapshots.
- Prevent accidental duplicate imports.

---

## Policy Management

- Create policy profiles.
- Import policy profiles from CSV.
- Edit policy entries.
- Associate multiple PUIDs.
- Store notes and conditions.

---

## Validation

The application shall detect:

- unknown PUIDs
- duplicate mappings
- missing policy status
- missing source references
- policy entries without PUIDs
- name mismatches

---

## Source Comparison

Compare two imported source snapshots.

Highlight:

- new formats
- removed formats
- changed names
- changed MIME types
- changed extensions

---

## Export

Export policy profiles to:

- CSV
- JSON

---

# 8. Non-functional Requirements

The application shall:

- run locally
- require no server
- use DuckDB
- use R Shiny
- support Windows
- preserve imported source data
- be fully reproducible

---

# 9. User Interface

The MVP consists of:

- Overview
- Source Snapshots
- Policy Profiles
- Format Explorer
- Validation
- Export

---

# 10. Success Criteria

The MVP is considered complete when a user can:

1. Import a DROID signature file.
2. Browse imported formats.
3. Import a policy profile.
4. Associate PUIDs with policy entries.
5. Validate the profile.
6. Export the result.
