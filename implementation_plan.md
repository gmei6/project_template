# Blueprint & Implementation Plan: 6_22_template Git Repository Template

This document provides a complete, high-specificity blueprint for converting the `6_22_template` folder into a standardized template repository for human-agent collaboration.

---

## 1. Directory Structure

Below is the complete layout map for the template repository:

```
6_22_template/
├── GEMINI.md                    # Pointer file for Gemini/Antigravity
├── CLAUDE.md                    # Pointer file for Claude Code/Desktop
├── AGENT.md                     # Unified master instructions for all agents
├── PROJECT_TRACKER.md           # Template for keeping projects on track
├── PROPOSALS_QUEUE.md           # Index file for agent change proposals
├── README.md                    # Repository documentation for humans
├── LICENSE                      # MIT License
├── .gitignore                   # Standard Python ignore rules
│
├── .agents/                     # Antigravity customization folder
│   ├── AGENTS.md                # Antigravity-specific rules referencing AGENT.md
│   └── skills/                  # Antigravity custom skills
│       ├── read_knowledge/      # Skill: scanning the OKF knowledge bundle
│       │   └── SKILL.md
│       ├── submit_proposal/     # Skill: creating and queuing proposals
│       │   └── SKILL.md
│       └── verify_proposal/     # Skill: reviewing, applying/rejecting, and logging a pending proposal
│           └── SKILL.md
│
├── skills/                      # Claude Code-native skills (auto-loaded by Claude Code)
│   ├── read_knowledge/          # Same skill as .agents/skills/, Claude Code SKILL.md format
│   │   └── SKILL.md
│   ├── submit_proposal/
│   │   └── SKILL.md
│   └── verify_proposal/
│       └── SKILL.md
│
├── rules/                       # Thinking & Coding style rule placeholders
│   ├── caveman.md                # Placeholder for 'caveman' thinking rules
│   └── ponytail.md               # Placeholder for 'ponytail' coding rules
│
├── proposals/                   # Directory for active agent proposals
│   ├── template.md              # Proposal template
│   └── example_proposal.md      # Example proposal showing diff/details
│
├── src/                          # Sample application source (target of the example proposal)
│   ├── app.py
│   └── config.py
│
├── tests/                        # Sample test suite (verifies the example proposal's fix)
│   └── test_config.py
│
└── knowledge/                    # Operator Knowledge Format (OKF) Bundle
    ├── index.md                  # Root directory index of knowledge concepts
    ├── log.md                    # Log of knowledge creation/updates
    ├── templates/
    │   └── concept.md            # Template for a new OKF concept
    └── lessons/                  # Category: past lessons and mistakes
        └── example_lesson.md     # Example of a recorded mistake/fix
```

> **Note on `proposals/` and `PROPOSALS_QUEUE.md`**: these two locations are the primary sanctioned exception to the no-direct-edit rule, available to any proposing agent (see Section 2.1, `AGENT.md` §4). A second, narrower exception exists only for the verifying role: after completing the `verify_proposal` procedure (Section 2.6) on a specific `Pending` proposal, it may write to that proposal's target files, `PROPOSALS_QUEUE.md`, `PROJECT_TRACKER.md`, and `knowledge/log.md`. Every other file in this tree, and every other agent role, remains off-limits for direct edits.

> **Note on links**: all cross-file references inside the templated markdown use **relative** links (e.g. `[AGENT.md](./AGENT.md)`), not absolute `file://` paths, so the template still works correctly after being cloned or copied to a different machine or path.

---

## 2. File Blueprints

This section contains the exact contents for each template file.

### 2.1 Pointer Files & Unified Guidelines

#### `GEMINI.md`
```markdown
# GEMINI.md - Instructions for Gemini / Antigravity

Welcome, Gemini/Antigravity Agent. Before proceeding with any task in this workspace, you MUST read and follow the unified agent guidelines.

## Required Actions

1. **Read Unified Guidelines**: Open and read the contents of [AGENT.md](./AGENT.md) immediately.
2. **Follow the Canary Protocol**: You MUST start every message, response, or output you send to the user with the configured canary prefix (default: `Gary - `, with a single space after the hyphen). See [AGENT.md](./AGENT.md) §1 for how this is configured.
3. **Execute Rules and Queue**: Ensure you scan the OKF bundle in `knowledge/`, check `PROJECT_TRACKER.md`, follow style guidelines in `rules/`, and write all proposed modifications to the queue in `proposals/` and `PROPOSALS_QUEUE.md`.
```

