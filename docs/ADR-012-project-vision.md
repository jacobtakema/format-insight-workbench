# ADR-012
## Policies are executable knowledge

### Status

Accepted

### Context

Most preservation policies exist as human-readable documents.

As a result they are:

- difficult to validate;
- difficult to compare;
- difficult to automate;
- difficult to maintain.

### Decision

The application models preservation policy as structured, machine-readable knowledge.

A policy should be capable of supporting both human interpretation and automated validation.

### Consequences

Future functionality may include:

- automated compliance checking;
- policy inheritance;
- rule-based validation;
- integration with preservation tools.

The application should avoid storing important policy information only as free text whenever a structured representation is feasible.