#!/usr/bin/env bash
#
# Bootstrap a repo onto the methridge/taskfiles standard: lay down the generic
# root Taskfile.yaml, the shared task files + scripts under .taskfiles/shared/,
# a .taskfiles/project/project.yml stub, and a committed .taskfiles/config
# recording what was vendored/installed. Idempotent - never clobbers an
# existing project.yml, .pre-commit-config.yaml, .claude/settings.json, or
# .taskfiles/config.
#
# Usage (served from the latest GitHub Release):
#   curl -fsSL https://github.com/methridge/taskfiles/releases/latest/download/init.sh \
#     | bash -s -- [REF] [extra shared files...]
# REF (first positional, else $TASKFILES_REF) defaults to "latest", which resolves
# to the newest vX.Y.Z tag. Pass an explicit tag to pin. Extra shared files come
# AFTER the ref.
# Examples:
#   ... | bash                         # latest: git.yml + scripts
#   ... | bash -s -- latest go.yml     # latest, also vendor go.yml
#   ... | bash -s -- v1.0.0            # pin to v1.0.0

set -o errexit
set -o nounset
set -o pipefail

REPO="https://github.com/methridge/taskfiles"

REF="${1:-${TASKFILES_REF:-latest}}"
shift || true

if [[ "$REF" != "latest" && "$REF" != v* ]]; then
  echo "First arg is the version ref (v1.0.0 or 'latest'); got '${REF}'." >&2
  echo "Extra shared files go after the ref: ... | bash -s -- latest go.yml" >&2
  exit 1
fi

if [[ "$REF" == "latest" ]]; then
  REF="$(git ls-remote --tags --refs --sort=-v:refname "${REPO}.git" 'v*' 2>/dev/null \
    | sed -n '1s#.*/##p' || true)"
  if [[ -z "$REF" ]]; then
    echo "Could not resolve a latest tag from ${REPO} (no releases yet?)." >&2
    echo "Pass one explicitly, e.g.  ... | bash -s -- v1.0.0" >&2
    exit 1
  fi
fi

BASE="${TASKFILES_BASE:-https://raw.githubusercontent.com/methridge/taskfiles/${REF}}"

# Pull optional `precommit=NAME` and `claude=PROFILE` tokens out of the args so
# they are not treated as extra shared task files. precommit defaults to the
# base template (`none` opts out); claude is opt-in and defaults to `none`.
PRECOMMIT="base"
CLAUDE_PROFILE="none"
# Track what this invocation actually did (not just what was requested), so
# the .taskfiles/config we write at the end never claims something skipped
# because a file already existed.
PRECOMMIT_INSTALLED=""
CLAUDE_PROFILE_INSTALLED=""
REST=()
for a in "$@"; do
  case "$a" in
    precommit=*) PRECOMMIT="${a#precommit=}" ;;
    claude=*) CLAUDE_PROFILE="${a#claude=}" ;;
    *) REST+=("$a") ;;
  esac
done
set -- "${REST[@]+"${REST[@]}"}"

SHARED=(git.yml scripts/lib.sh scripts/merge.sh scripts/review.sh "$@")

echo "Bootstrapping from methridge/taskfiles @ ${REF}"

mkdir -p .taskfiles/shared/scripts .taskfiles/project

curl -fsSL "${BASE}/Taskfile.yaml" -o Taskfile.yaml

for f in "${SHARED[@]}"; do
  mkdir -p ".taskfiles/shared/$(dirname "$f")"
  curl -fsSL "${BASE}/.taskfiles/shared/${f}" -o ".taskfiles/shared/${f}"
  case "$f" in *.sh) chmod +x ".taskfiles/shared/${f}" ;; esac
done

if [[ ! -f .taskfiles/project/project.yml ]]; then
  cat > .taskfiles/project/project.yml <<'EOF'
# yaml-language-server: $schema=https://taskfile.dev/schema.json
# https://taskfile.dev
#
# Project-specific tasks (repo-owned; `task sync` never touches this file).

version: "3"

tasks: {}
EOF
fi

