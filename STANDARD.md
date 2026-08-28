# Taskfile standard

Conventions every `Taskfile.yaml` in my repos follows. The reference
implementation is this repo.

## Structure

- Header on every file:

  ```yaml
  # yaml-language-server: $schema=https://taskfile.dev/schema.json
  # https://taskfile.dev
  ```

- `version: "3"` (double-quoted).
- The root `Taskfile.yaml` is generic and identical across repos. It wires
  includes and defines generic, repo-agnostic tasks: `default`, `sync`,
  `sync:check`, and `claude:*` (see below). It carries no project-specific
  tasks - those live in `.taskfiles/project/project.yml` instead.
- Shared task content is vendored into `.taskfiles/shared/` and included by
  relative path. Optional shared files (`go.yml`, `ansible.yml`) and the
  project layer use `optional: true` so a repo can omit what it does not use.
- Project-specific tasks live in `.taskfiles/project/project.yml` (repo-owned;
  never synced).
- Pre-commit config templates live in `precommit/` (`base`, `terraform`, `go`,
  `ansible`); `init.sh` installs one via a `precommit=NAME` token. The
  `.pre-commit-config.yaml` it drops is repo-owned (never synced), and
  `precommit/terraform.yaml` is the canonical terraform config other repos should
  match.
- Claude Code plugin profiles live in `claude/` (`terraform`, `packer`,
  `claude-config`); `init.sh` installs one via a `claude=PROFILE` token.
  Unlike `precommit`, this is opt-in (default `none`), and an existing
  `.claude/settings.json` is never overwritten. Where the two diverge is what
  happens next: the `.pre-commit-config.yaml` `init.sh` drops is repo-owned and
  `sync` never touches it again, but the `.claude/settings.json` it writes **is**
  sync-managed - `task sync` refreshes it from `claude/<name>.json` upstream
  whenever a profile is selected (resolved via `.taskfiles/config`; see below).
  **Behavioural change from profile-less repos:** a bare `task sync` in a repo
  with a committed `.claude/settings.json` but no `TASKFILES_CLAUDE_PROFILE`
  set and no `.taskfiles/config` entry leaves that file alone forever -
  propagation requires either the config file or the env var. A repo
  bootstrapped with `claude=PROFILE` gets `TASKFILES_CLAUDE_PROFILE` recorded
  in its `.taskfiles/config`, so a bare `task sync` with no environment
  variable set refreshes `.claude/settings.json` from `claude/<name>.json`
  upstream on every run. That is the intended meaning of "sync-managed."
  Repos with no config entry and no env var behave as before: `sync` no-ops
  and the committed file stays frozen.
  - The v1.5.0 profile set was `terraform`, `terraform-provider`, `packer`,
    `terraform-provider-development`, `packer-builders`, `packer-hcp`
    (mapping to six now-defunct upstream `hashicorp/agent-skills` plugins).
    HashiCorp consolidated those six plugins into two (`terraform`, `packer`)
    in v1.6.0; `terraform-provider` was deleted outright because the
    consolidated `terraform` plugin already contains every provider skill it
    used to enable separately, making the profile byte-identical to
    `terraform`. It had zero consumers at deletion time.
  - A profile may also ship a sibling `claude/<profile>.mcp.json` (shape
    `{"mcpServers": {...}}`) for a project-scoped MCP server. Both `init.sh`
    and `sync` fetch it alongside the profile's `.json` and, if present,
    write it to `./.mcp.json` at the repo root - not under `.claude/`, which
    is where Claude Code looks for project-scoped MCP config. Only `terraform`
    has one today, restoring the Terraform registry MCP server the old
    `terraform-module-generation` plugin bundled inline (the consolidated
    plugins ship no MCP server at all). A missing `claude/<profile>.mcp.json`
    (most profiles) is normal and silent, not an error - and in that case an
    existing `./.mcp.json` is never overwritten or deleted, same as
    `init.sh` never overwrites `.claude/settings.json`. When the profile
    *does* have an `.mcp.json`, `task sync` treats it as sync-managed exactly
    like `.claude/settings.json` - it is refreshed from upstream on every
    run, overwriting a pre-existing `./.mcp.json`. `init.sh`, being
    bootstrap-only, never overwrites an existing `.mcp.json` either way.
    Switching a repo away from a profile with an `.mcp.json` leaves the old
    file behind; remove it by hand.
  - An `.mcp.json` is committed and sync-managed, so it must never carry a
    credential. Reference one instead - `"TFE_TOKEN": "${TFE_TOKEN}"` - and let
    Claude Code expand it from the environment `.envrc` provides. Keeping the
    indirection is what lets the same file be shared across a team whose
    members hold different tokens, and what keeps `task sync` free to overwrite
    the file without destroying a secret. Document the variables a profile
    needs in the repo's `example.envrc`; the template in this repo shows the
    `terraform` profile's pair. Note the failure mode is quiet: an unset token
    still starts the server, just with the authenticated tools missing, so
    verify against the provider's API rather than assuming a clean start means
    a working credential. Address and token travel together - a token is issued
    by one Terraform instance and rejected by every other, so pair `TFE_ADDRESS`
    with the `hostname` in the repo's own `cloud {}` block. Testing a
    self-hosted token against `app.terraform.io` returns the same 401 as an
    expired one, which makes a wrong-host mistake read as a dead credential.

