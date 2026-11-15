# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.2] - 2026-11-15

### Fixed
- The identity preflight now requires an explicitly configured `user.name` plus `user.email`
  (config, or the `EMAIL` variable). The old `git var GIT_COMMITTER_IDENT` probe behaves
  differently per platform — some builds happily guess `user@host` on a fully unconfigured
  machine, which made the same run exit 0 on one OS and 30 on another.

### Changed
- CI: the bash 3.2 parse check now also covers `tests/run-tests.sh` (GitHub's macOS runner
  parses the suite with `/bin/bash` 3.2, which rejects constructs newer bashes accept).

## [0.1.1] - 2026-11-15

### Fixed
- `--undo` no longer deletes staged new files from the working tree. The pre-run snapshot was
  built with `read-tree HEAD` + `add -u`, which cannot see entries that exist only in the
  index; undo then restored them in the index (A) while `reset --hard` had removed the file
  from disk, leaving a staged-but-deleted (`AD`) state. The snapshot now also captures
  index-only entries, so undo reproduces staged new files — and the staged/worktree two-layer
  state of a file with different staged and worktree content — exactly.

### Changed
- Merge strategy: staged entries outside the overlap are parked in the temporary commit as
  well. `git merge` refuses to start while any index entry differs from HEAD ("Your local
  changes ... would be overwritten by merge"), even for paths the merge never touches, so
  such a pull always failed with exit 20 and needed a manual `--undo`. Staged entries block
  the pull exactly like overlapping edits, so they are parked and restored like one; the run
  now succeeds end to end and reports each extra entry ("+ path (staged entry: ...)").

## [0.1.0] - 2026-11-06

First public release.

### Added
- `git pullkeep`: pull while keeping every uncommitted change. Only the files whose changes
  overlap the incoming commits are parked in a temporary commit; all other dirty files never
  leave the working tree. No stash is created.
- `--undo` / `--abort`: exact rollback from a working-tree snapshot stored in
  `refs/pullkeep/<stamp>` (the branch is not moved while running, so a plain `git pull` can
  still be used if you prefer).
- `--continue` / `--finish`: collapse the temporary and merge commits back into uncommitted
  changes after conflicts were resolved.
- `--dry-run`, `--check` (exit 10 gate for CI), `--no-fetch`, `--keep-backups=N`, `-y`.
- Relayed `git pull` options: `--rebase[=merges]` (the flavour is passed on verbatim, so
  `--rebase=merges` keeps preserving merge commits), `--no-rebase`, `--no-ff`, `-X`, `-s`,
  `--no-edit`, `--signoff`, `--prune`, `--tags`, `--depth=N`, `--jobs=N`, and the usual
  output flags.
- Explicit positional `<remote> [<branch>]` support, so a branch without an upstream works.
- Staged (index) state is preserved across the collapse step.
- `modify/delete` conflicts are reported before anything is moved.
- Untracked files whose path is claimed by upstream are moved to
  `.git/pullkeep-aside/<stamp>/` and restored by `--undo`.
- Documented exit codes (`0/2/10/20/21/30/31/35/40`) and a `git-pullkeep(1)` man page.
- `--recover`: collapse a temporary commit left behind by an interrupted run, without
  guessing a target it cannot justify.
- Temporary commits are labelled `wip: pullkeep temp commit` and carry a `pullkeep-temp:`
  trailer (`stamp`, `base`, `upstream`, `strategy`), mirrored into
  `.git/pullkeep-meta/<stamp>`, so leftovers stay detectable without any state file.
- Bilingual documentation: `README.md` (English, GitHub) and `README_zh.md` (Chinese, Gitee),
  cross-linked at the top of both files.
- One-line installers for POSIX sh and PowerShell, both accepting a raw base URL (so a Gitee
  mirror works end to end), plus a three-OS CI matrix.
- npm distribution: `npm install -g git-pullkeep`, or `npx git-pullkeep` to try it without
  installing. The tarball ships the script, the man page and the docs only; `prepublishOnly`
  re-runs the suite, so a broken tree cannot reach the registry.
- Concurrency guard: the writing modes (`run`, `--continue`, `--recover`, `--undo`) take an
  atomic `mkdir` lock in the common git dir, so two runs in one repository cannot race on the
  index or on `refs/pullkeep/`. A second run exits 35 and names the holder; a lock left by a
  dead process is reclaimed and reported. `--dry-run` / `--check` never take it.
- `.github/workflows/publish.yml`: a `v*` tag first proves that `VERSION` in the script, the
  `package.json` version and the tag itself agree, refuses to publish while the `OWNER`
  placeholder is still present, runs the suite plus shellcheck, and only then publishes with
  npm provenance and attaches the script and man page to a GitHub release.

### Notes
- Exit code 30 covers anything that makes the repository unusable before a run can start: not a
  repository, detached HEAD, no upstream, a failed fetch (network, credentials, a locked remote
  ref), and a missing `user.name` / `user.email`, since every write path creates a commit object.
  `--dry-run` and `--check` never create one, so they work without a configured identity.
- `--dry-run` and `--check` still perform the pre-flight fetch unless `--no-fetch` is given, so
  the analysis always describes a freshly observed upstream. Exit code 20 means "a human has to
  look at this": merge/rebase conflicts, or a `git pull` that failed on its own. Your
  uncommitted changes are kept in either case.
- Idempotency: a run refuses to start (exit 31) while a temp commit from an earlier run is
  still reachable from `HEAD`, so a repeated or interrupted run can never turn the temp commit
  into permanent history. Re-running on an up-to-date branch is a no-op.
- All source comments and runtime messages are ASCII English, so Windows consoles using a
  non-UTF-8 code page (e.g. GBK) stay readable.
- `--ff-only`, `--squash`, `--no-commit`, `--allow-unrelated-histories`, `--all` and
  `--rebase=interactive` are rejected on purpose (exit 21) with a suggested alternative.
- `--rebase` parks *all* dirty tracked files, because rebase itself requires a clean tree.
- Requires Git >= 2.23 and bash >= 3.2; no dependency beyond `git` and POSIX utilities.
- On Windows always type `git pullkeep`: Git for Windows runs the script with its bundled bash.
  Invoking the bare `git-pullkeep` shim that npm installs can pick up WSL's
  `C:\Windows\System32\bash.exe` instead and fail with `No such file or directory`.
- npm is only a delivery channel. Git has no plugin registry: a command is discovered purely by
  the `git-<name>` file being on `PATH` (list them with `git help -a`).

[0.1.2]: https://github.com/aiti-ai/git-pullkeep/releases/tag/v0.1.2
[0.1.1]: https://github.com/aiti-ai/git-pullkeep/releases/tag/v0.1.1
[0.1.0]: https://github.com/aiti-ai/git-pullkeep/releases/tag/v0.1.0