#### `CLAUDE.md`
```markdown
# CLAUDE.md - Instructions for Claude

Welcome, Claude Agent. Before proceeding with any task in this workspace, you MUST read and follow the unified agent guidelines.

## Required Actions

1. **Read Unified Guidelines**: Open and read the contents of [AGENT.md](./AGENT.md) immediately.
2. **Follow the Canary Protocol**: You MUST start every message, response, or output you send to the user with the configured canary prefix (default: `Gary - `, with a single space after the hyphen). See [AGENT.md](./AGENT.md) §1 for how this is configured.
3. **Execute Rules and Queue**: Ensure you scan the OKF bundle in `knowledge/`, check `PROJECT_TRACKER.md`, follow style guidelines in `rules/`, and write all proposed modifications to the queue in `proposals/` and `PROPOSALS_QUEUE.md`.
```

#### `AGENT.md`
```markdown
# AGENT.md - Master Agent Guidelines

Welcome, Agent. This file is your master configuration and operating procedure. You MUST adhere to the guidelines below for every interaction, decision, and code modification.

---

## 1. The Canary Protocol (CRITICAL)

> [!IMPORTANT]
> **You MUST start every single message or response you send to the user with a fixed canary prefix.**
>
> The canary prefix is configurable per project. Unless overridden below, the default prefix is:
> `Gary - `
>
> *(Exactly as written: capital G, lowercase ary, followed by a space, a hyphen, and another space.)*
> This rule serves as a "canary in the coal mine." If you fail to prefix your message with the configured canary, it indicates your context window is degrading or system prompts are being ignored, and you must self-correct immediately.

**Current configured prefix for this project**: `Gary - `
*(To change the canary for a new project, edit this line — it is the single source of truth all pointer files defer to.)*

---

## 2. Before You Think or Act (Workflow Order)

Before taking any actions, executing commands, or proposing edits:

1. **Scan the OKF Knowledge Bundle**:
   - Navigate to the [knowledge/](./knowledge/) folder.
   - Scan [knowledge/index.md](./knowledge/index.md) and concept files to see if any tags, terms, or historical logs match your current task.
   - If a match is found, read the corresponding concept file to learn from past mistakes and see what has worked in the past.
2. **Review Project State**:
   - Read [PROJECT_TRACKER.md](./PROJECT_TRACKER.md) to understand current goals, milestones, and task statuses.
3. **Load the Style Rules**:
   - Read [rules/caveman.md](./rules/caveman.md) to learn how you must structure your thinking.
   - Read [rules/ponytail.md](./rules/ponytail.md) to learn how you must format and write code.

---

## 3. Thinking & Coding Modes

* **Thinking (Caveman Style)**: You must follow the instructions in [rules/caveman.md](./rules/caveman.md). Generally, this requires explicit, raw, simple, step-by-step thinking before writing code.
* **Coding (Ponytail Style)**: You must follow the instructions in [rules/ponytail.md](./rules/ponytail.md). Generally, this requires clean, modular, highly styled, and robust code.

---

## 4. The Change Proposal Queue (NO DIRECT EDITS)

> [!WARNING]
> **Do NOT edit any file directly.** This restriction applies to *every* file in this repository — application source code, `rules/`, `knowledge/`, `PROJECT_TRACKER.md`, pointer files, everything — with exactly two narrow exceptions, both below.
>
> **Exception 1 (proposing)**: writing a new file inside [proposals/](./proposals/) and appending a row to [PROPOSALS_QUEUE.md](./PROPOSALS_QUEUE.md) are the sanctioned mechanism *for proposing* changes. Any agent may write to these two locations directly — without this exception, no proposal could ever be submitted.
>
> **Exception 2 (verifying)**: an agent acting in the verifying role — and only while running the [`verify_proposal`](./skills/verify_proposal/SKILL.md) procedure against one specific `Pending` proposal it did not author — may write directly to `PROPOSALS_QUEUE.md`, `PROJECT_TRACKER.md`, and `knowledge/log.md` to record the outcome. It does **not** write to the proposal's target files itself: that write (applying or rejecting the diff, and running the tests) happens inside a freshly spawned subagent with no access to the calling agent's conversation history (see `verify_proposal` Steps 2–3). The calling agent only relays the subagent's verdict into the logs. This split is what prevents the agent that authored a proposal from also being the context that judges and applies it — even if it later runs `verify_proposal` against its own work. This exception is scoped to the one proposal under review and never applies to the proposal's own author.

Instead, follow this validation queue flow:
1. Create a detailed markdown proposal file inside the [proposals/](./proposals/) directory. Name your file `proposal_YYYYMMDD_<short_description>.md` using the format in [proposals/template.md](./proposals/template.md).
2. Append your proposed change as a new row in the [PROPOSALS_QUEUE.md](./PROPOSALS_QUEUE.md) index file. Assign the next **sequential, zero-padded** ID (e.g. if the last row is `01`, yours is `02`). If your chosen ID turns out to already be claimed by another proposal (e.g. a concurrent submission), do not silently renumber either one — follow the collision-resolution rule at the top of [PROPOSALS_QUEUE.md](./PROPOSALS_QUEUE.md) instead.
3. Mark its status as `Pending`.
4. Wait for a human or a verifying agent to run the [`verify_proposal`](./skills/verify_proposal/SKILL.md) procedure, which reviews, tests, applies (or rejects) your diff, and logs the outcome in [PROJECT_TRACKER.md](./PROJECT_TRACKER.md) §8.

This applies to `knowledge/` too: new entries in [knowledge/log.md](./knowledge/log.md) or new files under [knowledge/lessons/](./knowledge/lessons/) are never written directly by a proposing agent — propose them through the same queue, exactly like a code change. The verifying agent appends the final `knowledge/log.md` line itself as the last step of `verify_proposal`.

---

## 5. Skills & Extension Rules

* **Skills**: the same three skills are defined twice, once per client, so each can auto-load them in its own native format:
  - [skills/](./skills/) — Claude Code-native skill format (`SKILL.md` with `name`/`description` YAML frontmatter), auto-loaded by Claude Code.
  - [.agents/skills/](./.agents/skills/) — Antigravity's equivalent, same logic, loaded via Antigravity's convention.
  If you add or change a skill, update both locations to keep them in sync.
* **Role-restricted skill**: `read_knowledge` and `submit_proposal` are available to any agent. `verify_proposal` is restricted to the verifying role and is the only skill that carries the Exception 2 write access described in §4 — never invoke it when acting as the proposing agent on your own proposal.
* **Environment-Specific Customs**: Consult `.agents/AGENTS.md` for specific instructions or tools configured for Antigravity, and `CLAUDE.md` / `GEMINI.md` for client-specific instructions.
```

