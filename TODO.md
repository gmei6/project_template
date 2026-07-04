# TODO

## Scaffold the `okf/` knowledge bundle for this template

Goal: build an OKF-style (Open Knowledge Format) knowledge bundle at `okf/` for this template repo, so future copies of this template carry a lightweight, progressive-disclosure project tracker instead of one monolithic markdown file.
Design worked out in conversation, informed by a real 39-session single-file tracker example (the "Two-Channel Cascade Model" project) pasted for reference, not migrated in.

Key decisions so far:
- One file per decision (`decisions/d-NNN-slug.md`) and one file per session change (`changes/s-NNN-slug.md`), both append-only.
- `log.md` (OKF's reserved changelog filename) stays terse, one line per session, linking out to the matching `changes/s-NNN.md` for the full narrative.
- A cross-cutting `mutability` frontmatter field (`frozen` / `live` / `append-only`) replaces the original tracker's 🔒/🟢/📜 emoji legend.
- All `index.md` files stay spec-lean: heading plus flat link list only, no embedded instructions or prose.
- Convention enforcement (filenames, frontmatter, frozen-edit gating, changes/log.md pairing) is being pushed into a future skill, not written into the bundle itself.
  See `okf_skill_plan.md` at repo root for the full spec of what that skill must enforce.

### Next steps

- [x] `okf/references/` - same lean treatment as decisions/ and changes/ (index.md, no example).
- [x] `okf/identity.md` and `okf/north-star.md` (kept as two separate concepts, not merged - confirmed via the cascade-model example that North Star carries substantial standalone content).
- [x] `okf/model/` directory (network-and-channels.md, notation-and-parameters.md, forks.md).
- [x] `okf/benchmark.md`.
- [x] `okf/architecture/` directory (stack.md, repo-layout.md, reproducibility.md, definition-of-done.md).
- [x] `okf/roadmap.md`, `okf/risks.md`.
- [x] Live-state files: `okf/status.md`, `okf/open-questions.md`, `okf/next-actions.md`.
- [x] Root `okf/index.md` tying the bundle together (session-start reading order, links to every top-level section/directory).
- [ ] Build the actual "edit-okf" skill per `okf_skill_plan.md` once the full bundle shape is settled.

## Fill in real content for `session-start` and `session-wrapup` skills

Goal: both skills currently exist only as anatomy, empty `name`/`description` frontmatter and empty `scripts`/`references`/`assets` folders.
They were created intentionally as structure-only stubs, but as written they don't do anything, and the Skill tool lists both as a generic "Skill" rather than by real purpose.

### Next steps

- [x] Decide what `session-start` should actually do, for example loading `AGENTS.md` conventions or checking the `lavish-axi` dashboard for open sessions, then draft it with the `skill-creator` skill.
- [x] Decide what `session-wrapup` should actually do, for example updating `CHANGELOG.md` or checking for stray artifacts, then draft it the same way.
- [x] Drop the empty `scripts`/`references`/`assets` folders under each if the finished skill doesn't end up needing them.