if [[ "$PRECOMMIT" != "none" ]]; then
  if [[ -f .pre-commit-config.yaml ]]; then
    echo "Keeping existing .pre-commit-config.yaml (left untouched)."
  else
    tmp="$(mktemp)"
    if curl -fsSL "${BASE}/precommit/${PRECOMMIT}.yaml" -o "$tmp"; then
      mv "$tmp" .pre-commit-config.yaml
      echo "Installed .pre-commit-config.yaml (precommit=${PRECOMMIT})."
      PRECOMMIT_INSTALLED="$PRECOMMIT"
    else
      rm -f "$tmp"
      echo "Unknown precommit template '${PRECOMMIT}'." >&2
      echo "Valid: base, terraform, go, ansible, none." >&2
      exit 1
    fi
  fi
fi

if [[ "$CLAUDE_PROFILE" != "none" ]]; then
  if [[ -f .claude/settings.json ]]; then
    echo "Keeping existing .claude/settings.json (left untouched)."
  else
    tmp="$(mktemp)"
    if curl -fsSL "${BASE}/claude/${CLAUDE_PROFILE}.json" -o "$tmp"; then
      mkdir -p .claude
      mv "$tmp" .claude/settings.json
      echo "Installed .claude/settings.json (claude=${CLAUDE_PROFILE})."
      CLAUDE_PROFILE_INSTALLED="$CLAUDE_PROFILE"
    else
      rm -f "$tmp"
      echo "Unknown claude profile '${CLAUDE_PROFILE}'." >&2
      echo "Valid: terraform, packer, claude-config, none." >&2
      exit 1
    fi
  fi

  # Optional per-profile MCP server (claude/<profile>.mcp.json upstream).
  # Same never-clobber treatment as .claude/settings.json above: an existing
  # ./.mcp.json is always kept. Most profiles have no .mcp.json at all - a
  # fetch failure there is normal and silent, not an error.
  if [[ -f .mcp.json ]]; then
    echo "Keeping existing .mcp.json (left untouched)."
  else
    mcp_tmp="$(mktemp)"
    if curl -fsSL "${BASE}/claude/${CLAUDE_PROFILE}.mcp.json" -o "$mcp_tmp" 2>/dev/null; then
      mv "$mcp_tmp" .mcp.json
      echo "Installed .mcp.json (claude=${CLAUDE_PROFILE})."
    else
      rm -f "$mcp_tmp"
    fi
  fi
fi

# .taskfiles/config is the committed record of the choices this bootstrap
# made (superset of the old .taskfiles/claude-profile marker, removed in
# v1.4.0). Only record what this invocation actually did: if an existing
# .claude/settings.json or .pre-commit-config.yaml was left untouched above,
# CLAUDE_PROFILE_INSTALLED / PRECOMMIT_INSTALLED stay empty, so we never
# claim credit for a file we didn't write. TASKFILES_REF is deliberately not
# recorded here - it is already stamped into Taskfile.yaml's sync default by
# `task release`; a second copy could disagree with the authoritative one.
if [[ -f .taskfiles/config ]]; then
  echo "Keeping existing .taskfiles/config (left untouched)."
else
  mkdir -p .taskfiles
  {
    echo "# Committed methridge/taskfiles config for this repo (see STANDARD.md)."
    echo "# Loaded by the root Taskfile's \`dotenv:\` directive."
    printf 'TASKFILES_FILES="%s"\n' "${SHARED[*]}"
    if [[ -n "$CLAUDE_PROFILE_INSTALLED" ]]; then
      printf 'TASKFILES_CLAUDE_PROFILE="%s"\n' "$CLAUDE_PROFILE_INSTALLED"
    fi
    if [[ -n "$PRECOMMIT_INSTALLED" ]]; then
      # Record only - PRECOMMIT names the template that seeded
      # .pre-commit-config.yaml. That file is repo-owned and hand-tunable;
      # `task sync` never reads this key or touches the file again.
      printf 'PRECOMMIT="%s"\n' "$PRECOMMIT_INSTALLED"
    fi
  } > .taskfiles/config
  echo "Wrote .taskfiles/config."
fi

echo "Initialized methridge/taskfiles @ ${REF}. Run: task --list-all"
