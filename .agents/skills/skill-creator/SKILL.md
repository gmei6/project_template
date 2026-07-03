---
name: skill-creator
description: Use when the user asks to create, scaffold, bootstrap, or generate a new Claude Code skill (e.g. "create a skill for X", "make a new skill", "scaffold a skill") — interactively defines the new skill's name, purpose, and SKILL.md, and optionally its scripts/references/assets, then wires it into .agents/skills/ and .claude/skills/.
---

# skill-creator Skill Instructions

Use this skill's logic when the user wants to create a brand-new Claude Code skill. Skills in this project live in two places: real files under `.agents/skills/<name>/`, and a matching symlink under `.claude/skills/<name>` that Claude Code actually scans — see `references/skill-format.md` for the full anatomy spec and a worked example before drafting the new SKILL.md.

## Steps
1. Interview the user about the new skill: its name (confirm/derive a lowercase kebab-case slug) and its purpose (what task it helps with, and what should trigger it).
2. Ask the user, via AskUserQuestion, whether the new skill needs bundled resources (scripts, references, and/or assets) beyond a bare SKILL.md.
3. If the user wants bundled resources, ask via AskUserQuestion (multiSelect) which of scripts/, references/, and/or assets/ are needed, then briefly plan with the user what each selected folder will contain — do not create folders the user didn't ask for or can't describe a use for.
4. Read `references/skill-format.md` for the exact anatomy, frontmatter rules, and the `read_knowledge` style example before drafting content.
5. Run `scripts/scaffold_skill.sh <skill-name> [--scripts] [--references] [--assets]` from the project root to create `.agents/skills/<skill-name>/` (with only the requested subfolders and a placeholder SKILL.md) and the `.claude/skills/<skill-name>` symlink. Do not hand-create these paths; the script contains the validation and collision checks.
6. Overwrite the placeholder `.agents/skills/<skill-name>/SKILL.md` with the full drafted frontmatter (real `name` and a one-sentence `description` that states when to trigger the skill) and a body following the `# <Skill> Skill Instructions` + `## Steps` convention from `references/skill-format.md`.
7. Populate any requested `scripts/`, `references/`, or `assets/` folders with the content planned in step 3 (mark scripts executable with `chmod +x`).
8. Report the final structure back to the user (e.g. via `find .agents/skills/<skill-name>`) and confirm the `.claude/skills/<skill-name>` symlink resolves correctly.
