#!/usr/bin/env bash
# scaffold_skill.sh - deterministic filesystem scaffolding for a new Claude Code skill.
#
# Usage:
#   scripts/scaffold_skill.sh <skill-name> [--scripts] [--references] [--assets]
#
# Must be run with the project root as the current working directory (the
# directory that directly contains .agents/skills/ and .claude/skills/).
#
# Creates:
#   .agents/skills/<skill-name>/SKILL.md            (placeholder frontmatter only)
#   .agents/skills/<skill-name>/scripts/            (if --scripts requested)
#   .agents/skills/<skill-name>/references/         (if --references requested)
#   .agents/skills/<skill-name>/assets/             (if --assets requested)
#   .claude/skills/<skill-name> -> ../../.agents/skills/<skill-name>  (relative symlink)
#
# Never overwrites an existing skill. Exits non-zero with a clear message on
# any validation failure. Written for bash 3.2 (macOS default) - no
# associative arrays, no ${var,,}, no mapfile/readarray.

set -euo pipefail

usage() {
  echo "Usage: $0 <skill-name> [--scripts] [--references] [--assets]" >&2
  echo "  Must be run from the project root (the dir containing .agents/skills/ and .claude/skills/)." >&2
  exit 1
}

if [ "$#" -eq 0 ]; then
  usage
fi

SKILL_NAME=""
WANT_SCRIPTS=0
WANT_REFERENCES=0
WANT_ASSETS=0

for arg in "$@"; do
  case "$arg" in
    --scripts)
      WANT_SCRIPTS=1
      ;;
    --references)
      WANT_REFERENCES=1
      ;;
    --assets)
      WANT_ASSETS=1
      ;;
    -*)
      echo "Error: unknown flag '$arg'" >&2
      usage
      ;;
    *)
      if [ -n "$SKILL_NAME" ]; then
        echo "Error: multiple skill names given ('$SKILL_NAME' and '$arg')" >&2
        usage
      fi
      SKILL_NAME="$arg"
      ;;
  esac
done

if [ -z "$SKILL_NAME" ]; then
  echo "Error: missing <skill-name>" >&2
  usage
fi

# --- Validate name: lowercase kebab-case only, e.g. 'my-new-skill' ---
if ! printf '%s' "$SKILL_NAME" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$'; then
  echo "Error: '$SKILL_NAME' is not a valid skill name." >&2
  echo "Skill names must be lowercase kebab-case, e.g. 'my-new-skill'." >&2
  exit 1
fi

# --- Confirm we are at the project root ---
if [ ! -d ".agents/skills" ] || [ ! -d ".claude/skills" ]; then
  echo "Error: must be run from the project root (the directory containing" >&2
  echo "both .agents/skills/ and .claude/skills/). Current directory:" >&2
  echo "  $(pwd)" >&2
  exit 1
fi

AGENTS_SKILL_DIR=".agents/skills/${SKILL_NAME}"
CLAUDE_SKILL_LINK=".claude/skills/${SKILL_NAME}"

# --- Collision checks (catch real files/dirs AND broken/dangling symlinks) ---
if [ -e "$AGENTS_SKILL_DIR" ] || [ -L "$AGENTS_SKILL_DIR" ]; then
  echo "Error: '$AGENTS_SKILL_DIR' already exists. Refusing to overwrite an existing skill." >&2
  exit 1
fi

if [ -e "$CLAUDE_SKILL_LINK" ] || [ -L "$CLAUDE_SKILL_LINK" ]; then
  echo "Error: '$CLAUDE_SKILL_LINK' already exists. Refusing to overwrite an existing skill." >&2
  exit 1
fi

# --- Create the real skill directory + placeholder SKILL.md ---
mkdir -p "$AGENTS_SKILL_DIR"

cat > "$AGENTS_SKILL_DIR/SKILL.md" <<EOF
---
name: ${SKILL_NAME}
description:
---
EOF

# --- Create only the requested bundled-resource subfolders ---
if [ "$WANT_SCRIPTS" -eq 1 ]; then
  mkdir -p "$AGENTS_SKILL_DIR/scripts"
fi
if [ "$WANT_REFERENCES" -eq 1 ]; then
  mkdir -p "$AGENTS_SKILL_DIR/references"
fi
if [ "$WANT_ASSETS" -eq 1 ]; then
  mkdir -p "$AGENTS_SKILL_DIR/assets"
fi

# --- Symlink .claude/skills/<name> -> ../../.agents/skills/<name> (relative) ---
mkdir -p ".claude/skills"
ln -s "../../.agents/skills/${SKILL_NAME}" "$CLAUDE_SKILL_LINK"

# --- Report the resulting tree ---
echo "Created skill '${SKILL_NAME}':"
echo
find "$AGENTS_SKILL_DIR" | sort
echo
echo "Symlink:"
ls -l "$CLAUDE_SKILL_LINK"
echo
echo "Resolved target:"
readlink "$CLAUDE_SKILL_LINK"
