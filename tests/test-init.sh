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

# claude=terraform -> .claude/settings.json with the terraform plugin
w="$(run claude=terraform)"
if [[ -f "$w/.claude/settings.json" ]] \
  && grep -q 'terraform@hashicorp' "$w/.claude/settings.json"; then
  report "claude=terraform installs profile" ok
else
  report "claude=terraform installs profile" no
fi

# claude=terraform -> .mcp.json also installed, from claude/terraform.mcp.json
w="$(run claude=terraform)"
if [[ -f "$w/.mcp.json" ]] && grep -q terraform-mcp-server "$w/.mcp.json"; then
  report "claude=terraform installs .mcp.json" ok
else
  report "claude=terraform installs .mcp.json" no
fi

# default (no token) -> no .claude/settings.json at all
w="$(run)"
if [[ ! -f "$w/.claude/settings.json" ]]; then
  report "claude defaults to opt-out" ok
else
  report "claude defaults to opt-out" no
fi

# claude=none -> explicit opt-out, same as default
w="$(run claude=none)"
if [[ ! -f "$w/.claude/settings.json" ]]; then
  report "claude=none opts out" ok
else
  report "claude=none opts out" no
fi

# token combines with shared files and the precommit token
w="$(run go.yml precommit=go claude=packer)"
if [[ -f "$w/.taskfiles/shared/go.yml" ]] \
  && grep -q golangci-lint "$w/.pre-commit-config.yaml" \
  && grep -q 'packer@hashicorp' "$w/.claude/settings.json"; then
  report "claude token composes with go.yml + precommit" ok
else
  report "claude token composes with go.yml + precommit" no
fi

# claude=packer -> packer profile has no .mcp.json upstream, so none is
# created, silently (no error, no warning)
w="$(run claude=packer)"
if [[ -f "$w/.claude/settings.json" ]] && [[ ! -f "$w/.mcp.json" ]]; then
  report "claude=packer creates no .mcp.json" ok
else
  report "claude=packer creates no .mcp.json" no
fi

# existing .mcp.json is never clobbered, even for a profile that has its own
# (claude=terraform ships .mcp.json upstream, but a pre-existing file wins)
work="$(mktemp -d)"
printf '{"mcpServers":{"sentinel":{}}}\n' > "$work/.mcp.json"
( cd "$work" && TASKFILES_BASE="$BASE" bash "$INIT" v1.0.0 claude=terraform ) >/dev/null 2>&1
if grep -q sentinel "$work/.mcp.json"; then
  report "existing .mcp.json preserved under claude=terraform" ok
else
  report "existing .mcp.json preserved under claude=terraform" no
fi

# existing .mcp.json is never clobbered for a profile with no .mcp.json either
work="$(mktemp -d)"
printf '{"mcpServers":{"sentinel":{}}}\n' > "$work/.mcp.json"
( cd "$work" && TASKFILES_BASE="$BASE" bash "$INIT" v1.0.0 claude=packer ) >/dev/null 2>&1
if grep -q sentinel "$work/.mcp.json"; then
  report "existing .mcp.json preserved under claude=packer" ok
else
  report "existing .mcp.json preserved under claude=packer" no
fi

# unknown profile -> non-zero exit, no leftover file
work="$(mktemp -d)"
if ( cd "$work" && TASKFILES_BASE="$BASE" bash "$INIT" v1.0.0 claude=bogus ) >/dev/null 2>&1; then
  report "unknown claude profile fails" no
elif [[ ! -f "$work/.claude/settings.json" ]]; then
  report "unknown claude profile fails cleanly" ok
else
  report "unknown claude profile leaves no file" no
fi

# existing settings.json is never clobbered
work="$(mktemp -d)"
mkdir -p "$work/.claude"
printf '{"SENTINEL":true}\n' > "$work/.claude/settings.json"
( cd "$work" && TASKFILES_BASE="$BASE" bash "$INIT" v1.0.0 claude=terraform ) >/dev/null 2>&1
if grep -q SENTINEL "$work/.claude/settings.json"; then
  report "existing claude settings preserved" ok
else
  report "existing claude settings preserved" no
fi

# claude=terraform -> .taskfiles/config records TASKFILES_CLAUDE_PROFILE and
# the default TASKFILES_FILES list
w="$(run claude=terraform)"
if [[ -f "$w/.taskfiles/config" ]] \
  && grep -q 'TASKFILES_CLAUDE_PROFILE="terraform"' "$w/.taskfiles/config" \
  && grep -q 'TASKFILES_FILES="git.yml scripts/lib.sh scripts/merge.sh scripts/push.sh scripts/review.sh"' "$w/.taskfiles/config"; then
  report "claude=terraform records profile in config" ok