---

### 2.2 Project Management & Queue

#### `PROJECT_TRACKER.md`
```markdown
# Project Tracker Template

> **Single source of truth** for this project's state. Paste this whole file into a fresh agent
> conversation before working on it, and ask the agent to return the whole updated file at the end
> (see **§11 — Update Protocol**).

- **Last updated**: YYYY-MM-DD — Session 0
- **File version**: v1.0
- **Owner**: [Name] · **Stakeholders**: [Names/roles]

---

## §0 — Session-Start Checklist

Read, in this order, before doing anything else: **§2 (North Star)** → **§5 (Current Status)** →
**§6 (Open Questions & Blockers)** → **§7 (Next Actions)** → then only the 🔒 sections relevant to
today's specific task.

**Section legend**: 🔒 **FROZEN** — the agreed direction/spec; changes only through a dated entry
in the **Decision Log (§9)** plus a minimal edit, flagged in the **Session Changelog (§10)**. 🟢
**LIVE** (§5–§7) — current state; overwrite freely each session to reflect reality, truthfully. 📜
**APPEND-ONLY** (§8–§10) — permanent record; add to the bottom, never delete or rewrite a prior
entry. If a past entry is later found wrong, append a new entry that corrects it (an "errata" entry)
rather than editing the original.

> Insert project-specific 🔒 sections (e.g. a technical spec, coding standards, a risk register)
> between §4 and §5 as the project needs them, and renumber the 🟢/📜 sections that follow.

---

## §1 — Project Identity 🔒
* **Project Name**: [Name]
* **Start Date**: YYYY-MM-DD
* **Target Launch**: YYYY-MM-DD
* **Context**: [Team/program, time budget, advisor or stakeholder contact cadence, compute/resources.]

## §2 — North Star & Scope 🔒
*This is what the project **is**. If a request would pull the work away from this or contradict a
prior Decision (§9), say so explicitly and ask before proceeding — surface the tension, don't
quietly absorb it.*
* **One-line goal**: [The high-level goal, in 1-2 sentences.]
* **Claim this**: [The specific, honest scope of the deliverable/contribution.]
* **Do NOT claim**: [Adjacent things this project explicitly is not attempting, so scope creep is
  falsifiable rather than just discouraged.]

## §3 — Milestones & Objectives 🔒
- [ ] **Milestone 1**: [Description] (Target: YYYY-MM-DD)
  - [ ] Task 1.1: [Details]
  - [ ] Task 1.2: [Details]
- [ ] **Milestone 2**: [Description] (Target: YYYY-MM-DD)

## §4 — Definition of Done 🔒
*A deliverable counts as "done" only when it meets every item below — fill in per project.*
1. [e.g. produced by a script from a committed config + logged seed]
2. [e.g. regenerates from saved raw outputs, never recomputed ad hoc for a figure/report]
3. [e.g. passes its stated validation/test]
4. Recorded in §5 and, if it resolves an open question, logged in §9.

---

## §5 — Current Status 🟢 *(overwrite each session to reflect reality)*
* **Phase**: [Current milestone/phase]
* **Done this session**: [...]
* **Active Task Queue**:

| Task ID | Description | Assigned Agent | Status | Priority | Blockers |
|---------|-------------|----------------|--------|----------|----------|
| T-101   | Example Task | None           | Todo   | High     | None     |

## §6 — Open Questions & Blockers 🟢 *(overwrite each session)*
* **Blockers**: [None / list]
* **Open Questions**: [...]

## §7 — Next Actions 🟢 *(overwrite each session — keep it to the next few concrete steps)*
1. [...]
2. [...]

---

## §8 — Proposal Verification Log 📜 *(APPEND-ONLY)*
*Populated by the verifying agent's `verify_proposal` skill (see [AGENT.md](./AGENT.md) §4) — one
row per proposal reviewed, regardless of outcome. Never edit or delete a row; if a past verdict was
wrong, append a new row correcting it.*
| Proposal ID | Date Reviewed | Verifier | Tests Run | Result | Notes |
|-------------|---------------|----------|-----------|--------|-------|
| 01 | YYYY-MM-DD | [Agent/Human] | `pytest tests/` | Approved | Example row format |

## §9 — Decision Log 📜 *(APPEND-ONLY — newest at the bottom; never edit prior entries)*
> Format: `D-NNN | YYYY-MM-DD | Decision | Rationale | Affects §`. Any change to a 🔒 section
> requires an entry here. Correct a wrong past entry with a new entry, not an edit (e.g.
> `D-004 | ... | ERRATA correcting D-002 | ... | ...`).
- `D-001 | YYYY-MM-DD | [Decision] | [Why] | [§ affected]`

## §10 — Session Changelog 📜 *(APPEND-ONLY — what changed in THIS FILE each session)*
*Distinct from §9: this logs file edits, not the reasoning behind them.*
- `S-000 | YYYY-MM-DD | v1.0 | Initial tracker created.`

---

## §11 — Update Protocol (run at the end of each session)

When asked to update this file:
1. **Update the header**: bump `Last updated` and the session number; bump `File version` if any
   🔒 section changed.
2. **Rewrite §5–§7 (🟢 LIVE)** to match reality now — overwrite stale content, don't append to it.
3. **Append to §8–§10 (📜), never edit them.** Log every proposal verification (§8), every decision
   (§9), and a one-line summary of what changed in the file (§10). Correct a wrong past entry with a
   new entry, never an edit.
4. **Touch 🔒 sections only with cause**: record the decision in §9 first, make the minimal edit,
   note it in §10, and call it out explicitly in your reply (e.g. "I changed §3 because of D-004").
5. **Guard the direction**: if this session pulled the work away from §2's North Star or against a
   prior Decision, flag the tension and ask whether to record it as a deliberate pivot or set it
   aside — don't quietly fold it in.
6. **Be truthful and lean**: don't mark unfinished work done; record real blockers; keep §5–§7 tight
   (the next few steps, not a backlog dump).
```

