# OKF Skill Plan

Gary - this is the planning doc for a future Claude Code skill, tentatively named "edit-okf".
Its job is to enforce the structural conventions of this project's OKF-style knowledge bundle (`okf/`), so the bundle itself stays lightweight and free of embedded instructions.
Status: planning only, not yet built.

## Why a skill instead of in-bundle docs

The OKF spec keeps `index.md` files lean: a heading plus a flat link list, no prose.
Putting "how to write a decision" or "how to name a file" instructions inside the bundle would violate that leanness and would duplicate across every subdirectory.
Instead, those rules live once, in this skill, and get applied whenever a file is created or edited.

## Conventions the skill must enforce

### Directory-level conventions

- `decisions/` - one file per decision.
  Filename pattern `d-NNN-short-slug.md`, sequential, never reused, never renumbered.
  Frontmatter: `type: Decision`, `mutability: append-only`, `timestamp` (ISO 8601 date decided), optional `tags`.
  Body is append-only. Once written, a decision file's content is never edited.
  If a decision is reversed or refined, a new decision file is written that supersedes it, and both files say so explicitly.

- `changes/` - one file per session or unit of work.
  Filename pattern `s-NNN-short-slug.md`, sequential, never reused.
  Frontmatter: `type: Session Change`, `mutability: append-only`, `timestamp`, optional `tags`.
  Holds the full narrative for that session's changes to the bundle.
  Every file here must be referenced by exactly one line in `log.md`; a `changes/` file with no corresponding `log.md` line is incomplete.

- `log.md` - the OKF reserved changelog file.
  Stays terse: one line per session, date-headed, newest date first, each line linking to its `changes/s-NNN.md` for detail.
  Never holds full narrative text itself.

- `references/` - one file per external source.
  Frontmatter: `type: Reference`, `resource` (canonical URL), optional `tags`.

### Cross-cutting frontmatter convention

- `mutability` field on every concept file, value one of `frozen`, `live`, `append-only`.
  - `frozen`: encodes agreed direction or definitions.
    Only changes through a decision file plus a minimal edit.
  - `live`: current-state snapshot.
    Overwritten freely and truthfully.
  - `append-only`: permanent record.
    New entries only, at the bottom, never edits to prior entries.

### index.md conventions

- Every `index.md` follows the OKF spec exactly: one or more `#` section headings, each followed by a flat bullet list of `[Title](relative-path) - short description`.
  No frontmatter, no prose outside the list items.
- The skill keeps each directory's `index.md` in sync whenever a file in that directory is added, renamed, or removed.

### Editing a frozen concept

- Before editing any file whose frontmatter says `mutability: frozen`, the skill first requires a decision file recording the change and its rationale, then makes the minimal edit to the frozen file, then links the frozen file's edit to the decision and vice versa.
- The skill should refuse or flag a silent edit to a frozen file with no accompanying decision.

### changes/log.md pairing enforcement

- Whenever the skill creates a `changes/s-NNN.md` file, it must also add the matching one-line entry to `log.md` in the same operation.
- The skill should flag a mismatch in either direction: a `changes/` file with no `log.md` line, or a `log.md` line with no corresponding `changes/` file.

### Session workflow the skill should support

- At the start of a session: read root `index.md`, then whichever `live` files matter for the day's task, then only the specific `frozen` concept files relevant to the task, not the whole bundle.
- At the end of a session: overwrite the relevant `live` files, append one `changes/s-NNN.md`, add its one-line pointer to `log.md`, and append any new `decisions/d-NNN.md` entries plus their affected-concept links, updating whichever `index.md` files gained or lost entries.

## Open questions for the skill design, to resolve later

- Exact trigger or invocation for the skill: a slash command, or automatic on file edits under `okf/`.
- Whether the skill also validates cross-links, such as flagging a link to a concept file that does not exist, or leaves that to OKF's "tolerate broken links" permissiveness.
- Whether `changes/` and `decisions/` share one incrementing counter or are numbered independently.

## Status

This plan will be revised as the rest of the `okf/` bundle structure (model, architecture, roadmap, risks, live-state files) gets scaffolded, since the skill needs to know the full set of concept types and their mutability before it can be built.
