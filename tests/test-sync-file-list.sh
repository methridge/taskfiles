#!/usr/bin/env bash
# Integration test for `task sync`'s shared-file list.
#
# Task resolves the `TASKFILES_FILES` var from the Taskfile.yaml already on
# disk, before any command runs - but the first thing sync does is overwrite
# that file. So a release that ADDS a shared script used to fetch the new
# git.yml that calls it while silently skipping the script itself, and only a
# second `task sync` repaired it (the v1.6.4 rollout hit this fleet-wide).
#
# The consumer here is stood up with an OLD list that predates one of the
# shared scripts; a single sync against the working tree must still deliver it.
# Runs against the local checkout via a file:// base, so it exercises the
# branch under development rather than the published release.
set -o errexit
set -o nounset
set -o pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BASE="file://${REPO}"

# The script to hide from the consumer's starting list. Any entry in the
# current default works; push.sh is the one the real incident lost.
NEW_SCRIPT="scripts/push.sh"

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

# Stands up a consumer whose Taskfile.yaml declares an older TASKFILES_FILES
# default - one that has never heard of $NEW_SCRIPT - and vendors exactly that
# older list. Echoes the directory.
make_stale_consumer() {
  local work current old
  work="$(mktemp -d)"
  cp "${REPO}/Taskfile.yaml" "${work}/Taskfile.yaml"

  current="$(sed -nE 's/.*TASKFILES_FILES \| default "([^"]*)".*/\1/p' "${work}/Taskfile.yaml" | head -1)"
  # Delimit with # - the pattern itself contains the | of `FILES | default`.
  old="$(echo " ${current} " | sed "s# ${NEW_SCRIPT} # #" | sed -E 's/^ +| +$//g')"
  sed -i.bak -E "s#(TASKFILES_FILES \| default \")[^\"]*(\")#\1${old}\2#" "${work}/Taskfile.yaml"
  rm -f "${work}/Taskfile.yaml.bak"

  local item
  for item in $old; do
    mkdir -p "${work}/.taskfiles/shared/$(dirname "$item")"
    cp "${REPO}/.taskfiles/shared/${item}" "${work}/.taskfiles/shared/${item}"
  done

  echo "$work"
}

# --- the starting state is genuinely stale ----------------------------------
w="$(make_stale_consumer)"
if grep -q "$NEW_SCRIPT" <(sed -n '/TASKFILES_FILES/p' "${w}/Taskfile.yaml"); then
  report "fixture starts without ${NEW_SCRIPT} in its list" no
else
  report "fixture starts without ${NEW_SCRIPT} in its list" ok
fi
if [[ -f "${w}/.taskfiles/shared/${NEW_SCRIPT}" ]]; then
  report "fixture starts without ${NEW_SCRIPT} on disk" no
else
  report "fixture starts without ${NEW_SCRIPT} on disk" ok
fi

# --- one sync must deliver the newly-listed script --------------------------
( cd "$w" && task sync TASKFILES_BASE="$BASE" ) >/dev/null 2>&1 || true

if [[ -f "${w}/.taskfiles/shared/${NEW_SCRIPT}" ]]; then
  report "one sync delivers ${NEW_SCRIPT}" ok
else
  report "one sync delivers ${NEW_SCRIPT}" no
fi
if [[ -x "${w}/.taskfiles/shared/${NEW_SCRIPT}" ]]; then
  report "${NEW_SCRIPT} is executable" ok
else
  report "${NEW_SCRIPT} is executable" no
fi
if grep -q "$NEW_SCRIPT" "${w}/Taskfile.yaml"; then
  report "Taskfile.yaml is refreshed to the new list" ok
else
  report "Taskfile.yaml is refreshed to the new list" no
fi

# Every other script in the current list must still land - the fix must not
# trade the missing file for a dropped one.
missing=""
for item in $(sed -nE 's/.*TASKFILES_FILES \| default "([^"]*)".*/\1/p' "${REPO}/Taskfile.yaml" | head -1); do
  [[ -f "${w}/.taskfiles/shared/${item}" ]] || missing="${missing} ${item}"
done
if [[ -z "$missing" ]]; then
  report "the whole current list is delivered" ok
else
  report "the whole current list is delivered (missing:${missing})" no
fi

# --- an explicit override still wins ----------------------------------------
w2="$(make_stale_consumer)"
( cd "$w2" && task sync TASKFILES_BASE="$BASE" TASKFILES_FILES="git.yml" ) >/dev/null 2>&1 || true
if [[ -f "${w2}/.taskfiles/shared/git.yml" ]] && [[ ! -f "${w2}/.taskfiles/shared/${NEW_SCRIPT}" ]]; then
  report "explicit TASKFILES_FILES override is honoured" ok
else
  report "explicit TASKFILES_FILES override is honoured" no
fi

echo
echo "passed: ${pass}  failed: ${fail}"
exit $((fail > 0))