This file stays a **fully generic, blank template** — it is reused as-is for whatever real project gets built on top of this scaffold next, rather than pre-filled with metadata about building the template itself. Project-specific 🔒 sections (model specs, coding standards, risk registers, etc.) get inserted between §4 and §5 as that next project needs them.

#### `PROPOSALS_QUEUE.md`
```markdown
# Proposals Queue

Agents are not permitted to commit edits directly to source folders. Instead, all proposed modifications must be logged here for human/agent review.

IDs are sequential and zero-padded (`01`, `02`, `03`, ...). To submit a new proposal, find the highest existing ID and increment it.

**ID collisions**: if you ever find two proposals already sharing the same ID (e.g. from concurrent submissions), do not silently renumber either one. Ask the user which of the two colliding proposals is higher priority. The higher-priority proposal keeps the contested ID; the other must be renumbered to the next free ID — updating its row here, its `proposal_YYYYMMDD_<name>.md` filename, and any cross-references to it — before work continues.

**Status values**: `Pending` (awaiting review) → `Approved` (diff applied, tests passed) | `Rejected` (diff discarded, tests failed or unsound) | `Changes Requested` (diff no longer applies cleanly; author must resubmit). Status only ever moves out of `Pending` via the verifying agent's `verify_proposal` skill, which also appends the matching row to [PROJECT_TRACKER.md](./PROJECT_TRACKER.md) §8.

| ID | Date | Proposal Document | Author Agent | Affected Files | Status | Verifier / Notes |
|----|------|-------------------|--------------|----------------|--------|------------------|
| 01 | 2026-06-22 | [proposals/example_proposal.md](./proposals/example_proposal.md) | Antigravity | `src/config.py` | Pending | Awaiting Review |
```

