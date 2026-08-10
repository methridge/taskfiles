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
- The root `Taskfile.yaml` is generic and identical across repos. It only wires
  includes and defines `default` + `sync`. It carries no project-specific tasks.
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
- Claude Code plugin profiles live in `claude/` (`terraform`, `terraform-provider`,
  `packer`, `claude-config`); `init.sh` installs one via a `claude=PROFILE` token.
  Unlike `precommit`, this is opt-in (default `none`), and an existing
  `.claude/settings.json` is never overwritten. Where the two diverge is what
  happens next: the `.pre-commit-config.yaml` `init.sh` drops is repo-owned and
  `sync` never touches it again, but the `.claude/settings.json` it writes **is**
  sync-managed - `task sync` refreshes it from `claude/<name>.json` upstream
  whenever a profile is selected. When `init.sh` installs a profile it also
  writes `.taskfiles/claude-profile`, a committed one-line marker naming that
  profile, so the choice travels with the repo instead of living only in a
  gitignored `.envrc`.
  `sync` resolves which profile to use in this order: (1) `TASKFILES_CLAUDE_PROFILE`,
  if set and non-empty, always wins - a one-off override still works; (2)
  otherwise, the committed `.taskfiles/claude-profile` marker, if it exists and
  contains a non-empty name (surrounding whitespace and the trailing newline
  are trimmed; a whitespace-only file counts as empty); (3) otherwise, neither
  is set and `sync` does nothing to `.claude/settings.json` - this no-op is a
  safety property. `sync` only ever reads the marker, never writes it, so it
  cannot clobber it. A marker (or an explicit var) naming a profile that does
  not exist in `claude/` fails loudly and leaves `.claude/settings.json`
  untouched, the same as today.
  **Behavioural change from pre-marker repos:** before the marker existed, a
  bare `task sync` in a repo with a committed `.claude/settings.json` but no
  `TASKFILES_CLAUDE_PROFILE` set left that file alone forever - propagation
  required the variable to be set in that repo's own environment. Now, a
  repo bootstrapped with `claude=PROFILE` carries its own marker, so a bare
  `task sync` with no environment variable set will refresh
  `.claude/settings.json` from `claude/<name>.json` upstream on every run.
  That is the intended meaning of "sync-managed" - it just was not reachable
  without the marker before. Repos with no marker and no var behave exactly
  as before: `sync` no-ops and the committed file stays frozen.

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
