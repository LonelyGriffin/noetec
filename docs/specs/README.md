# Behavior specifications

This directory contains user-facing behavior specifications: observable outcomes
and acceptance scenarios, not storage formats or implementation designs.

## Catalog

| Specification | Scope | Status and implementation coverage |
|---|---|---|
| [Vault user workflow](01-vault-user-workflow.spec) | Creating, opening, closing, and managing vaults | Existing behavior baseline; explicitly unimplemented scenarios remain future requirements, not claims of current support |

The vault specification is preserved as-is, including its name and Markdown
Given/When/Then tables. The `.spec` extension does not imply executable Gherkin.

## Authoring rules

- Group scenarios by user capability. Describe preconditions, actions, observable
  results, and relevant error cases using the existing Given/When/Then style.
- Avoid implementation classes, development steps, and architectural rationale.
  Link to [technical contracts](../contracts/README.md) or existing
  [ADRs](../decisions/) where needed; do not duplicate them.
- For new specifications, state scope and document status: `draft`, `accepted`,
  or `deprecated`. Acceptance requires explicit project-owner approval; a file
  location or a passing test does not grant acceptance.
- Track implementation coverage separately from approval. A scenario can be
  accepted but not implemented. Identify future scenarios explicitly; do not
  infer current support from the absence of a status note.
- Link to relevant tests or issues when available. Scenarios need not be directly
  executable, but their outcomes must be testable.
- Update affected scenarios when an approved behavior change is implemented.

Existing accepted behavior takes precedence over code within its scope; report
discrepancies. Draft or ambiguous requirements require review before treating
code as defective.