## Repo config (`.taskfiles/config`)

An optional, committed, plain `KEY="value"` file, loaded by the root
Taskfile's `dotenv:` directive. It exists because `.envrc` is gitignored, so
nothing in-repo previously recorded certain per-repo choices - a bare `task
sync` would silently drift from what the repo actually needs (e.g. omit a
vendored shared file, or skip refreshing the Claude profile) with no error
and no signal. `.taskfiles/config` is generic machinery (loaded by the same
`dotenv:` line in every consumer); its *contents* are repo-specific data, same
as `.taskfiles/project/project.yml`. It supersedes the v1.3.0
`.taskfiles/claude-profile` marker, which recorded only the Claude profile;
that marker had zero consumers (no repo had synced to v1.3.0) and was removed
outright rather than migrated.

Keys recorded:

- `TASKFILES_FILES` - which shared files this repo vendors (space-separated,
  quoted: `TASKFILES_FILES="git.yml scripts/lib.sh go.yml"`).
- `TASKFILES_CLAUDE_PROFILE` - the Claude Code profile, if one is installed.
- `PRECOMMIT` - which `precommit/` template seeded `.pre-commit-config.yaml`.
  **Recorded only - `sync` never reads or acts on this key.**
  `.pre-commit-config.yaml` is repo-owned and hand-tunable per this document;
  re-syncing it from the template would clobber local edits. `PRECOMMIT` is a
  record of provenance (what seeded the file), not an instruction to `sync`.
  Do not "fix" `sync` to honour it.

`TASKFILES_REF` is deliberately **not** recorded here. It is already stamped
into `Taskfile.yaml`'s `sync` default by `task release`; a second copy in
`.taskfiles/config` could disagree with that authoritative one.

**Resolution order**, high to low, for any var `.taskfiles/config` sets
(verified against Task 3.50.0):

1. A CLI arg, e.g. `task sync TASKFILES_FILES=...` - always wins, for a
   one-off override.
2. The value in `.taskfiles/config`, if the file exists and sets the key.
3. An ambient environment variable (e.g. exported in a shell profile).
4. The taskfile's built-in default.

Critically, step 2 outranks step 3: a value committed in `.taskfiles/config`
is **not** overridden by a same-named variable that merely happens to be
exported in someone's shell. This is deliberate, not an oversight - it is the
same hazard class the v1.2.1 `TASKFILES_`-prefix namespacing fixed (a stray
ambient var silently steering `sync`), and a committed file that only a CLI
arg can override is immune to it. A missing `.taskfiles/config` is not an
error; step 3/4 apply as before.

`init.sh` writes `.taskfiles/config` after bootstrapping, recording only what
that invocation actually did - if it declined to overwrite an existing
`.claude/settings.json` or `.pre-commit-config.yaml`, the corresponding key is
left out entirely, so the file never claims a choice this run didn't make.
If `.taskfiles/config` already exists, `init.sh` leaves it alone and says so,
matching how it already refuses to clobber `.taskfiles/project/project.yml`
and `.pre-commit-config.yaml`.

### CLI-override warnings

