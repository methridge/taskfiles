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
