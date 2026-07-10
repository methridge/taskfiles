#!/usr/bin/env bash
#
# Bootstrap a repo onto the methridge/taskfiles standard: lay down the generic
# root Taskfile.yaml, the shared task files + scripts under .taskfiles/shared/,
# and a .taskfiles/project/project.yml stub. Idempotent — never clobbers an
# existing project.yml.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/methridge/taskfiles/main/init.sh \
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

BASE="https://raw.githubusercontent.com/methridge/taskfiles/${REF}"
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

echo "Initialized methridge/taskfiles @ ${REF}. Run: task --list-all"
