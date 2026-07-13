#!/usr/bin/env bash
# Integration test for init.sh precommit handling. Runs init.sh against the
# local working-tree checkout via a file:// base, so it exercises the branch
# under development (not the published release).
set -o errexit
set -o nounset
set -o pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
INIT="${REPO}/init.sh"
BASE="file://${REPO}"

pass=0
fail=0
report() { # $1 desc, $2 = "ok"/"no"
  if [[ "$2" == "ok" ]]; then
    echo "PASS: $1"
    pass=$((pass + 1))
  else
    echo "FAIL: $1"
    fail=$((fail + 1))
  fi
}

run() { # runs init.sh in a fresh temp dir; args passed through; echoes the dir
  local work
  work="$(mktemp -d)"
  ( cd "$work" && TASKFILES_BASE="$BASE" bash "$INIT" v1.0.0 "$@" ) >/dev/null 2>&1
  echo "$work"
}

# default -> base template, has large-files hook, no terraform hooks
w="$(run)"
if [[ -f "$w/.pre-commit-config.yaml" ]] && grep -q check-added-large-files "$w/.pre-commit-config.yaml"; then
  report "default installs base" ok
else
  report "default installs base" no
fi
if grep -q terraform_fmt "$w/.pre-commit-config.yaml" 2>/dev/null; then
  report "base has no terraform" no
else
  report "base has no terraform" ok
fi

# precommit=terraform -> terraform hooks present
w="$(run precommit=terraform)"
if grep -q terraform_fmt "$w/.pre-commit-config.yaml" 2>/dev/null; then
  report "terraform template installs tf hooks" ok
else
  report "terraform template installs tf hooks" no
fi

# precommit=go alongside go.yml shared file -> both land, token not a shared file
w="$(run go.yml precommit=go)"
if [[ -f "$w/.taskfiles/shared/go.yml" ]] && grep -q golangci-lint "$w/.pre-commit-config.yaml"; then
  report "go token + go.yml both land" ok
else
  report "go token + go.yml both land" no
fi

# precommit=none -> no config written
w="$(run precommit=none)"
if [[ ! -f "$w/.pre-commit-config.yaml" ]]; then
  report "none opts out" ok
else
  report "none opts out" no
fi

# unknown name -> non-zero exit and no leftover config file
work="$(mktemp -d)"
if ( cd "$work" && TASKFILES_BASE="$BASE" bash "$INIT" v1.0.0 precommit=bogus ) >/dev/null 2>&1; then
  report "unknown name fails" no
elif [[ ! -f "$work/.pre-commit-config.yaml" ]]; then
  report "unknown name fails cleanly" ok
else
  report "unknown name leaves no file" no
fi

# existing config is never clobbered
work="$(mktemp -d)"
printf 'SENTINEL\n' > "$work/.pre-commit-config.yaml"
( cd "$work" && TASKFILES_BASE="$BASE" bash "$INIT" v1.0.0 ) >/dev/null 2>&1
if grep -q SENTINEL "$work/.pre-commit-config.yaml"; then
  report "existing config preserved" ok
else
  report "existing config preserved" no
fi

echo "----"
echo "pass=$pass fail=$fail"
exit "$fail"