else
  report "claude=terraform records profile in config" no
fi

# no claude token -> config written, but no TASKFILES_CLAUDE_PROFILE key
w="$(run)"
if [[ -f "$w/.taskfiles/config" ]] && ! grep -q TASKFILES_CLAUDE_PROFILE "$w/.taskfiles/config"; then
  report "no claude token records no profile" ok
else
  report "no claude token records no profile" no
fi

# existing settings.json -> declined install, so config must not claim that
# profile (consistency rule: never record what this invocation didn't do)
work="$(mktemp -d)"
mkdir -p "$work/.claude"
printf '{"SENTINEL":true}\n' > "$work/.claude/settings.json"
( cd "$work" && TASKFILES_BASE="$BASE" bash "$INIT" v1.0.0 claude=terraform ) >/dev/null 2>&1
if grep -q SENTINEL "$work/.claude/settings.json" \
  && [[ -f "$work/.taskfiles/config" ]] \
  && ! grep -q TASKFILES_CLAUDE_PROFILE "$work/.taskfiles/config"; then
  report "existing settings.json -> config does not claim profile" ok
else
  report "existing settings.json -> config does not claim profile" no
fi

# precommit=terraform -> config records PRECOMMIT
w="$(run precommit=terraform)"
if grep -q 'PRECOMMIT="terraform"' "$w/.taskfiles/config" 2>/dev/null; then
  report "precommit=terraform records PRECOMMIT in config" ok
else
  report "precommit=terraform records PRECOMMIT in config" no
fi

# precommit=none -> no PRECOMMIT key
w="$(run precommit=none)"
if [[ -f "$w/.taskfiles/config" ]] && ! grep -q PRECOMMIT "$w/.taskfiles/config"; then
  report "precommit=none records no PRECOMMIT" ok
else
  report "precommit=none records no PRECOMMIT" no
fi

# existing .pre-commit-config.yaml -> declined install, config must not claim
# a PRECOMMIT template it didn't seed
work="$(mktemp -d)"
printf 'SENTINEL\n' > "$work/.pre-commit-config.yaml"
( cd "$work" && TASKFILES_BASE="$BASE" bash "$INIT" v1.0.0 precommit=terraform ) >/dev/null 2>&1
if grep -q SENTINEL "$work/.pre-commit-config.yaml" \
  && [[ -f "$work/.taskfiles/config" ]] \
  && ! grep -q PRECOMMIT "$work/.taskfiles/config"; then
  report "existing pre-commit config -> config does not claim PRECOMMIT" ok
else
  report "existing pre-commit config -> config does not claim PRECOMMIT" no
fi

# extra shared files (go.yml) land in TASKFILES_FILES
w="$(run go.yml)"
if grep -q 'TASKFILES_FILES=".*go\.yml"' "$w/.taskfiles/config" 2>/dev/null; then
  report "extra shared file recorded in TASKFILES_FILES" ok
else
  report "extra shared file recorded in TASKFILES_FILES" no
fi

# combined: go.yml + precommit=go + claude=packer -> all three keys present
w="$(run go.yml precommit=go claude=packer)"
if grep -q 'TASKFILES_FILES=".*go\.yml"' "$w/.taskfiles/config" 2>/dev/null \
  && grep -q 'PRECOMMIT="go"' "$w/.taskfiles/config" 2>/dev/null \
  && grep -q 'TASKFILES_CLAUDE_PROFILE="packer"' "$w/.taskfiles/config" 2>/dev/null; then
  report "config records all three keys together" ok
else
  report "config records all three keys together" no
fi

# pre-existing .taskfiles/config is never clobbered
work="$(mktemp -d)"
mkdir -p "$work/.taskfiles"
printf 'SENTINEL\n' > "$work/.taskfiles/config"
( cd "$work" && TASKFILES_BASE="$BASE" bash "$INIT" v1.0.0 claude=terraform precommit=go ) >/dev/null 2>&1
if grep -q SENTINEL "$work/.taskfiles/config"; then
  report "existing .taskfiles/config preserved" ok
else
  report "existing .taskfiles/config preserved" no
fi

echo "----"
echo "pass=$pass fail=$fail"
exit "$fail"
