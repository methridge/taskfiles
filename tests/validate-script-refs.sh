#!/usr/bin/env bash
# Validate that every script reachable from the vendored taskfiles is actually
# delivered to consumers. "Reachable" is transitive: a script referenced
# directly by a .taskfiles/shared/*.yml task (hop 1), or sourced by another
# reachable script (hop 2+, e.g. lib.sh, which no .yml references directly -
# only merge.sh and review.sh `source` it) - both count. A script missing
# from delivery breaks whatever task calls it fleet-wide the moment a
# consumer runs `task sync` or `init.sh` (see the v1.6.2 push.sh incident).
set -o errexit
set -o nounset
set -o pipefail

cd "$(dirname "$0")/.."

SCRIPTS_DIR=".taskfiles/shared/scripts"

# --- Hop 1: scripts referenced directly by any vendored *.yml taskfile -----
reachable=()
add_reachable() { # $1 = script basename, e.g. "lib.sh"
  local name="$1" existing
  for existing in "${reachable[@]}"; do
    [[ "$existing" == "$name" ]] && return
  done
  reachable+=("$name")
}

while IFS= read -r ref; do
  [[ -n "$ref" ]] && add_reachable "$(basename "$ref")"
done < <(grep -hoE "${SCRIPTS_DIR}/[A-Za-z0-9_.-]+\.sh" .taskfiles/shared/*.yml 2>/dev/null | sort -u)

# --- Hop 2+: transitively follow real `source`/`.` statements inside each --
# reachable script, to a fixed point, so a script only ever reached through
# another script (like lib.sh) is still caught. Keys off actual source/. command
# lines, not `# shellcheck source=` comments above them, so neither one
# changing alone can fool this.
changed=1
while [[ "$changed" -eq 1 ]]; do
  changed=0
  for name in "${reachable[@]}"; do
    f="${SCRIPTS_DIR}/${name}"
    [[ -f "$f" ]] || continue
    # shellcheck disable=SC2016 # single-quoted regex chars, not expansion
    while IFS= read -r sourced; do
      [[ -z "$sourced" ]] && continue
      base="$(basename "$sourced")"
      already=0
      for existing in "${reachable[@]}"; do
        [[ "$existing" == "$base" ]] && already=1 && break
      done
      if [[ "$already" -eq 0 ]]; then
        reachable+=("$base")
        changed=1
      fi
    done < <(grep -E '^[[:space:]]*(source|\.)[[:space:]]+' "$f" 2>/dev/null \
              | grep -oE '[A-Za-z0-9_./${}-]+\.sh' || true)
  done
done

# --- Delivery lists to check against ----------------------------------------
taskfile_default="$(grep -m1 'TASKFILES_FILES:' Taskfile.yaml | sed -E 's/.*default "([^"]*)".*/\1/')"
init_shared="$(grep -m1 '^SHARED=(' init.sh | sed -E 's/^SHARED=\(([^)]*)\).*/\1/; s/"\$@"//')"
config_files=""
if [[ -f .taskfiles/config ]] && grep -q '^TASKFILES_FILES=' .taskfiles/config; then
  config_files="$(grep -m1 '^TASKFILES_FILES=' .taskfiles/config | sed -E 's/^TASKFILES_FILES="([^"]*)".*/\1/')"
fi

list_contains() { # $1 = space-separated list, $2 = item
  local list=" $1 " item="$2"
  [[ "$list" == *" $item "* ]]
}

fail=0
for name in "${reachable[@]}"; do
  rel="scripts/${name}"
  path="${SCRIPTS_DIR}/${name}"

  if [[ -f "$path" ]]; then
    echo "OK: ${path} exists on disk"
  else
    echo "MISSING: ${path} does not exist on disk (referenced but never created)"
    fail=1
    continue
  fi

  if list_contains "$taskfile_default" "$rel"; then
    echo "OK: ${rel} listed in Taskfile.yaml's TASKFILES_FILES default"
  else
    echo "MISSING: ${rel} not in Taskfile.yaml's TASKFILES_FILES default - task sync will not deliver it to consumers"
    fail=1
  fi

  if list_contains "$init_shared" "$rel"; then
    echo "OK: ${rel} listed in init.sh's SHARED array"
  else
    echo "MISSING: ${rel} not in init.sh's SHARED array - a fresh bootstrap will not deliver it"
    fail=1
  fi

  if [[ -n "$config_files" ]]; then
    if list_contains "$config_files" "$rel"; then
      echo "OK: ${rel} listed in this repo's own .taskfiles/config TASKFILES_FILES"
    else
      echo "MISSING: ${rel} not in this repo's own .taskfiles/config TASKFILES_FILES - this repo's dogfooded task sync will not deliver it to itself"
      fail=1
    fi
  fi
done

exit "$fail"
