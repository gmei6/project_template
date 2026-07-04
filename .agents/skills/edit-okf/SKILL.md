---
name: edit-okf
description: Use when the user asks to read, create, or edit files within the okf/ knowledge bundle (e.g., "update okf", "start a session", "make a decision") to enforce OKF structural conventions like mutability, index syncing, and changelog management.
---

# edit-okf Skill Instructions

Use this skill's logic when starting a session, ending a session, or anytime you are reading, creating, or editing files in the `okf/` directory, to enforce the bundle's structural and mutability conventions.

## Steps

1. **Observe Directory-Level Conventions**:
   - `okf/decisions/`: One file per decision, named `d-NNN-short-slug.md` (sequential, never renumbered). Frontmatter requires `type: Decision`, `mutability: append-only`, `timestamp` (ISO 8601), optional `tags`. Never edit a decision once written; instead, write a new decision that supersedes it.
   - `okf/changes/`: One file per session/unit of work, named `s-NNN-short-slug.md` (sequential). Frontmatter requires `type: Session Change`, `mutability: append-only`, `timestamp`, optional `tags`. It holds the full narrative of the session's changes.
   - `okf/log.md`: Reserved changelog. Date-headed (newest first), one line per session linking to its `changes/s-NNN.md` file. Never holds full narrative text itself.
   - `okf/references/`: One file per external source. Frontmatter requires `type: Reference`, `resource` (canonical URL), optional `tags`.

2. **Respect Mutability Frontmatter on Concept Files**:
   - `mutability: frozen`: Requires a decision file (`decisions/d-NNN.md`) explaining the change *before* editing. Then, make a minimal edit, and link the concept to the decision (and vice versa). Do not silently edit frozen files.
   - `mutability: live`: Can be overwritten freely to reflect the current state.
   - `mutability: append-only`: Add new entries only at the bottom. **CRITICAL**: You are strictly forbidden from using text editing tools to directly edit append-only files (e.g., `okf/log.md`, `changes/`, `decisions/`). You MUST use the provided Python script to append content: `python .agents/skills/edit-okf/scripts/append_okf.py <filepath> "<content>"` or pipe content into it. Never edit prior entries.

3. **Keep index.md Synchronized**:
   - Every `index.md` must follow the OKF spec exactly: one or more `#` section headings, each followed by a flat bullet list of `[Title](relative-path) - short description`.
   - Update the respective `index.md` file whenever a file in its directory is added, renamed, or removed. No prose or frontmatter is allowed outside the list.

4. **Maintain log.md and changes/ Pairing**:
   - When creating a `changes/s-NNN.md` file, simultaneously add its corresponding one-line entry to `okf/log.md`.
   - Flag and fix any mismatch (a `changes/` file missing a `log.md` entry, or vice versa).

5. **Follow the Session Workflow**:
   - **Start of session**: Read the root `okf/index.md`, relevant `live` files, and only the specific `frozen` concept files pertinent to the task.
   - **End of session**: Overwrite relevant `live` files. Append one `changes/s-NNN.md` file and add its pointer to `log.md`. Append any new `decisions/d-NNN.md` entries and link them to affected concepts. Update any `index.md` files that gained or lost entries.
