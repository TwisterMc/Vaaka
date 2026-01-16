# COPILOT POLICY

**Effective:** 2026-01-16

## Purpose

This file documents repository policy for GitHub Copilot (the assistant) and any automated code suggestion agents.

## Authoritative instruction to GitHub Copilot

- **GitHub Copilot MUST NOT commit, push, merge, or create pull requests on its own.**
- Any code or configuration changes suggested by Copilot must be presented to a human maintainer for review and explicit approval before any commit or push is performed.

## Allowed assistant behavior

- Provide suggestions, diffs, and file contents in messages or as draft files in the working directory for human review.
- Explain the rationale, tests, and any risk/impact for suggested changes.
- Run local checks or tests when requested by a human (in a local environment) but do not push results.

## Forbidden assistant behavior

- Do not commit, push, or merge any changes to the repository without explicit, human-issued commit commands.
- Do not modify CI workflows, secrets, signing keys, or credentials without explicit maintainer approval and review.
- Do not bypass human review processes (e.g., creating or merging PRs automatically).

## How maintainers should verify

- Review suggested changes in diffs or draft files.
- Ensure tests and CI pass on maintainer-triggered runs before merging.

## Development & product policies

- **Feature removal and cleanup** — When removing a feature, always remove any code, tests, assets, configuration, and CI references that are no longer needed. Do not leave abandoned or dead code in the repository.
- **Platform support** — The app must support **macOS 14.0 or later**.
- **Swift version** — The project should be built with **Swift 6.0 or later**.
- **Quality attributes** — The app must be **accessible**, **performant**, **secure**, and adhere to current Swift language and API standards and best practices.
- **No telemetry** — The app must **not** collect telemetry, analytics, or crash reporting data without explicit maintainer approval; by default there must be no telemetry.
- **Remove debug logging** — When a feature is complete, remove debug logs and temporary instrumentation; any runtime logging must be intentional, scoped, and minimal.

## Contact / Escalation

If this policy is violated or you need to change it, contact the repository maintainers and update this file via a documented PR.

---

_This file is intentional and authoritative for any automated assistant interacting with this repository._