---

### 2.3 Style & Rules

`rules/caveman.md` and `rules/ponytail.md` are intentionally left as **empty placeholder stubs** for the user to fill in later — they are not pre-populated with rule content.

#### `rules/caveman.md`
```markdown
# Caveman Thinking Style (How to Think)

<!-- TODO: define the rules for this project's "caveman" thinking style. -->
```

#### `rules/ponytail.md`
```markdown
# Ponytail Coding Style (How to Code)

<!-- TODO: define the rules for this project's "ponytail" coding style. -->
```

---

### 2.4 Proposals Directory Templates

#### `proposals/template.md`
```markdown
# Proposal: [Short Title]

* **Date**: YYYY-MM-DD
* **Author Agent**: [Agent Name / ID]
* **Target Files**:
  - `path/to/file1.ext`

## 1. Problem Description
*Describe the issue, bug, or feature request being solved.*

## 2. Proposed Changes
*Provide details of the structural changes.*

## 3. Code Modifications (Diff Format)
```diff
- old code
+ new code
```

## 4. Verification and Testing
*Describe how the reviewer can test and verify these changes.*
```

#### `proposals/example_proposal.md`
```markdown
# Proposal: Add input validation to app configuration

* **Date**: 2026-06-22
* **Author Agent**: Antigravity
* **Target Files**:
  - `src/config.py`

## 1. Problem Description
The application configuration module crashes silently (returns `None` values) when required database environment variables are missing, instead of failing loudly.

## 2. Proposed Changes
Introduce a `required_keys` check inside `load_config` that raises `ValueError` when a required environment variable is unset.

## 3. Code Modifications (Diff Format)
```diff
 def load_config():
     import os
+    required_keys = ['DB_HOST', 'DB_PORT']
+    for key in required_keys:
+        if key not in os.environ:
+            raise ValueError(f"Missing required environment variable: {key}")
     return {
         'host': os.getenv('DB_HOST'),
         'port': os.getenv('DB_PORT')
     }
```

## 4. Verification and Testing
Run `pytest tests/test_config.py`. Before this proposal is applied, `test_load_config_raises_on_missing_env` fails because `load_config()` does not validate. After applying the diff above to `src/config.py`, both tests pass.
```