A CLI arg to `sync` (e.g. `task sync TASKFILES_CLAUDE_PROFILE=packer`) is
always one-off - `sync` never writes it back to `.taskfiles/config`. Left
silent, that one-off nature is easy to miss, and there is a worse variant: a
CLI arg in a repo with **no** recorded profile produces a correct
`.claude/settings.json` once and then never again, because every later bare
`sync` has nothing to resolve to. That is the exact staleness bug
`.taskfiles/config` exists to prevent, re-entered through the CLI-arg door.
`sync` therefore prints a warning to stderr in exactly two cases, both only
when `TASKFILES_CLAUDE_PROFILE` came from a CLI arg:

- The CLI value differs from what `.taskfiles/config` records: the override
  is for this run only, `.taskfiles/config` is unchanged, and the next bare
  `sync` reverts to the recorded value.
- `.taskfiles/config` records no profile at all: nothing will maintain
  `.claude/settings.json` going forward, and the file will stay frozen at
  whatever this run wrote unless `TASKFILES_CLAUDE_PROFILE` is recorded.

The normal path - the profile coming from `.taskfiles/config` itself, with no
CLI arg - stays silent; warning on the intended, everyday path would just
train people to ignore warnings.

Distinguishing "value came from a CLI arg" from "value came from
`.taskfiles/config`" (verified on Task 3.50.0): a CLI-passed `VAR=value`
populates the resolved template var (`{{.TASKFILES_CLAUDE_PROFILE}}`) but is
**not** exported into the shell environment `cmds:` scripts run in - Task
keeps CLI/call vars and the process environment as separate channels. A
value from `dotenv:` (`.taskfiles/config`) or an ambient env var, by
contrast, **is** visible as a real shell variable there. So a mismatch
between the resolved template var and the plain shell variable of the same
name means a CLI arg won. What `.taskfiles/config` itself records is read
directly from the file (not through Task's var resolution at all), so
ambient-env noise can never taint that comparison.

### `claude:*` - record a profile without drift

`task claude:<profile>` (e.g. `task claude:terraform`) is the safe way to
change a repo's Claude Code profile: it validates the name resolves upstream,
updates (or creates) `.taskfiles/config` - preserving every other key and
comment, touching only the `TASKFILES_CLAUDE_PROFILE` line - and then runs
`sync`, so `.taskfiles/config` and `.claude/settings.json` can never drift
apart. It follows this repo's existing `<verb>:*` wildcard idiom
(`tag:*`, `review:*`, `release:*`). Prefer it over a bare
`task sync TASKFILES_CLAUDE_PROFILE=...`, which is intentionally one-off (see
above).

## Tasks

- `default` (with `aliases: [help]`) runs `task --list-all`. `task help` still
  works via the alias; there is no separate duplicated `help` task.
- Every task has a `desc:` so it shows up in `task --list-all`.
- Tool dependencies are guarded by a `precondition` with an install hint:

  ```yaml
  preconditions:
    - sh: 'command -v <tool> >/dev/null 2>&1'
      msg: "<tool> required: <install hint>"
  ```

- Mandatory config values are guarded by `requires:` (Task also checks the
  environment for these):

  ```yaml
  requires:
    vars: [OCP_NAMESPACE]
  ```

## Portability

- No hardcoded machine- or org-specific values. Lift them into top-level
  `vars:` with an env-overridable default:

  ```yaml
  vars:
    VAULT_ADDR: '{{.VAULT_ADDR | default "https://vault.example:8200"}}'
  ```

  or into `requires:` when there is no safe default. Where an override must be
  explicit, use the `{{env "NAME"}}` template function.
- Task reads a variable from an environment variable of the **same name** (no
  `TASK_` prefix; verified on Task 3.50.0). Precedence, high to low: a CLI arg
  `VAR=value` > an env var > the taskfile `default`. So `VAULT_ADDR:
  '{{.VAULT_ADDR | default "..."}}'` picks up `$VAULT_ADDR` from `.envrc`, and a
  CLI arg still wins for a one-off. This is also how a repo pins the taskfiles
  version it syncs to — `export TASKFILES_REF` in `.envrc`.
- Document required environment in an `example.envrc`. Start from the template
  [`example.envrc`](example.envrc) in this repo: copy it into your repo, list
  the vars your tasks need, and commit it (but never commit the filled-in
  `.envrc`). This repo itself needs no env, so its `example.envrc` is a
  commented skeleton only.
- Scripts called by tasks resolve their own siblings via `BASH_SOURCE`, so they
  are relocation-safe once vendored under `.taskfiles/shared/scripts/`.
