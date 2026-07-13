#!/usr/bin/env bash
# Validate that every precommit/*.yaml template exists and is a well-formed
# pre-commit config (offline; validate-config does not fetch the hook repos).
set -o errexit
set -o nounset
set -o pipefail

cd "$(dirname "$0")/.."

names=(base terraform go ansible)
fail=0
for n in "${names[@]}"; do
  f="precommit/${n}.yaml"
  if [[ ! -f "$f" ]]; then
    echo "MISSING: $f"
    fail=1
    continue
  fi
  if pre-commit validate-config "$f"; then
    echo "OK: $f"
  else
    echo "INVALID: $f"
    fail=1
  fi
done
exit "$fail"
