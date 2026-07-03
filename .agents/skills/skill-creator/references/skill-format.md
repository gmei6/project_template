# Claude Code Skill Anatomy Reference

## Directory structure

```
skill-name/
├── SKILL.md (required)
│   ├── YAML frontmatter (name, description required)
│   └── Markdown instructions
└── Bundled Resources (optional)
    ├── scripts/    - Executable code for deterministic/repetitive tasks
    ├── references/ - Docs loaded into context as needed
    └── assets/     - Files used in output (templates, icons, fonts)
```

In this project, the *real* skill files live under `.agents/skills/<name>/`
(Claude Code does not natively scan this path). `.claude/skills/<name>` is a
relative symlink to `../../.agents/skills/<name>` — that symlink is what
makes Claude Code actually discover and load the skill. Always create both
in lockstep; never create one without the other.

## Frontmatter requirements

- `name` — required, lowercase kebab-case, must match the skill's directory name.
- `description` — required, a single sentence written in the third person
  that states **when to trigger** the skill, not just what it does. Claude
  Code decides whether to load a skill largely from this line alone, before
  ever reading the body — so include concrete trigger phrases/example user
  requests, not just a summary of functionality.

## Body conventions

- Start with a top-level heading: `# <Skill Name> Skill Instructions`.
- Follow with one short paragraph stating when/why to invoke this skill's logic.
- Then a `## Steps` section: a numbered, imperative list of concrete actions.
- Keep the body **short**. SKILL.md is loaded into context whenever the
  skill triggers, so push any detail that isn't needed every time into
  `references/` (loaded on demand) instead of bloating SKILL.md. This is
  "progressive disclosure."

## Bundled resources — when to use each

- `scripts/` — executable code for deterministic, repeatable tasks (e.g.
  filesystem setup, validation) that the model should shell out to rather
  than re-derive by hand each time.
- `references/` — reference docs and specs loaded into context only when
  the skill actually needs them.
- `assets/` — non-instructional files consumed in the *output* of a task
  (templates, icons, fonts, boilerplate copied into a deliverable).
- All three are optional. Do not create empty/unused subfolders — only
  create the ones a skill genuinely needs.

## Example: `read_knowledge` (style template)

```
---
name: read_knowledge
description: Allows the agent to scan and query the OKF knowledge bundle for relevant concepts.
---

# read_knowledge Skill Instructions

Use this skill's logic when starting a task to traverse `knowledge/index.md` and read matched concepts.

## Steps
1. Perform a directory scan of `knowledge/`.
2. Grep files in `knowledge/` for matching keyword indexes.
3. Incorporate past lessons directly into thinking buffers.
```

What makes this a good example to imitate:
- The `description` states the trigger condition ("when starting a task"),
  not just the mechanism.
- Each step is a short, concrete, imperative action — no filler.
- There is no unnecessary bundled-resource folder; it's a plain SKILL.md.
