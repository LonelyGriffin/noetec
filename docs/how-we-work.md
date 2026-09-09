# How we work

Noetec is built by a small team of one human and several AI agents.

- **Pavel Fanaskov** owns the vision, the architecture, the final review, and the merge. Every change is reviewed and merged by a human.
- **AI agents** (Developer, Architect, QA) implement tasks, write and run tests, and review each other's work, orchestrated on the Multica platform.

## What this means for you

- Every line of code is reviewed by a human before it reaches `main`.
- The pipeline is: Developer → Architect (architecture review) → QA (behavior verification) → Pavel (merge).
- `CLAUDE.md` and the `skills/` directory are instructions for the AI agents — you do **not** need to read them to understand or use the project.

This workflow is a deliberate, public experiment in how software can be built. If you find a bug in agent-written code, report it like any other bug — see [SUPPORT.md](../SUPPORT.md).
