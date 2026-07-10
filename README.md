# taskfiles

Canonical, shareable [Task](https://taskfile.dev) workflow shared across my repos.

Each repo vendors these files into a local `.taskfiles/shared/` directory and
includes them by relative path, so every clone is self-contained and portable -
no home-directory dependencies, no experimental flags. A repo's own tasks live
separately in `.taskfiles/project/project.yml`, which sync never touches.

## Layout

```
Taskfile.yaml                 # generic root — identical in every consumer repo
.taskfiles/
  shared/                     # vendored from here; do not hand-edit in consumers
    git.yml                   # merge / pre / push / review / tag* workflow
    go.yml                    # Go build/run/mod tasks (optional)
    ansible.yml               # Ansible playbook task (optional)
    scripts/                  # lib.sh, merge.sh, review.sh (backing git.yml)
  project/
    project.yml               # repo-owned tasks (never synced)
init.sh                       # one-time bootstrap for a repo with no Taskfile
```

## Bootstrap a repo (no Taskfile yet)

Defaults to the **latest** release (resolved via `git ls-remote`); the init
script itself is fetched from `main`.

```bash
# latest release
curl -fsSL https://raw.githubusercontent.com/methridge/taskfiles/main/init.sh | bash

# latest, also vendoring go.yml (a Go repo) — extra files come after the ref
curl -fsSL https://raw.githubusercontent.com/methridge/taskfiles/main/init.sh | bash -s -- latest go.yml

# pin to a specific release
curl -fsSL https://raw.githubusercontent.com/methridge/taskfiles/main/init.sh | bash -s -- v1.0.0
```

Commit the resulting `.taskfiles/` into your repo (it is vendored, not ignored),
then put your project-specific tasks in `.taskfiles/project/project.yml`.

## Refresh an already-adopted repo

A bare `task sync` re-pulls the **same version this repo shipped with** (the
default baked into its root `Taskfile.yaml`), so it never surprises you with an
upgrade. Upgrading is explicit:

```bash
task sync                                   # stay on the current version (idempotent)
task sync TASKFILES_REF=v1.1.0             # upgrade to a newer release (one-off)
task sync TASKFILES_FILES="git.yml go.yml scripts/lib.sh scripts/merge.sh scripts/review.sh"
```

`TASKFILES_REF` for `sync` must be a concrete tag (unlike `init.sh`, `sync` does
not resolve `latest`). `sync` overwrites only the generic root `Taskfile.yaml`
and files under `.taskfiles/shared/`; it never writes to `.taskfiles/project/`.

### Pin a version durably (recommended)

Because `task sync` overwrites the root `Taskfile.yaml`, editing its default ref
won't stick. Both sync vars are read from an env var of the same name (a CLI arg
still overrides), so pin them in the repo's `.envrc` instead — it isn't synced:

```bash
# .envrc
export TASKFILES_REF="v1.1.0"
export TASKFILES_FILES="git.yml go.yml scripts/lib.sh scripts/merge.sh scripts/review.sh"
```

Then `task sync` always tracks that ref and file set. See [`example.envrc`](example.envrc).

## The git workflow (from `git.yml`)

| Task | What it does |
|------|--------------|
| `merge` (aliases `mr`, `pr`) | Open a PR (GitHub) or MR (GitLab) for the current branch, wait for checks, merge with a real merge commit, clean up. Auto-detects the host. |
| `review:<PR#>` | Show a GitHub PR (metadata, checks, diff), then optionally approve and merge. |
| `pre` | `pre-commit autoupdate` + `gc` + `run -a`. |
| `push` | Branch off `main` (if needed), commit all changes with a timestamp, push. |
| `tag:<v>` / `tag:<v>:<msg>` | Create a signed tag. |
| `tag0` | Create the first tag (`v0.0.0`). |
| `tagauto` | Signed tag with auto semantic version (`autotag`, conventional scheme). |
| `tagcal` | Signed tag with calendar version. |

See [STANDARD.md](STANDARD.md) for the conventions every Taskfile follows.

## Cutting a release (maintainers)

```bash
task release:v1.1.0
```

This stamps `v1.1.0` into the root `Taskfile.yaml` sync default (so consumers on
that release re-sync idempotently), commits, and creates + pushes the signed
tag. `init.sh` picks up the new tag as `latest` automatically - no other version
strings to bump.

## Tools the workflow assumes

`task`, `git` (with a signing key for the `tag*` tasks), `gh` and/or `glab`,
`pre-commit`, `autotag`. Each task guards its own dependency with a
`precondition` that prints an install hint if the tool is missing.
