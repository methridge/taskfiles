#!/usr/bin/env bash
#
# Bootstrap a repo onto the methridge/taskfiles standard: lay down the generic
# root Taskfile.yaml, the shared task files + scripts under .taskfiles/shared/,
# and a .taskfiles/project/project.yml stub. Idempotent — never clobbers an
# existing project.yml.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/methridge/taskfiles/v1.0.0/init.sh \
#     | bash -s -- [REF] [extra shared files...]
# REF may also come from the TASKFILES_REF env var (positional arg wins).
# Examples:
#   ... | bash -s -- v1.0.0            # base: git.yml + scripts
#   ... | bash -s -- v1.0.0 go.yml     # also vendor go.yml

set -o errexit
set -o nounset
set -o pipefail

REF="${1:-${TASKFILES_REF:-v1.0.0}}"
shift || true
BASE="https://raw.githubusercontent.com/methridge/taskfiles/${REF}"
SHARED=(git.yml scripts/lib.sh scripts/merge.sh scripts/review.sh "$@")

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
