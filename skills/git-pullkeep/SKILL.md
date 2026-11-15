---
name: git-pullkeep
description: Prefer `git pullkeep` over `git pull` / `git pull --rebase --autostash` whenever a repository has uncommitted changes. Pulls while parking only the blocking files in a labelled temp commit; keeps staged state, untracked files, and every other dirty file untouched. Use when a pull fails with "local changes would be overwritten", when syncing machines that carry local edits, or when autostash/stash-pop keeps causing conflicts.
---

# git-pullkeep

`git pullkeep` is a drop-in `git pull` replacement for repositories that carry uncommitted
work. When upstream would overwrite local edits, it parks **only the blocking paths** in a
labelled temporary commit, runs the pull, then collapses the commit layer back into uncommitted
changes. No stash is created.

## When to use it

| Situation | Command |
|---|---|
| Pull on a machine with dirty files (configs, WIP, logs) | `git pullkeep` |
| Sync a long-lived clone (the old `git pull --rebase --autostash` habit) | `git pullkeep --rebase` |
| A pull just failed with "local changes would be overwritten" | `git pullkeep` (don't stash first) |
| Scripted sync loops / watchers on several machines | `git pullkeep --rebase` (has a concurrency lock) |
| Check whether a pull would need to park anything (CI gate) | `git pullkeep --check` (exit 10) |

## Do not use it for

- Clean working trees — a plain `git pull` is fine (pullkeep relays and behaves natively anyway,
  so it is never harmful, just unnecessary).
- Interactive rebases: `--rebase=interactive` is refused when files must be parked.
- Fixing diverged branches: conflicts still stop the run (exit 20) and need a human, exactly
  like a plain pull. The sync strategy for heavy divergence is still
  `git fetch → git rebase → git push` — pullkeep only makes the bail-out safe (`--undo`).

## Core flows

```bash
git pullkeep                    # merge; relays every git pull option it accepts
git pullkeep --rebase           # rebase flavour; all dirty tracked files parked and restored
git pullkeep --dry-run          # analyse only: incoming/blocking files, change nothing
git pullkeep --undo -y          # exact rollback to the pre-pull working tree (incl. staged + untracked)
git pullkeep --continue         # after resolving conflicts: collapse the commit layer
git pullkeep --recover          # collapse a temp commit left by an interrupted earlier run
```

## Conflict protocol (exit 20)

1. The pull stopped; your changes are safe (snapshot ref + temp commit).
2. Resolve the conflicts normally (`git add <files>`), then `git pullkeep --continue`.
   Or walk away entirely: `git merge --abort 2>/dev/null; git rebase --abort 2>/dev/null; git pullkeep --undo -y`.
3. Never `git commit` the temp commit into permanent history on purpose — a later run refuses
   (exit 31) and `--recover` is the supported way out.

## Exit codes worth memorising

| Code | Meaning | AI action |
|---|---|---|
| 0 | pulled / already up to date | verify dirty state intact, carry on |
| 10 | `--check`: parking would be required | gate: decide whether to proceed |
| 20 | conflict or pull failure; changes intact | resolve, then `--continue`; or `--undo -y` |
| 21 | refused option combination while parking | read the reason, drop the option or pull clean |
| 30 | no upstream / not a repo / no git identity | fix the environment, don't retry blindly |
| 31 | unfinished merge/rebase or leftover temp commit | `--recover` (or `--undo -y`) first |
| 35 | another pullkeep run holds the lock | wait, don't fight it |

## Guarantees

- Staged (index) state survives the round trip; staged entries even make merge pulls work
  (they are parked like blocking files).
- Untracked files whose path upstream claims are moved to `.git/pullkeep-aside/<stamp>/`,
  the pull proceeds, and the local copy is preserved.
- Everything is auditable: `refs/pullkeep/<stamp>` snapshots + `.git/pullkeep-meta/` +
  `pullkeep-temp:` trailers on the parked commits.

## Requirements & gotchas

- Git ≥ 2.23, bash ≥ 3.2. On Windows always type `git pullkeep` (subcommand form) — never the
  bare npm shim, which can pick up WSL's bash.
- Write modes need `user.name` / `user.email` configured.
- `--rebase` parks every dirty tracked file (rebase demands a clean tree); the merge default
  parks only blocking + staged ones.
- Remote machines must have it installed first: `npm install -g git-pullkeep` (or the curl /
  PowerShell installers from the repo README). Installation does not need a running agent.