This proposal is fully runnable: `src/config.py` (Section 2.8) contains exactly the unpatched "before" state shown in the diff, and `tests/test_config.py` (Section 2.8) is a real pytest file that fails against the current code and passes once the diff is applied.

---

### 2.5 Operator Knowledge Format (OKF) Bundle

> **Naming note**: "OKF" here stands for this template's own **Operator Knowledge Format**, an internal convention for logging agent lessons and concepts. It is unrelated to Google Cloud's "Open Knowledge Format" (an open data-table format for analytics interoperability) — the shared initials are coincidental, and `knowledge/index.md` calls this out explicitly so future readers don't conflate the two.

#### `knowledge/index.md`
```markdown
# Knowledge Base Index

This bundle follows this project's own Operator Knowledge Format (OKF) v0.1 — an internal convention for logging agent lessons and concepts, unrelated to Google Cloud's "Open Knowledge Format" data-sharing spec of the same initials.

## Categories

### Lessons & Mistakes
* [knowledge/lessons/example_lesson.md](./lessons/example_lesson.md) - Record of configuration parser failure.
```

#### `knowledge/log.md`
```markdown
# Knowledge Update Log

## 2026-06-22
* **Initialization**: Set up foundational OKF structure and index.
```

#### `knowledge/templates/concept.md`
```markdown
---
type: Concept Template
title: Concept Display Name
description: One sentence summary of the concept.
tags: [tag1, tag2]
timestamp: YYYY-MM-DDTHH:MM:SSZ
---

# Details
*Provide specific details and context.*

# Examples
*Provide structural patterns or code snippets.*

# Citations
[1] [Reference link](https://example.com)
```

#### `knowledge/lessons/example_lesson.md`
```markdown
---
type: Lesson Learned
title: Context Degradation and Silent Failures
description: Lessons on resolving silent context degradation and agent loop hangs.
tags: [agent-mechanics, context-limits]
timestamp: 2026-06-22T16:15:00Z
---

# Details
Agents can fall into infinite command execution loops when context size exceeds 80% of client capacity.

# Resolution & Best Practices
1. Maintain active git proposal checks.
2. Ensure the configured canary prefix is strictly checked; its omission is the primary indicator of failure.
```

---

### 2.6 Agent Customizations (Antigravity Workspace Rules & Claude-Native Skills)

#### `.agents/AGENTS.md`
```markdown
# Antigravity Workspace Rules

These custom workspace rules are loaded automatically by Google Antigravity.

## Constraints

1. **Canary Prefix**: You MUST start every message with the configured canary prefix (default `"Gary - "`, single space after the hyphen). See root [AGENT.md](../AGENT.md) §1.
2. **Unified Instructions**: Follow the guidelines in the root [AGENT.md](../AGENT.md) at all times.
3. **Queue Enforcement**: Do not write edits directly except to `proposals/` and `PROPOSALS_QUEUE.md`. Always output proposal files to the `proposals/` folder.
```

#### `.agents/skills/read_knowledge/SKILL.md`
```yaml
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

#### `.agents/skills/submit_proposal/SKILL.md`
```yaml
---
name: submit_proposal
description: Validates and writes a new proposal code modification to the workspace queue.
---

# submit_proposal Skill Instructions

Follow this procedure when creating proposed codebase edits:

## Steps
1. Generate the proposal file `proposals/proposal_YYYYMMDD_<name>.md` following the proposal template.
2. Find the highest existing ID in `PROPOSALS_QUEUE.md` and increment it for your new row. Before appending, re-check the table for a collision — if another proposal already holds the ID you were about to use, stop and ask the user which of the two colliding proposals is higher priority. The higher-priority proposal keeps its ID; renumber the other proposal (its queue row, its filename, and any cross-references to it) to the next free ID, then proceed.
3. Append your proposed change as a new row in `PROPOSALS_QUEUE.md` using your (possibly renumbered) ID.
4. Set status to `Pending` and alert the user.
```

#### `.agents/skills/verify_proposal/SKILL.md`
```yaml
---
name: verify_proposal
description: Reviews a Pending proposal, applies or rejects its diff, runs tests, and logs the outcome. Restricted to the verifying role.
---

# verify_proposal Skill Instructions

This skill carries the one elevated write exception in `AGENT.md` §4 (Exception 2). Use it only when acting as the verifying agent on a specific proposal you did not author. Critically, you do not review the proposal yourself — you delegate that to a freshly spawned subagent so the verification happens in a context structurally independent of whoever authored the proposal.

