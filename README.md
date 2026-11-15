# git-pullkeep

[![CI](https://github.com/aiti-ai/git-pullkeep/actions/workflows/test.yml/badge.svg)](https://github.com/aiti-ai/git-pullkeep/actions/workflows/test.yml)
[![Release](https://img.shields.io/github/v/release/aiti-ai/git-pullkeep)](https://github.com/aiti-ai/git-pullkeep/releases)
[![License: MIT](https://img.shields.io/github/license/aiti-ai/git-pullkeep)](LICENSE)
[![npm](https://img.shields.io/npm/v/git-pullkeep)](https://www.npmjs.com/package/git-pullkeep)
[![Platform](https://img.shields.io/badge/platform-linux%20%7C%20macOS%20%7C%20windows-lightgrey)](README.md)

**English** · [简体中文](README_zh.md)

`git pull` that never loses your uncommitted work — and never stashes the whole tree.

```console
$ git status --short
 M src/api/client.ts
 M src/service/handler.ts
 M docs/notes.md            # 70 more dirty files your pull does not care about

$ git pull
error: Your local changes to the following files would be overwritten by merge:
        src/api/client.ts
        src/service/handler.ts
Please commit your changes or stash them before you merge.
Aborting

$ git pullkeep
==> fetch origin

branch      : main
upstream    : origin/main (a1b2c3d4)
incoming    : 12 file(s) across 14 new commit(s)
dirty       : 72 tracked file(s) + 3 untracked
strategy    : merge
blocking    : 2 file(s) overlap upstream, 2 file(s) will be parked
   - src/api/client.ts
   - src/service/handler.ts

==> snapshot of current working tree -> refs/pullkeep/20261106-101336
    'git pullkeep --undo' restores this exact dirty state at any time
==> temp commit: 3c9f1a2b (2 file(s))
    tagged "wip: pullkeep temp commit" so a later run can detect and collapse it
==> git pull --no-rebase origin main
==> collapsing commits: reset --mixed a1b2c3d4
==> verified: working tree state is identical to pre-pull (75 entries)

done. on origin/main (a1b2c3d4), 72 dirty file(s) still uncommitted.
  undo fully : git pullkeep --undo
  backups    : 1 ref(s) under refs/pullkeep/
```

## `git pullkeep` vs `git pull --autostash`

| | ✅ `git pullkeep` | `git pull --autostash` |
|---|---|---|
| 🎯 What moves out of the way | **only the files that block the pull** | the whole working tree |
| 🛡️ Conflict risk on restore | none for untouched files — they never move | one big three-way merge; you can land mid-`stash pop` |
| 📦 Staged (index) state | **preserved across the round trip** | lost |
| 🧾 Audit trail | snapshot ref + tagged temp commit + `--dry-run` / `--check` | none |
| ↩️ Recovery | **`--undo` restores the exact pre-pull tree**, untracked files included | `git stash list` archaeology |
| 🔁 Interrupted run | leftover temp commit is detected (exit 31) and collapsible via `--continue` / `--recover` | a stray stash entry is easy to lose |
| 🔒 Concurrent runs | **one writing run at a time**; a second one exits 35 instead of racing on the index | no coordination at all: two runs can both rewrite the index and the stash |
| ⚙️ Relayed options | fetch + merge + `--rebase[=merges]`, the flavour you typed is passed on unchanged | whatever `git pull` accepts |
| ⚠️ Not supported | `--ff-only`, `--squash`, `--no-commit` (refused on purpose, exit 21) | all of them |

## Install

A single bash script (3.2+), zero dependencies beyond `git` and POSIX utilities. Git discovers it
through its own dashed-external mechanism: any file named `git-pullkeep` on `PATH` becomes
`git pullkeep` — no config, no plugin system. npm is only the delivery truck; git itself never
consults a registry.

**Any platform (npm)**

```sh
npm install -g git-pullkeep       # from v0.1.0 on; before that use the installers below
npx git-pullkeep --dry-run        # try it without installing anything
```

**macOS / Linux**

```sh
curl -fsSL https://raw.githubusercontent.com/aiti-ai/git-pullkeep/main/install.sh | sh
# Homebrew (planned)
brew install aiti-ai/tap/git-pullkeep
```

**Windows** (PowerShell 5.1+)

```powershell
irm https://raw.githubusercontent.com/aiti-ai/git-pullkeep/main/install.ps1 | iex
# installs %USERPROFILE%\bin\git-pullkeep and appends it to your user PATH
```

**Manual**: copy `git-pullkeep` (no extension, LF line endings) into any directory on `PATH`,
then verify with `git help -a | grep pullkeep`.

> Windows note: always type `git pullkeep`. Git for Windows runs the shebang script with its
> bundled bash, so the subcommand form works. The bare `git-pullkeep` shim that npm installs can
> instead pick up `C:\Windows\System32\bash.exe` (WSL) and fail with `No such file or directory`.
> `git help -a` may also list a harmless `pullkeep.ps1` entry — that is npm's PowerShell shim.

**Gitee mirror** (China): set `GIT_PULLKEEP_REPO=https://gitee.com/aiti-ai/git-pullkeep/raw` for
`sh install.sh`, or `$env:GIT_PULLKEEP_REPO` before `irm install.ps1`; both installers then pull the
script itself from Gitee instead of GitHub.

## Usage

```console
git pullkeep                 # merge (default), keeps every uncommitted change
git pullkeep --rebase        # rebase; all dirty tracked files are parked and restored
git pullkeep --dry-run       # analyse only (still fetches, unless --no-fetch)
git pullkeep --check         # exit 10 if the pull would have to park or resolve anything (CI gate)
git pullkeep --continue      # after resolving conflicts: collapse the commit layer
git pullkeep --recover       # collapse a temp commit left by an interrupted run
git pullkeep --undo -y       # restore the exact pre-pull working tree (`--abort` is an alias)
git pullkeep --no-fetch      # work from the current remote-tracking ref
git pullkeep --keep-backups=3 # keep only the newest 3 snapshots (default 5)
git pullkeep origin main     # explicit remote/branch instead of @{upstream}
git pullkeep -h              # help  (use -h: `--help` is hijacked by `git help`)
```

### Relayed `git pull` options

| Option | Behaviour |
|---|---|
| `--rebase`, `-r`, `--rebase=merges` | supported; the flavour is relayed verbatim, so `--rebase=merges` still preserves merge commits. Rebase needs a clean tree, so **all** dirty tracked files are parked and restored |
| `--no-rebase` | merge (default; explicitly overrides `pull.rebase` from your config) |
| `--no-ff`, `--ff`, `-X <opt>`, `-s <strategy>`, `--no-edit`, `--signoff` | relayed to the merge |
| `--prune`, `-p`, `--tags`, `--no-tags`, `--force`, `--depth=N`, `--jobs=N` | relayed to the fetch (and to `git pull`) |
| `--ff-only` | **rejected** (exit 21) — parking files requires a local commit, so the update can never be a fast-forward |
| `--squash`, `--no-commit` | **rejected** (exit 21) — there is no commit layer to collapse afterwards |
| `--allow-unrelated-histories`, `--rebase=interactive` | **rejected** — no merge base to analyse / needs a terminal |
| `--all` | **rejected** — `git fetch --all` refuses explicit refspecs, and pullkeep always fetches one named remote |

### Exit codes

| Code | Meaning |
|---|---|
| 0 | success (also "already up to date") |
| 2 | bad command line: unknown option, missing value, or `--undo` without `-y` when no terminal is attached |
| 10 | `--check`: the pull would have to park or resolve files |
| 20 | the run stopped and needs a human: merge/rebase conflicts, or `git pull` itself failed (your changes are intact) |
| 21 | rejected option combination |
| 30 | the repository or its environment cannot be used: not a repo, detached HEAD, no upstream, the fetch failed, or `user.name` / `user.email` are not configured |
| 31 | an unfinished merge/rebase is in progress, **or** a temp commit from an earlier run is still in history |
| 35 | another pullkeep run is already working in this repository (lock held) |
| 40 | internal error (the snapshot ref, if one was created, is kept for `--undo`) |

## How it works

Every writing mode first takes the repository lock (see [Concurrency](#concurrency)), then:

1. `git fetch`, then compute `incoming = base..upstream` and `dirty = HEAD..worktree`.
2. `blocking = incoming ∩ dirty`. Untracked files whose path upstream now owns are moved to
   `.git/pullkeep-aside/<stamp>/`; `modify/delete` conflicts are reported before anything moves.
3. Snapshot the dirty tree into `refs/pullkeep/<stamp>` (a commit object, **not** a stash, and
   the branch does not move) plus the current index tree, so `--undo` is exact.
4. `git add` + `git commit --only -- <blocking paths>`: a temporary commit touching only those.
   With the merge strategy, staged entries outside the overlap are parked too — `git merge`
   refuses to start while the index differs from `HEAD`, even for paths it never touches. With
   `--rebase`, every dirty tracked file is parked, because rebase itself needs a clean tree.
5. `git pull <your options>` — now runs on a clean tree for exactly those paths.
6. `git reset --mixed <new upstream tip>` collapses the temp and merge commits; the previously
   staged paths are then re-staged, so your index state survives the round trip.
7. `git status --porcelain` before/after is diffed and reported, so "did this touch anything
   else?" is a checkable fact rather than a hope.

## Safety & idempotency

A pull that stops halfway (conflicts, Ctrl-C, a killed shell) must never leave a "wip: pullkeep
temp commit" in your permanent history. Four independent guards make that impossible:

1. **The temp commit is labelled.** Its message is `wip: pullkeep temp commit (N file(s))` plus a
   machine-readable trailer `pullkeep-temp: stamp=... base=... upstream=... strategy=...`, and the
   same facts are written to `.git/pullkeep-meta/<stamp>`. Detection therefore needs no state
   file: it survives a `git gc`, a re-clone, or a moved branch.
2. **A later run refuses to start.** Before touching anything, `git pullkeep` scans the last 50
   commits reachable from `HEAD` (`PULLKEEP_SCAN` overrides). If one carries the marker it exits
   **31** and points at `--continue` / `--recover` / `--undo` instead of stacking a second temp
   commit on top of the first.
3. **`--recover` collapses it.** It picks a target only when the answer is unambiguous:
   `@{upstream}` (or the positional `<remote> <branch>`) if that is already merged into `HEAD`,
   otherwise the parent of the temp commit when the pull never completed. Anything else exits 20
   with instructions, because guessing could throw away upstream work. If the temp commit is
   already published to a remote-tracking branch it says so loudly.
4. **Published temp commits are left alone.** If the marker commit is already reachable from a
   remote-tracking branch (pushed by mistake, or merged upstream by a colleague), collapsing it
   would rewrite shared history: the run reports it and carries on instead of blocking forever.

Idempotency in practice:

| Situation | Result |
|---|---|
| run again on an up-to-date branch | `already up to date`, exit 0, no new refs, worktree untouched |
| pull conflicted, you resolved with `git add` + `git commit` | next run exits 31 and refuses; `--recover` collapses it (or `--continue`) |
| pull conflicted, you aborted the merge | `--undo -y` restores the exact pre-pull state |
| process killed between `git pull` and the collapse | next run exits 31; `--continue` or `--recover` finishes the job |
| `--recover` with nothing to collapse | `nothing to recover`, exit 0 |

## Concurrency

`--dry-run` and `--check` only read; every other mode writes. The writing modes (`run`,
`--continue`, `--recover`, `--undo`) therefore take a lock in the **common** git dir first:

```console
$ git pullkeep                      # in one shell
$ git pullkeep                      # at the same time, in another
git-pullkeep: another pullkeep run is already working in this repository:
git-pullkeep:   pid 48162 on workstation since 20261106-114022
git-pullkeep: wait for it to finish; if you are sure it is gone, delete: /repo/.git/pullkeep.lock

$ echo $?
35
```

- The lock is a `mkdir`, which is atomic wherever bash runs — no `flock(1)`, no lock-file race.
- It lives in the common git dir, so it also serialises every `git worktree` checkout of the same
  repository (two separate clones have separate git dirs and never contend).
- A lock whose owner is dead on this host is reclaimed and reported; one with no owner file
  (killed between `mkdir` and the write) is reclaimed after three seconds.
- It is released from an `EXIT` trap, so a conflict or Ctrl-C cannot leave it behind. Even a
  `SIGKILL` is recoverable: the next run sees a dead owner and reclaims the lock.

The two kinds of "another run" failure are different on purpose: **35** means *wait*, **31** means
*this repository needs `--recover` or `--undo` first*.

## Compatibility

- Git ≥ 2.23; tested on 2.39 and 2.51.
- bash ≥ 3.2 — macOS system bash works (no `mapfile`, no associative arrays).
- POSIX utilities only — no `jq`, no `python`, no `perl`.
- `user.name` and `user.email` must be configured (every write path creates a commit object).
  `--dry-run` and `--check` work without them, because they never create one.
- Submodules and linked worktrees are covered by the suite: S15 runs inside a submodule, S16
  inside a linked worktree, where the lock and the metadata are resolved from the common git dir.
- Windows: Git for Windows ≥ 2.30.

## Development

```sh
bash tests/run-tests.sh      # 21 scenarios / 126 assertions in throwaway repositories
shellcheck -s bash git-pullkeep
```

CI runs the suite on Linux, macOS and Windows (Git Bash), plus `shellcheck`, a `dash -n`
check for `install.sh` and a `bash 3.2` parse check.

## License

[MIT](LICENSE)
