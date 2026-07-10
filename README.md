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

```bash
curl -fsSL https://raw.githubusercontent.com/methridge/taskfiles/v1.0.0/init.sh \
  | bash -s -- v1.0.0
```

Add optional shared files as extra args, e.g. a Go repo:

```bash
curl -fsSL https://raw.githubusercontent.com/methridge/taskfiles/v1.0.0/init.sh \
  | bash -s -- v1.0.0 go.yml
```

Commit the resulting `.taskfiles/` into your repo (it is vendored, not ignored),
then put your project-specific tasks in `.taskfiles/project/project.yml`.

## Refresh an already-adopted repo

```bash
task sync                       # pins to the default ref in the root Taskfile
task sync REF=v1.1.0            # bump to a newer release
task sync SHARED="git.yml go.yml scripts/lib.sh scripts/merge.sh scripts/review.sh"
```

`sync` overwrites only the generic root `Taskfile.yaml` and files under
`.taskfiles/shared/`. It never writes to `.taskfiles/project/`.

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

## Tools the workflow assumes

`task`, `git` (with a signing key for the `tag*` tasks), `gh` and/or `glab`,
`pre-commit`, `autotag`. Each task guards its own dependency with a
`precondition` that prints an install hint if the tool is missing.
