# Architecture Decisions

Version: 0.1

This document records the key architectural decisions made during the development of Format Insight Workbench.

The purpose of these decisions is to preserve design intent over time.

When implementing new functionality, contributors should follow these decisions unless there is a documented reason to change them.

---

# ADR-001
## Separate technical reference data from preservation policy

### Status

Accepted

### Context

PRONOM and DROID describe technical file format information.

Preservation policies describe organisational recommendations.

Although policies often reference PRONOM PUIDs, they are conceptually different.

A policy may:

- reference multiple PUIDs;
- reference no PUID;
- contain organisational conditions;
- evolve independently from PRONOM.

### Decision

The application shall model technical reference data and policy data as separate domains.

Imported source data is read-only.

Policy data is editable.

### Consequences

Advantages

- clear separation of responsibilities;
- multiple policy profiles can reference the same source data;
- future support for additional registries;
- easier validation.

Disadvantages

- additional mapping tables;
- slightly more complex data model.

---

# ADR-002
## Imported sources are immutable

### Status

Accepted

### Context

Users need to compare multiple PRONOM or DROID releases.

Replacing imported data would make historical comparisons impossible.

### Decision

Every import creates a new immutable snapshot.

Snapshots are never modified after import.

### Consequences

Advantages

- reproducibility;
- historical comparison;
- auditability.

Disadvantages

- larger database size.

---

# ADR-003
## Policy profiles are configurable

### Status

Accepted

### Context

Different organisations maintain different preservation policies.

The National Archives Preferred Formats list is only one example.

### Decision

The application supports multiple policy profiles.

The National Archives profile is treated as a reference implementation rather than a built-in rule set.

### Consequences

Advantages

- reusable outside one organisation;
- supports local policy variation;
- future inheritance between profiles.

---

# ADR-004
## DuckDB is the embedded database

### Status

Accepted

### Context

The application is intended to be a local desktop application.

Installing PostgreSQL or another database server would increase complexity.

### Decision

DuckDB is used as the primary database.

### Consequences

Advantages

- zero configuration;
- portable;
- fast analytical queries;
- SQL support.

Disadvantages

- not intended for concurrent multi-user editing.

---

# ADR-005
## Policy entries and PUIDs use a many-to-many relationship

### Status

Accepted

### Context

One policy entry may correspond to multiple PUIDs.

Likewise, one PUID may legitimately appear in multiple policy profiles.

### Decision

Introduce a separate mapping table.

Never store multiple PUIDs inside one text field.

### Consequences

Advantages

- normalised model;
- simpler validation;
- easier querying.

---

# ADR-006
## Preserve imported source values

### Status

Accepted

### Context

Normalisation often loses information.

Users occasionally need to inspect the original imported values.

### Decision

Store original imported values alongside normalised values where practical.

### Consequences

Advantages

- traceability;
- easier debugging;
- future-proof.

---

# ADR-007
## Validation results are derived

### Status

Accepted

### Context

Validation results depend on both:

- the selected policy profile;
- the selected source snapshot.

They should not be edited manually.

### Decision

Validation results are generated from source data and policy data.

They are disposable and reproducible.

### Consequences

Advantages

- no stale validation data;
- deterministic behaviour.

---

# ADR-008
## Local-first architecture

### Status

Accepted

### Context

Many archival institutions work in restricted environments.

Internet access should not be required.

### Decision

The application runs entirely locally.

No cloud services are required.

### Consequences

Advantages

- privacy;
- reproducibility;
- offline use.

---

# ADR-009
## Source registries are plugins, not assumptions

### Status

Accepted

### Context

Today the application targets PRONOM.

Future users may wish to import:

- GDFR
- Wikidata
- LOC registries
- local registries

### Decision

The internal model shall not assume PRONOM-specific identifiers.

PUIDs are treated as one identifier type.

The source registry is stored separately.

### Consequences

Advantages

- future extensibility;
- avoids PRONOM lock-in.

---

# ADR-010
## Prefer simple import pipelines

### Status

Accepted

### Context

Complex ETL pipelines are difficult to maintain.

### Decision

Imports follow four explicit stages.

1. Read source.
2. Parse.
3. Normalise.
4. Persist.

Each stage is independently testable.

### Consequences

Advantages

- simpler debugging;
- better automated tests;
- easier maintenance.

---

# ADR-011
## Build a policy workbench rather than a PRONOM browser

### Status

Accepted

### Context

The goal is not to replicate the PRONOM website.

The application's value lies in supporting policy management.

### Decision

PRONOM browsing is a supporting feature.

Policy management is the primary feature.

### Consequences

Future development should prioritise:

- policy maintenance;
- policy validation;
- release comparison;
- policy review workflows.

Features that merely duplicate PRONOM should be avoided unless they directly support these goals.
