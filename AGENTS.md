# AGENTS.md

## Project

This repository contains a prototype named **Format Insight Workbench**.

It is a local desktop-style R Shiny application for maintaining and validating configurable file-format policy profiles based on PRONOM PUIDs and DROID signature files.

The application is separate from Warqube.

## Primary users

The primary users are digital preservation specialists and records-management professionals. Assume that users understand file formats and PUIDs but may not be software developers.

## MVP scope

The MVP must support:

1. importing a DROID binary-signature XML file;
2. extracting and storing its format records and PUIDs;
3. importing a configurable policy profile from CSV;
4. storing policy entries separately from their PUID mappings;
5. browsing and searching imported PRONOM/DROID format records;
6. validating policy mappings;
7. comparing two imported signature-file snapshots;
8. exporting the policy profile as CSV and JSON;
9. running fully locally without external services.

## Technology

Use:

* R;
* Shiny;
* bs4Dash;
* DuckDB;
* DBI;
* testthat;
* renv;
* modular Shiny code.

Do not introduce Python, Node.js, Docker, an external database or a web API unless explicitly requested.

## Architecture

Keep these concerns separate:

* source import;
* source snapshots;
* normalized format data;
* policy profiles;
* policy entries;
* PUID mappings;
* validation results;
* user interface.

Do not treat the DROID signature file as the policy source of truth.

The policy profile is the policy source of truth.

The imported DROID/PRONOM data is an external technical reference source against which the policy is validated.

## Data modelling rules

A policy entry may:

* map to zero, one or multiple PUIDs;
* contain conditions or explanatory notes;
* be preferred, acceptable, under review or prohibited;
* remain valid without a PUID;
* belong to an information category;
* have effective-from and effective-to dates.

Do not store multiple PUIDs in one delimited database field.

Use a separate many-to-many mapping table.

Preserve the original imported source values alongside normalized values where practical.

Every source import must create an immutable snapshot with:

* source type;
* source filename;
* source version where available;
* import timestamp;
* file checksum;
* import status.

## Coding style

* Use British English in documentation and user-interface text.
* Prefer small, testable functions.
* Avoid large monolithic Shiny server functions.
* Use explicit names rather than abbreviations.
* Add comments only where they explain a non-obvious decision.
* Do not silently discard malformed or unknown source values.
* Return useful validation and import messages.
* Keep the UI functional and restrained rather than decorative.

## Working method

For each task:

1. inspect the existing repository;
2. explain the intended change briefly;
3. make the smallest coherent implementation;
4. add or update tests;
5. run the relevant tests;
6. report which files changed;
7. report assumptions and unresolved issues.

Do not rewrite unrelated files.

Do not add functionality outside the requested task.

## Definition of done

A task is complete only when:

* the requested behaviour is implemented;
* automated tests cover important parsing and validation logic;
* tests pass;
* the application still starts;
* documentation reflects material design decisions;
* errors are shown clearly rather than hidden.
