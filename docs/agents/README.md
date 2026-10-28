# Agent documentation

This directory contains implementation governance and evidence for coding agents and maintainers. Human setup and usage guidance remains directly under `docs/`.

Read these documents selectively according to the task:

- [GOALSET.md](GOALSET.md) — the current implementation requirements and definition of done.
- [Cadenza-Implementation-Goalset.md](Cadenza-Implementation-Goalset.md) — the UI revision addendum supplied during implementation.
- [DEVELOPMENT.md](DEVELOPMENT.md) — repository architecture, development workflow, and local quality gates.
- [COMPATIBILITY.md](COMPATIBILITY.md) — preserved identifiers, protocol compatibility, recovery, and upgrade constraints.
- [RESOURCES.md](RESOURCES.md) — resource-efficiency guidance and the target measurement procedure.
- [VALIDATION.md](VALIDATION.md) — dated evidence, limitations, and required platform validation.

`GOALSET.md` is the only base acceptance document. The revision file contains only later UI-specific additions and clarifications, so a base requirement belongs in `GOALSET.md` and a UI requirement belongs in the addendum.

The root [AGENTS.md](../../AGENTS.md) points agents here. Human-facing build, setup, installation, usage, troubleshooting, and release guides remain in the parent `docs/` directory.
