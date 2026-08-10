#!/usr/bin/env bash
# Validate that every claude/*.json profile exists, is well-formed JSON, and
# declares both the keys Claude Code needs to enable a plugin from a project.
set -o errexit
set -o nounset
set -o pipefail

cd "$(dirname "$0")/.."

names=(terraform terraform-provider packer claude-config)
fail=0
for n in "${names[@]}"; do
  f="claude/${n}.json"
  if [[ ! -f "$f" ]]; then
    echo "MISSING: $f"
    fail=1
    continue
  fi
  if ! python3 -m json.tool "$f" >/dev/null 2>&1; then
    echo "INVALID JSON: $f"
    fail=1
    continue
  fi
  if ! python3 - "$f" <<'PY'
import json, sys
path = sys.argv[1]
d = json.load(open(path))
if not isinstance(d, dict):
    print(f"{path}: profile is not a JSON object")
    sys.exit(1)
missing = [k for k in ("extraKnownMarketplaces", "enabledPlugins") if k not in d]
if missing:
    print("missing keys: " + ", ".join(missing))
    sys.exit(1)
if not isinstance(d["enabledPlugins"], dict):
    print(f"{path}: enabledPlugins is not a JSON object")
    sys.exit(1)
if not d["enabledPlugins"]:
    print("enabledPlugins is empty")
    sys.exit(1)
for name, enabled in d["enabledPlugins"].items():
    if enabled is not True:
        print(f"{path}: enabledPlugins[{name}] is not true")
        sys.exit(1)
    if "@" not in name:
        print(f"plugin key not marketplace-qualified: {name}")
        sys.exit(1)
    market = name.split("@", 1)[1]
    if market not in d["extraKnownMarketplaces"]:
        print(f"{name} references unregistered marketplace '{market}'")
        sys.exit(1)
PY
  then
    echo "INVALID: $f"
    fail=1
    continue
  fi
  echo "OK: $f"
done
exit "$fail"
