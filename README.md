# taskfiles

Canonical, shareable [Task](https://taskfile.dev) workflow shared across my repos.

Each repo vendors these files into a local `.taskfiles/shared/` directory and
includes them by relative path, so every clone is self-contained and portable -
no home-directory dependencies, no experimental flags. A repo's own tasks live
separately in `.taskfiles/project/project.yml`, which sync never touches.

## Layout

```text
Taskfile.yaml                 # generic root — identical in every consumer repo
.taskfiles/
  shared/                     # vendored from here; do not hand-edit in consumers
    git.yml                   # merge / pre / push / review / tag* workflow
    go.yml                    # Go build/run/mod tasks (optional)
    ansible.yml               # Ansible playbook task (optional)
    scripts/                  # lib.sh, merge.sh, review.sh (backing git.yml)
  project/
    project.yml               # repo-owned tasks (never synced)
  config                       # committed repo config (optional; see below)
init.sh                       # one-time bootstrap for a repo with no Taskfile
```

## Bootstrap a repo (no Taskfile yet)

The init script is served from the **latest GitHub Release** (attached as a
release asset), so you never run an unreleased `main` version. With no ref it
also vendors the latest release's content.

```bash
# latest release
curl -fsSL https://github.com/methridge/taskfiles/releases/latest/download/init.sh | bash

# latest, also vendoring go.yml (a Go repo) — extra files come after the ref
curl -fsSL https://github.com/methridge/taskfiles/releases/latest/download/init.sh | bash -s -- latest go.yml

# pin to a specific release (script + content from that tag)
curl -fsSL https://github.com/methridge/taskfiles/releases/download/v1.0.0/init.sh | bash -s -- v1.0.0
```

Commit the resulting `.taskfiles/` into your repo (it is vendored, not ignored),
then put your project-specific tasks in `.taskfiles/project/project.yml`.

### Pre-commit config

`init.sh` also installs a `.pre-commit-config.yaml` from `precommit/`. Pick a
template with a `precommit=NAME` token (default `base`); use `precommit=none` to
skip it. An existing `.pre-commit-config.yaml` is never overwritten.

| Name | Hooks |
| --- | --- |
| `base` | pre-commit-hooks base set (large-files, merge-conflict, yaml, eof, no-commit-to-branch, trailing-whitespace) |
| `terraform` | base + antonbabenko/pre-commit-terraform (fmt, validate, docs, tflint, trivy) |
| `go` | base + golangci-lint |
| `ansible` | base + ansible-lint |

```bash
# base pre-commit (default)
curl -fsSL https://github.com/methridge/taskfiles/releases/latest/download/init.sh | bash

# terraform template
curl -fsSL https://github.com/methridge/taskfiles/releases/latest/download/init.sh | bash -s -- latest precommit=terraform

# go tasks + go pre-commit (the token can sit alongside extra shared files)
curl -fsSL https://github.com/methridge/taskfiles/releases/latest/download/init.sh | bash -s -- latest go.yml precommit=go

# no pre-commit config
curl -fsSL https://github.com/methridge/taskfiles/releases/latest/download/init.sh | bash -s -- latest precommit=none
```

Templates are complete standalone files (pre-commit has no include mechanism).
`precommit/terraform.yaml` is the canonical terraform config; keep repo copies in
sync with it.

### Claude Code plugin profile

`init.sh` can also install a `.claude/settings.json` from `claude/`, so the repo
only loads the Claude Code plugins it needs. Unlike `precommit`, this is
opt-in - pass a `claude=PROFILE` token to install one (there is no default). An
existing `.claude/settings.json` is never overwritten, and when one already
exists `init.sh` also skips recording the profile in `.taskfiles/config` (see
below), so the two never disagree about which profile - if any - is installed.

Valid profiles: `terraform`, `terraform-provider`, `packer`, `claude-config`.

```bash
# add a Claude Code plugin profile
curl -fsSL https://github.com/methridge/taskfiles/releases/latest/download/init.sh | bash -s -- latest claude=terraform

# combine with a pre-commit template
curl -fsSL https://github.com/methridge/taskfiles/releases/latest/download/init.sh | bash -s -- latest precommit=terraform claude=terraform
```

Unlike the pre-commit template, this file stays managed after bootstrap.
Installing a profile also records `TASKFILES_CLAUDE_PROFILE` in the committed
`.taskfiles/config` (see [Repo config](#repo-config-taskfilesconfig) below),
so the choice travels with the repo instead of living only in a gitignored
`.envrc`. `task sync` resolves which profile to use, in order: an explicit
`TASKFILES_CLAUDE_PROFILE` env var or CLI arg (always wins) - otherwise the
value in `.taskfiles/config` - otherwise an ambient environment variable -
otherwise neither is set and `.claude/settings.json` is left alone.

**Behavioural change:** without a `.taskfiles/config` entry, a bare `task sync`
with no `TASKFILES_CLAUDE_PROFILE` set never touches a committed
`.claude/settings.json`, even if the repo had bootstrapped with a profile -
propagation requires the config file or the env var. A repo bootstrapped with
`claude=PROFILE` gets it recorded in `.taskfiles/config`, so a bare `task sync`
refreshes `.claude/settings.json` from `claude/<name>.json` upstream on every
run, with no environment variable needed. Set
`export TASKFILES_CLAUDE_PROFILE="terraform"` in `.envrc` only when you need
to override the committed config for that checkout.

## Repo config (`.taskfiles/config`)

`.taskfiles/config` is an optional, committed, plain `KEY="value"` file the
root Taskfile loads via Task's `dotenv:` directive. It exists because
`.envrc` is gitignored, so nothing in-repo otherwise records certain
per-repo choices - a bare `task sync` would silently drift (e.g. skip
refreshing a vendored shared file it doesn't know about) with no error. It
supersedes the v1.3.0 `.taskfiles/claude-profile` marker.

`init.sh` writes it after bootstrapping, recording only what that run
actually did:

```bash
# .taskfiles/config
TASKFILES_FILES="git.yml scripts/lib.sh scripts/merge.sh scripts/review.sh go.yml"
TASKFILES_CLAUDE_PROFILE="terraform"
PRECOMMIT="terraform"
```

- `TASKFILES_FILES` - which shared files this repo vendors.
- `TASKFILES_CLAUDE_PROFILE` - the Claude Code profile, if one was installed.
- `PRECOMMIT` - which `precommit/` template seeded `.pre-commit-config.yaml`.
  **Recorded only** - `sync` never reads or acts on this key, because
  `.pre-commit-config.yaml` is repo-owned and hand-tunable (see
  [STANDARD.md](STANDARD.md)); re-syncing it would clobber local edits.

`TASKFILES_REF` is deliberately not recorded here - `task release` already
stamps it into `Taskfile.yaml`'s `sync` default.

Resolution order for any var `.taskfiles/config` sets, high to low: a CLI arg
> the value in `.taskfiles/config` > an ambient environment variable > the
taskfile's built-in default. The config file deliberately outranks a stray
ambient env var - the same hazard class the v1.2.1 `TASKFILES_` namespacing
fixed - while a CLI arg can still override it for a one-off. A missing
`.taskfiles/config` is not an error; defaults apply as before. If
`.taskfiles/config` already exists, `init.sh` leaves it alone.

## Refresh an already-adopted repo

Check whether you're behind the latest release first:

```bash
task sync:check    # e.g. "Update available: v1.0.0 -> v1.1.0"
```

A bare `task sync` re-pulls the **same version this repo shipped with** (the
default baked into its root `Taskfile.yaml`), so it never surprises you with an
upgrade. Upgrading is explicit:

```bash
task sync                                   # stay on the current version (idempotent)
task sync TASKFILES_REF=v1.1.0             # upgrade to a newer release (one-off)
task sync TASKFILES_FILES="git.yml go.yml scripts/lib.sh scripts/merge.sh scripts/review.sh"  # one-off file-list override
```

A repo that vendors an optional shared file (e.g. `go.yml`) should record it
in the committed `.taskfiles/config` (`init.sh` does this automatically), not
just pass it on the CLI - otherwise a later bare `task sync` falls back to the
built-in default list, which omits it, and that file silently goes stale.

`TASKFILES_REF` for `sync` must be a concrete tag (unlike `init.sh`, `sync` does
not resolve `latest`). `sync` overwrites only the generic root `Taskfile.yaml`
and files under `.taskfiles/shared/`; it never writes to `.taskfiles/project/`.

### Pin a version durably (recommended)

Because `task sync` overwrites the root `Taskfile.yaml`, editing its default ref
won't stick. `TASKFILES_REF` is a per-checkout override, not something to
commit (see [Repo config](#repo-config-taskfilesconfig) above for why), so pin
it in the repo's `.envrc` instead — it isn't synced:

```bash
# .envrc
export TASKFILES_REF="v1.1.0"
```

`TASKFILES_FILES`, by contrast, is repo data everyone who clones the repo
needs - commit it in `.taskfiles/config` instead (`init.sh` does this for
you). See [`example.envrc`](example.envrc) for the `.envrc` template.

## The git workflow (from `git.yml`)

| Task | What it does |
| ---- | ------------ |
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
task release            # next version, auto-computed from conventional commits (autotag)
task release:v1.0.0    # explicit version — required for the FIRST release, or a major bump
```

Both stamp the version into the root `Taskfile.yaml` sync default (so consumers
on that release re-sync idempotently), commit, push the signed tag, and publish
a GitHub Release with `init.sh` attached - so `releases/latest/download/init.sh`
immediately serves the new bootstrap. No other version strings to bump.

`task release` uses `autotag --scheme=conventional`, which needs a prior tag to
bump from; the first release has none, so cut it explicitly (`task
release:v1.0.0`), mirroring the `tag0` → `tagauto` split in the shared workflow.

## Tools the workflow assumes

`task`, `git` (with a signing key for the `tag*` tasks), `gh` and/or `glab`,
`pre-commit`, `autotag`. Each task guards its own dependency with a
`precondition` that prints an install hint if the tool is missing.