## Steps
1. Confirm the proposal's row in `PROPOSALS_QUEUE.md` is `Pending`, and confirm you are **not** the listed `Author Agent`. Refuse to continue if you are.
2. Spawn a fresh subagent using your environment's subagent/sub-task mechanism (e.g. Claude Code's Agent/Task tool, or Antigravity's equivalent) with **no access to your current conversation history**. Hand it only the full proposal document and the current contents of each file under "Target Files".
3. Instruct the subagent to act as verifier under `AGENT.md` §4 Exception 2 for this one proposal: read the proposal in full; compare current target file contents against the "Code Modifications" diff; if the diff no longer applies cleanly, return a verdict of `Changes Requested` with reasons and stop; otherwise apply the diff, run the tests named in the proposal's "Verification and Testing" section, and return `Approved` (keeping the change) if tests pass or `Rejected` (reverting the change) if tests fail, along with the tests run and notes.
4. Receive the subagent's verdict, tests run, and notes.
5. Update the queue status in `PROPOSALS_QUEUE.md` to match the subagent's verdict.
6. Append one row to the "Proposal Verification Log" table in `PROJECT_TRACKER.md` §8 (ID, date, verifier, tests run, result, notes — drawn from the subagent's report).
7. Append one line to `knowledge/log.md` summarizing the outcome.
```

#### `skills/read_knowledge/SKILL.md`
```yaml
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

#### `skills/submit_proposal/SKILL.md`
```yaml
---
name: submit_proposal
description: Validates and writes a new proposal code modification to the workspace queue.
---

# submit_proposal Skill Instructions

Follow this procedure when creating proposed codebase edits:

## Steps
1. Generate the proposal file `proposals/proposal_YYYYMMDD_<name>.md` following the proposal template.
2. Find the highest existing ID in `PROPOSALS_QUEUE.md` and increment it for your new row. Before appending, re-check the table for a collision — if another proposal already holds the ID you were about to use, stop and ask the user which of the two colliding proposals is higher priority. The higher-priority proposal keeps its ID; renumber the other proposal (its queue row, its filename, and any cross-references to it) to the next free ID, then proceed.
3. Append your proposed change as a new row in `PROPOSALS_QUEUE.md` using your (possibly renumbered) ID.
4. Set status to `Pending` and alert the user.
```

#### `skills/verify_proposal/SKILL.md`
```yaml
---
name: verify_proposal
description: Reviews a Pending proposal, applies or rejects its diff, runs tests, and logs the outcome. Restricted to the verifying role.
---

# verify_proposal Skill Instructions

This skill carries the one elevated write exception in `AGENT.md` §4 (Exception 2). Use it only when acting as the verifying agent on a specific proposal you did not author. Critically, you do not review the proposal yourself — you delegate that to a freshly spawned subagent so the verification happens in a context structurally independent of whoever authored the proposal.

## Steps
1. Confirm the proposal's row in `PROPOSALS_QUEUE.md` is `Pending`, and confirm you are **not** the listed `Author Agent`. Refuse to continue if you are.
2. Spawn a fresh subagent using your environment's subagent/sub-task mechanism (e.g. Claude Code's Agent/Task tool, or Antigravity's equivalent) with **no access to your current conversation history**. Hand it only the full proposal document and the current contents of each file under "Target Files".
3. Instruct the subagent to act as verifier under `AGENT.md` §4 Exception 2 for this one proposal: read the proposal in full; compare current target file contents against the "Code Modifications" diff; if the diff no longer applies cleanly, return a verdict of `Changes Requested` with reasons and stop; otherwise apply the diff, run the tests named in the proposal's "Verification and Testing" section, and return `Approved` (keeping the change) if tests pass or `Rejected` (reverting the change) if tests fail, along with the tests run and notes.
4. Receive the subagent's verdict, tests run, and notes.
5. Update the queue status in `PROPOSALS_QUEUE.md` to match the subagent's verdict.
6. Append one row to the "Proposal Verification Log" table in `PROJECT_TRACKER.md` §8 (ID, date, verifier, tests run, result, notes — drawn from the subagent's report).
7. Append one line to `knowledge/log.md` summarizing the outcome.
```

> These three `skills/` files are byte-for-byte identical in content to their `.agents/skills/` counterparts — only the directory location differs, so that both Claude Code and Antigravity auto-load the same skill logic in each client's native convention.

---

### 2.7 Repository README

#### `README.md`
```markdown
# 6_22_template Repository

This repository is configured as an AI-Agent collaborative environment. It uses pointer instructions and rigid rulesets to manage interactions with agents such as Claude and Antigravity.

## Core Features
1. **Canary Protocol**: Agents are forced to prefix all messages with a configured canary (default `"Gary - "`), providing an immediate signal if model context degrades.
2. **Proposals Queue**: Direct file editing by proposing agents is disabled everywhere except `proposals/` and `PROPOSALS_QUEUE.md`. A separate verifying role runs the `verify_proposal` skill, which spawns an independent subagent (no access to the proposing conversation) to review, test, and apply (or reject) each proposal, logging the outcome in `PROJECT_TRACKER.md`'s Proposal Verification Log.
3. **OKF Knowledge base**: this template's own Operator Knowledge Format (OKF) v0.1 is used to maintain logs of errors and lessons.
4. **Style Guides**: Explicit cognitive rules ("Caveman thinking") and programming guidelines ("Ponytail coding") are stored in `rules/` as placeholders to be filled in per project.
5. **Sample App & Tests**: `src/` and `tests/` contain a minimal runnable example (`src/config.py`, `src/app.py`, `tests/test_config.py`) that the example proposal in `proposals/example_proposal.md` targets, so the proposal flow is verifiable end to end.

## License
MIT — see [LICENSE](./LICENSE).

## Getting Started
1. This repository is already an initialized git repository (see Section 3) — clone or copy it as a starting point for your project.
2. Configure agent clients to read `CLAUDE.md` or `GEMINI.md`.
```

---

### 2.8 Sample Application & Tests

These exist so that `proposals/example_proposal.md` (Section 2.4) is a real, runnable example rather than purely illustrative text.

#### `src/config.py`
```python
def load_config():
    import os
    return {
        'host': os.getenv('DB_HOST'),
        'port': os.getenv('DB_PORT')
    }
```

This is exactly the unpatched "before" state referenced by the diff in `proposals/example_proposal.md`.

#### `src/app.py`
```python
from config import load_config


def main():
    config = load_config()
    print(f"Connecting to {config['host']}:{config['port']}")


if __name__ == "__main__":
    main()
```

#### `tests/test_config.py`
```python
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

import pytest
from config import load_config


def test_load_config_raises_on_missing_env(monkeypatch):
    monkeypatch.delenv("DB_HOST", raising=False)
    monkeypatch.delenv("DB_PORT", raising=False)
    with pytest.raises(ValueError):
        load_config()


def test_load_config_succeeds_when_env_set(monkeypatch):
    monkeypatch.setenv("DB_HOST", "localhost")
    monkeypatch.setenv("DB_PORT", "5432")
    config = load_config()
    assert config == {"host": "localhost", "port": "5432"}
```

With the current (unpatched) `src/config.py`, `test_load_config_raises_on_missing_env` fails — demonstrating the bug that `proposals/example_proposal.md` proposes to fix. Applying the diff makes both tests pass.

---

### 2.9 License

#### `LICENSE`
```
MIT License

Copyright (c) 2026 Gary Mei

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

### 2.10 Git Ignore Rules

#### `.gitignore`
```
__pycache__/
*.pyc
*.pyo
*.pyd
.Python
*.egg-info/
.eggs/
.venv/
venv/
env/
.pytest_cache/
.mypy_cache/
*.log
.DS_Store
```

---

## 3. Initialization Steps

If you want to initialize the repository layout automatically, you can run the following script in your terminal inside the `6_22_template` folder:

```bash
mkdir -p rules proposals knowledge/templates knowledge/lessons \
  .agents/skills/read_knowledge .agents/skills/submit_proposal .agents/skills/verify_proposal \
  skills/read_knowledge skills/submit_proposal skills/verify_proposal \
  src tests
```

Then create each file using the templates defined above, and finally initialize git and commit the scaffold:

```bash
git init
git add .
git commit -m "Initial scaffold of 6_22_template"
```
