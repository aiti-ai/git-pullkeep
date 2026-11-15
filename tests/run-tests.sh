#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2086,SC2015
#   SC2016/SC2086: the assertions are intentionally eval'd format strings / globs.
#
# Regression suite for git-pullkeep. Everything runs inside throwaway repositories under a
# temp dir, so it never touches the repository you invoke it from.
# Run: bash tests/run-tests.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/../git-pullkeep"
WORKROOT=$(mktemp -d "${TMPDIR:-/tmp}/pullkeep-test.XXXXXX")
trap 'rm -rf "$WORKROOT"' EXIT

PASS=0; FAIL=0
ok()    { printf '  [PASS] %s\n' "$*"; PASS=$((PASS+1)); }
bad()   { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL+1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

mk() { # mk <name>: create the origin.git + seed + work triad
  local d="$WORKROOT/$1"
  mkdir -p "$d"
  git init -q --bare "$d/origin.git"
  git clone -q "$d/origin.git" "$d/seed" 2>/dev/null
  cd "$d/seed" || exit 1
  git config user.email t@t; git config user.name t
  seq 1 20 > a.txt; seq 1 20 > b.txt; seq 1 5 > c.txt
  git add . && git commit -qm init && git branch -q -M main
  git push -q origin main 2>/dev/null
  git clone -q "$d/origin.git" "$d/work" 2>/dev/null
  cd "$d/work" || exit 1
  git config user.email t@t; git config user.name t
  git checkout -q -B main origin/main 2>/dev/null
  git branch -q --set-upstream-to=origin/main main
}

pushseed() { # pushseed <name> <cmd...>: commit inside seed and push to origin
  cd "$WORKROOT/$1/seed" || exit 1
  shift
  "$@" >/dev/null 2>&1
  git add -A >/dev/null 2>&1; git commit -qm up >/dev/null 2>&1; git push -q origin main >/dev/null 2>&1
}

run() { bash "$SCRIPT" "$@"; }

echo "== S1 clean worktree, only behind upstream =="
mk s1
pushseed s1 bash -c 'sed -i "s/^2$/two/" b.txt'
cd "$WORKROOT/s1/work" && run >"$WORKROOT/s1.log" 2>&1
check "pull succeeded" '[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ]'
check "upstream content applied" 'grep -q "^two$" b.txt'

echo "== S2 local and upstream touch the same file, different hunks, plus a third dirty file =="
mk s2
pushseed s2 bash -c 'sed -i "s/^10$/ten/" a.txt; sed -i "s/^3$/three/" b.txt'
cd "$WORKROOT/s2/work" || exit 1
sed -i 's/^1$/ONE-local/' a.txt
sed -i 's/^5$/FIVE-local/' c.txt; echo dirty-extra >> c.txt
before_c=$(cat c.txt)
run >"$WORKROOT/s2.log" 2>&1
check "reached upstream tip" '[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ]'
check "local change kept" 'grep -q "^ONE-local$" a.txt'
check "upstream change applied (a.txt)" 'grep -q "^ten$" a.txt'
check "upstream change applied (b.txt)" 'grep -q "^three$" b.txt'
check "non-blocking dirty file untouched" '[ "$before_c" = "$(cat c.txt)" ]'
check "no leftover MERGE_HEAD" '[ ! -e "$(git rev-parse --absolute-git-dir)/MERGE_HEAD" ]'
check "no stash created" '[ -z "$(git stash list)" ]'
check "blocking file is uncommitted again" 'git status --porcelain | grep -q "^ M a.txt"'
check "backup ref created" '[ -n "$(git for-each-ref refs/pullkeep/)" ]'
check "no temp commit left behind" 'git log --oneline -1 | grep -qv "pullkeep temp commit"'

echo "== S3 local deletion + upstream modification (modify/delete) =="
mk s3
pushseed s3 bash -c 'sed -i "s/^7$/seven/" b.txt'
cd "$WORKROOT/s3/work" || exit 1
rm b.txt; echo extra-local > c.txt
run >"$WORKROOT/s3.log" 2>&1; rc=$?
check "exits 20 (conflict needs a human)" '[ '"$rc"' -eq 20 ]'
check "modify/delete is warned about up front" 'grep -q "modify/delete conflict" "$WORKROOT/s3.log"'
check "hints at --continue/--undo" 'grep -q "pullkeep --continue" "$WORKROOT/s3.log"'
rm -f b.txt; git rm -q --cached b.txt 2>/dev/null
git commit -qm "merge: keep local deletion" >/dev/null 2>&1
run --continue >"$WORKROOT/s3b.log" 2>&1
check "--continue reaches upstream tip" '[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ]'
check "local deletion kept" 'git status --porcelain | grep -q "^ D b.txt"'
check "unrelated dirty file kept" 'grep -q "extra-local" c.txt'

echo "== S3b --undo after a conflict must roll back losslessly =="
mk s3c
pushseed s3c bash -c 'sed -i "s/^7$/seven/" b.txt'
cd "$WORKROOT/s3c/work" || exit 1
h_before=$(git rev-parse HEAD)
rm b.txt; echo extra-local > c.txt; sed -i 's/^1$/ONE-local/' a.txt
run >/dev/null 2>&1
run --undo -y >"$WORKROOT/s3c-undo.log" 2>&1
check "HEAD back to pre-pull" '[ "$h_before" = "$(git rev-parse HEAD)" ]'
check "local deletion restored" 'git status --porcelain | grep -q "^ D b.txt"'
check "every dirty file kept" 'grep -q "extra-local" c.txt && grep -q "^ONE-local$" a.txt'
check "no leftover MERGE_HEAD" '[ ! -e "$(git rev-parse --absolute-git-dir)/MERGE_HEAD" ]'

echo "== S4 untracked file with the same name as a new upstream file =="
mk s4
pushseed s4 bash -c 'echo upstream-new > d.txt'
cd "$WORKROOT/s4/work" || exit 1
echo "my-local-draft" > d.txt
run >"$WORKROOT/s4.log" 2>&1
check "pull succeeded" '[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ]'
check "upstream version wins" 'grep -q "upstream-new" d.txt'
check "local version parked aside" '[ -n "$(grep -rl "my-local-draft" .git/pullkeep-aside/ 2>/dev/null)" ]'
run --undo -y >"$WORKROOT/s4-undo.log" 2>&1
check "--undo brings the local draft back" 'grep -q "my-local-draft" d.txt'

echo "== S5 --dry-run / --check change nothing =="
mk s5
pushseed s5 bash -c 'sed -i "s/^10$/ten/" a.txt'
cd "$WORKROOT/s5/work" || exit 1
sed -i 's/^1$/ONE-local/' a.txt
h_before=$(git rev-parse HEAD); st_before=$(git status --porcelain)
run --dry-run >"$WORKROOT/s5.log" 2>&1
check "HEAD untouched" '[ "$h_before" = "$(git rev-parse HEAD)" ]'
check "worktree untouched" '[ "$st_before" = "$(git status --porcelain)" ]'
check "blocking file detected" 'grep -q "1 file(s) overlap upstream" "$WORKROOT/s5.log"'
run --check >"$WORKROOT/s5c.log" 2>&1; rc=$?
check "--check exits 10" '[ '"$rc"' -eq 10 ]'
cd "$WORKROOT/s1/work" 2>/dev/null && { run --check >/dev/null 2>&1; check "--check exits 0 on a clean tree" '[ '"$?"' -eq 0 ]'; }

echo "== S6 --undo restores the dirty worktree exactly =="
mk s6
pushseed s6 bash -c 'sed -i "s/^10$/ten/" a.txt'
cd "$WORKROOT/s6/work" || exit 1
sed -i 's/^1$/ONE-local/' a.txt
sed -i 's/^5$/FIVE-local/' c.txt; echo dirty-extra >> c.txt
h_before=$(git rev-parse HEAD); st_before=$(git status --porcelain)
run >/dev/null 2>&1
run --undo -y >"$WORKROOT/s6.log" 2>&1
check "HEAD back to pre-pull" '[ "$h_before" = "$(git rev-parse HEAD)" ]'
check "blocking file change still there" 'grep -q "^ONE-local$" a.txt'
check "unrelated dirty file still there" 'grep -q "^FIVE-local$" c.txt && grep -q "dirty-extra" c.txt'
check "status identical to pre-pull" '[ "$st_before" = "$(git status --porcelain)" ]'
check "backup ref cleaned up" '[ -z "$(git for-each-ref refs/pullkeep/)" ]'

echo "== S7 --rebase: every dirty file steps aside and comes back =="
mk s7
pushseed s7 bash -c 'sed -i "s/^10$/ten/" a.txt'
cd "$WORKROOT/s7/work" || exit 1
sed -i 's/^1$/ONE-local/' a.txt
sed -i 's/^5$/FIVE-local/' c.txt
run --rebase >"$WORKROOT/s7.log" 2>&1; rc=$?
check "exits 0" '[ '"$rc"' -eq 0 ]'
check "reached upstream tip" '[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ]'
check "local change kept (a.txt)" 'grep -q "^ONE-local$" a.txt'
check "upstream change applied (a.txt)" 'grep -q "^ten$" a.txt'
check "non-blocking dirty file restored too (c.txt)" 'grep -q "^FIVE-local$" c.txt'
check "still uncommitted" 'git status --porcelain | grep -q "^ M a.txt"'
check "no stash created" '[ -z "$(git stash list)" ]'
check "report says rebase" 'grep -q "strategy    : rebase" "$WORKROOT/s7.log"'

# --rebase=merges must not be downgraded to a plain rebase (that would silently flatten the
# merge commits it is meant to preserve), so the flavour has to reach `git pull` verbatim.
pushseed s7 bash -c 'sed -i "s/^ten$/eleven/" a.txt'
cd "$WORKROOT/s7/work" || exit 1
GIT_TRACE=1 bash "$SCRIPT" --rebase=merges >"$WORKROOT/s7b.log" 2>&1; rc=$?
check "--rebase=merges exits 0" '[ '"$rc"' -eq 0 ]'
check "the merges flavour reaches git pull verbatim" 'grep -q "pull --rebase=merges" "$WORKROOT/s7b.log"'
check "--rebase=merges still keeps the local edit" 'grep -q "^ONE-local$" a.txt'

echo "== S8 --ff-only / --squash are rejected (exit 21) =="
mk s8
pushseed s8 bash -c 'sed -i "s/^10$/ten/" a.txt'
cd "$WORKROOT/s8/work" || exit 1
sed -i 's/^1$/ONE-local/' a.txt
h_before=$(git rev-parse HEAD)
run --ff-only >"$WORKROOT/s8.log" 2>&1; rc=$?
check "--ff-only exits 21" '[ '"$rc"' -eq 21 ]'
check "--ff-only suggests an alternative" 'grep -q "git pull --ff-only --autostash" "$WORKROOT/s8.log"'
check "--ff-only left the repo alone" '[ "$h_before" = "$(git rev-parse HEAD)" ]'
run --squash >"$WORKROOT/s8b.log" 2>&1; rc=$?
check "--squash exits 21" '[ '"$rc"' -eq 21 ]'
run --all >"$WORKROOT/s8c.log" 2>&1; rc=$?
check "--all exits 21" '[ '"$rc"' -eq 21 ]'
run --bogus-option >/dev/null 2>&1; rc=$?
check "unknown option exits 2" '[ '"$rc"' -eq 2 ]'

echo "== S9 index fidelity: staged state is replayed after the collapse =="
mk s9
pushseed s9 bash -c 'sed -i "s/^10$/ten/" a.txt'
cd "$WORKROOT/s9/work" || exit 1
sed -i 's/^1$/ONE-local/' a.txt
sed -i 's/^5$/FIVE-local/' c.txt
git add a.txt                      # stage a.txt only; c.txt stays unstaged
run >"$WORKROOT/s9.log" 2>&1
check "a.txt is still staged" 'git status --porcelain | grep -q "^M  a.txt"'
check "a.txt holds both local and upstream changes" 'grep -q "^ONE-local$" a.txt && grep -q "^ten$" a.txt'
check "staged content is the local change" 'git diff --cached -- a.txt | grep -q "^+ONE-local$"'
check "c.txt is still unstaged" 'git status --porcelain | grep -q "^ M c.txt"'
check "exactly one file staged" '[ "$(git diff --cached --name-only | wc -l | tr -d " ")" -eq 1 ]'

echo "== S10 --continue (alias of --finish) also replays the staged state =="
mk s10
pushseed s10 bash -c 'sed -i "s/^7$/seven/" b.txt'
cd "$WORKROOT/s10/work" || exit 1
rm b.txt; git add -A b.txt          # stage the deletion, then park it
run >/dev/null 2>&1
rm -f b.txt; git rm -q --cached b.txt 2>/dev/null; git commit -qm "merge: keep deletion" >/dev/null 2>&1
run --continue >"$WORKROOT/s10.log" 2>&1
check "--continue reaches upstream tip" '[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ]'
check "--continue keeps the staged deletion" 'git status --porcelain | grep -q "^D  b.txt"'

echo "== S11 --no-fetch uses the existing tracking ref =="
mk s11
pushseed s11 bash -c 'sed -i "s/^10$/ten/" a.txt'
cd "$WORKROOT/s11/work" || exit 1
git fetch -q origin
sed -i 's/^1$/ONE-local/' a.txt
run --no-fetch >"$WORKROOT/s11.log" 2>&1; rc=$?
check "exits 0" '[ '"$rc"' -eq 0 ]'
check "reached upstream tip" '[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ]'
check "local change kept" 'grep -q "^ONE-local$" a.txt'

echo "== S12 --keep-backups caps the number of snapshots =="
mk s12
pushseed s12 bash -c 'sed -i "s/^10$/ten/" a.txt'
cd "$WORKROOT/s12/work" || exit 1
sed -i 's/^1$/ONE-local/' a.txt
run --keep-backups=1 >/dev/null 2>&1
pushseed s12 bash -c 'sed -i "s/^11$/eleven/" a.txt'
cd "$WORKROOT/s12/work" || exit 1
sed -i 's/^2$/TWO-local/' a.txt
run --keep-backups=1 >/dev/null 2>&1
check "only one backup kept" '[ "$(git for-each-ref refs/pullkeep/ | wc -l | tr -d " ")" -eq 1 ]'
check "both upstream changes applied" 'grep -q "^ten$" a.txt && grep -q "^eleven$" a.txt'
check "both local changes kept" 'grep -q "^ONE-local$" a.txt && grep -q "^TWO-local$" a.txt'

echo "== S13 positional <remote> [<branch>] =="
mk s13
pushseed s13 bash -c 'sed -i "s/^10$/ten/" a.txt'
cd "$WORKROOT/s13/work" || exit 1
sed -i 's/^1$/ONE-local/' a.txt
git branch -q --unset-upstream 2>/dev/null
run origin main >"$WORKROOT/s13.log" 2>&1; rc=$?
check "works without an upstream branch" '[ '"$rc"' -eq 0 ]'
check "reached upstream tip" '[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ]'
check "local change kept" 'grep -q "^ONE-local$" a.txt'

echo "== S14 the temp commit is tagged and detectable =="
mk s14
pushseed s14 bash -c 'sed -i "s/^7$/seven/" b.txt'
cd "$WORKROOT/s14/work" || exit 1
rm b.txt
run >"$WORKROOT/s14.log" 2>&1; rc=$?
check "conflict exits 20" '[ '"$rc"' -eq 20 ]'
check "temp commit carries the marker" 'git log -n 5 --format=%s | grep -qF "wip: pullkeep temp commit"'
check "temp commit carries the trailer" 'git log -1 --format=%B HEAD | grep -q "^pullkeep-temp: .*stamp=.*base=.*upstream="'
check "parent of the temp commit is the pre-pull HEAD" 'git log -1 --format=%B HEAD | grep -q " base=$(git rev-parse HEAD^)"'

# Resolve by hand and commit the merge, which is what a user normally does.
rm -f b.txt; git rm -q --cached b.txt 2>/dev/null
git commit -qm "merge: keep local deletion" >/dev/null 2>&1
check "merge state is gone after the manual commit" '[ ! -e "$(git rev-parse --absolute-git-dir)/MERGE_HEAD" ]'
h_before=$(git rev-parse HEAD); refs_before=$(git for-each-ref refs/pullkeep/ | wc -l | tr -d " ")

# Running again must refuse instead of stacking a second temp commit on top.
run >"$WORKROOT/s15.log" 2>&1; rc=$?
check "re-running after a manual resolve exits 31" '[ '"$rc"' -eq 31 ]'
check "it names the leftover temp commit" 'grep -q "temporary commit from an earlier run" "$WORKROOT/s15.log"'
check "it points at --continue / --recover / --undo" 'grep -q "pullkeep --recover" "$WORKROOT/s15.log" && grep -q "pullkeep --undo -y" "$WORKROOT/s15.log"'
check "it changed nothing" '[ "$h_before" = "$(git rev-parse HEAD)" ] && [ "$refs_before" = "$(git for-each-ref refs/pullkeep/ | wc -l | tr -d " ")" ]'

# --recover is the idempotent way out: the temp commit becomes uncommitted changes again.
run --recover >"$WORKROOT/s16.log" 2>&1; rc=$?
check "--recover exits 0" '[ '"$rc"' -eq 0 ]'
check "--recover reaches the upstream tip" '[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ]'
check "--recover keeps the local deletion uncommitted" 'git status --porcelain | grep -q "^ D b.txt"'
check "no temp commit left in history" '! git log -n 10 --format=%s | grep -qF "wip: pullkeep temp commit"'
check "--recover is idempotent (nothing left to do)" 'run --recover >"$WORKROOT/s17.log" 2>&1; grep -q "nothing to recover" "$WORKROOT/s17.log"'

# A plain re-run after a successful pull must be a no-op.
cd "$WORKROOT/s1/work" 2>/dev/null || exit 1
refs_before=$(git for-each-ref refs/pullkeep/ | wc -l | tr -d " "); st_before=$(git status --porcelain)
run >"$WORKROOT/s18.log" 2>&1; rc=$?
check "re-running on an up-to-date branch exits 0" '[ '"$rc"' -eq 0 ]'
check "it reports already up to date" 'grep -q "already up to date" "$WORKROOT/s18.log"'
check "it creates no new backup" '[ "$refs_before" = "$(git for-each-ref refs/pullkeep/ | wc -l | tr -d " ")" ]'
check "it leaves the worktree alone" '[ "$st_before" = "$(git status --porcelain)" ]'

echo "== S15 a submodule: the cycle runs inside the module's own git dir =="
mk s15
mkdir -p "$WORKROOT/s15/subrepo"
cd "$WORKROOT/s15/subrepo" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t
seq 1 5 > m.txt && git add m.txt && git commit -qm init
git init -q --bare --initial-branch=main "$WORKROOT/s15/sub-origin.git"
git remote add origin "$WORKROOT/s15/sub-origin.git" && git push -q -u origin main
cd "$WORKROOT/s15/work" || exit 1
git -c protocol.file.allow=always submodule add -q "$WORKROOT/s15/sub-origin.git" mod 2>/dev/null
cd "$WORKROOT/s15/work/mod" || exit 1
git config user.email t@t; git config user.name t
git checkout -q -B main origin/main 2>/dev/null
git branch -q --set-upstream-to=origin/main main 2>/dev/null
git clone -q "$WORKROOT/s15/sub-origin.git" "$WORKROOT/s15/sub2" 2>/dev/null
cd "$WORKROOT/s15/sub2" || exit 1
git config user.email t@t; git config user.name t
sed -i 's/^5$/five/' m.txt && git commit -qam up && git push -q origin main
cd "$WORKROOT/s15/work/mod" || exit 1
sed -i 's/^1$/ONE-local/' m.txt
run >"$WORKROOT/s15.log" 2>&1; rc=$?
check "pullkeep works inside a submodule" '[ '"$rc"' -eq 0 ]'
check "both changes are present" 'grep -q "^ONE-local$" m.txt && grep -q "^five$" m.txt'
check "the local edit is uncommitted again" 'git status --porcelain | grep -q "^ M m.txt"'
check "the metadata sits in the module git dir" '[ -d "$(git rev-parse --absolute-git-dir)/pullkeep-meta" ]'
check "no lock left behind" '[ ! -e "$(git rev-parse --git-common-dir)/pullkeep.lock" ]'

echo "== S16 linked worktree: shared refs, shared lock, shared metadata =="
mk s16
pushseed s16 bash -c 'sed -i "s/^10$/ten/" a.txt'
cd "$WORKROOT/s16/work" || exit 1
git worktree add -q -B wt ../wt 2>/dev/null
cd "$WORKROOT/s16/wt" || exit 1
git branch -q --set-upstream-to=origin/main wt 2>/dev/null
sed -i 's/^1$/ONE-local/' a.txt
run >"$WORKROOT/s16.log" 2>&1; rc=$?
check "a linked worktree can pull too" '[ '"$rc"' -eq 0 ]'
check "both changes are present" 'grep -q "^ONE-local$" a.txt && grep -q "^ten$" a.txt'
check "the snapshot ref is visible from the main checkout" '[ -n "$(git -C "$WORKROOT/s16/work" for-each-ref refs/pullkeep/)" ]'
check "the metadata is in the common git dir" '[ -d "$(git rev-parse --git-common-dir)/pullkeep-meta" ]'
check "the lock is in the common dir and released" '[ ! -e "$(git rev-parse --git-common-dir)/pullkeep.lock" ]'

echo "== S17 an unreadable remote is a 30, not a 20 =="
mk s17
pushseed s17 bash -c 'sed -i "s/^10$/ten/" a.txt'
cd "$WORKROOT/s17/work" || exit 1
sed -i 's/^1$/ONE-local/' a.txt
git remote set-url origin "$WORKROOT/s17/missing.git"
h_before=$(git rev-parse HEAD); st_before=$(git status --porcelain)
run >"$WORKROOT/s17.log" 2>&1; rc=$?
check "a failed fetch exits 30" '[ '"$rc"' -eq 30 ]'
check "it says nothing was changed" 'grep -q "Nothing was changed" "$WORKROOT/s17.log"'
check "it suggests --no-fetch" 'grep -q -- "--no-fetch" "$WORKROOT/s17.log"'
check "HEAD and the worktree are untouched" '[ "$h_before" = "$(git rev-parse HEAD)" ] && [ "$st_before" = "$(git status --porcelain)" ]'
check "the lock was released" '[ ! -e "$(git rev-parse --git-common-dir)/pullkeep.lock" ]'

echo "== S18 preconditions: a concurrent run is locked out, a missing identity is reported =="
mk s18
pushseed s18 bash -c 'sed -i "s/^10$/ten/" a.txt'
cd "$WORKROOT/s18/work" || exit 1
sed -i 's/^1$/ONE-local/' a.txt
gcd=$(git rev-parse --git-common-dir)
gcd=$(cd "$gcd" && pwd)
mkdir -p "$gcd/pullkeep.lock"
printf '%s %s %s\n' "$$" "$(hostname 2>/dev/null || echo unknown)" "held-by-the-test" >"$gcd/pullkeep.lock/owner"
h_before=$(git rev-parse HEAD)
run >"$WORKROOT/s18a.log" 2>&1; rc=$?
check "a held lock exits 35" '[ '"$rc"' -eq 35 ]'
check "it names the holder" 'grep -q "held-by-the-test" "$WORKROOT/s18a.log"'
check "the blocked run changed nothing" '[ "$h_before" = "$(git rev-parse HEAD)" ]'
dead=999999
while kill -0 "$dead" 2>/dev/null; do dead=$((dead+1)); done
printf '%s %s %s\n' "$dead" "$(hostname 2>/dev/null || echo unknown)" "stale" >"$gcd/pullkeep.lock/owner"
run >"$WORKROOT/s18b.log" 2>&1; rc=$?
check "a lock from a dead pid is reclaimed" '[ '"$rc"' -eq 0 ]'
check "the reclaim is announced" 'grep -q "stale lock" "$WORKROOT/s18b.log"'
check "no lock survives a successful run" '[ ! -d "$gcd/pullkeep.lock" ]'

# ---- a commit object needs user.name/user.email; --dry-run must still work without them
idir="$WORKROOT/s18i"
mkdir -p "$idir/nohome"
git init -q --bare --initial-branch=main "$idir/origin.git"
git clone -q "$idir/origin.git" "$idir/seed" 2>/dev/null
cd "$idir/seed" || exit 1
git config user.email t@t; git config user.name t
seq 1 10 > a.txt; git add a.txt; git commit -qm init; git push -q origin main
git clone -q "$idir/origin.git" "$idir/work" 2>/dev/null
git checkout -q -B main origin/main; git branch -q --set-upstream-to=origin/main main
sed -i 's/^10$/ten/' a.txt && git commit -qam up && git push -q origin main
cd "$idir/work" || exit 1
sed -i 's/^1$/ONE-local/' a.txt
noident() {
  env -u EMAIL -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL \
      HOME="$idir/nohome" GIT_CONFIG_GLOBAL="$idir/nohome/gitconfig" \
      GIT_CONFIG_SYSTEM="$idir/nohome/system-gitconfig" bash "$SCRIPT" "$@"
}
noident --dry-run >"$WORKROOT/s18c.log" 2>&1; rc=$?
check "--dry-run needs no identity" '[ '"$rc"' -eq 0 ]'
noident >"$WORKROOT/s18d.log" 2>&1; rc=$?
check "a missing identity exits 30" '[ '"$rc"' -eq 30 ]'
check "it tells you how to fix it" 'grep -q "git config user.email" "$WORKROOT/s18d.log"'
check "nothing was parked" '! git log -n 5 --format=%s | grep -qF "wip: pullkeep temp commit"'
check "the local edit is still there" 'grep -q "^ONE-local$" a.txt'

echo "== S19 an already published temp commit must not block future runs =="
mk s19
pushseed s19 bash -c 'sed -i "s/^7$/seven/" b.txt'
cd "$WORKROOT/s19/work" || exit 1
rm b.txt
run >/dev/null 2>&1
rm -f b.txt; git rm -q --cached b.txt 2>/dev/null
git commit -qm "merge: keep deletion" >/dev/null 2>&1
git push -q origin main >/dev/null 2>&1
run >"$WORKROOT/s19.log" 2>&1; rc=$?
check "a pushed temp commit does not block the run" '[ '"$rc"' -eq 0 ]'
check "it is reported as already published" 'grep -q "already published" "$WORKROOT/s19.log"'
check "the run still changes nothing" 'grep -q "already up to date" "$WORKROOT/s19.log"'
run --recover >"$WORKROOT/s19r.log" 2>&1; rc=$?
check "--recover leaves published ones alone" '[ '"$rc"' -eq 0 ] && grep -q "already published" "$WORKROOT/s19r.log"'
check "the published temp commit is untouched" 'git log -n 10 --format=%s | grep -qF "wip: pullkeep temp commit"'

echo "== S20 packaging: the npm metadata must stay in sync with the script =="
pkgjson="$HERE/../package.json"
publishwf="$HERE/../.github/workflows/publish.yml"
pkgver=$(sed -n 's/^VERSION=//p' "$SCRIPT" | head -n 1)
check "package.json sits next to the script" '[ -f "$pkgjson" ]'
check "its version matches VERSION=$pkgver" 'grep -qF "\"version\": \"$pkgver\"," "$pkgjson"'
check "bin maps git-pullkeep to the script" 'grep -qF "\"./git-pullkeep\"" "$pkgjson"'
check "the man page is declared" 'grep -qF "man/git-pullkeep.1" "$pkgjson"'
check "the tarball ships the Chinese readme" 'grep -qF "README_zh.md" "$pkgjson"'
check "prepublishOnly re-runs this suite" 'grep -qF "bash tests/run-tests.sh" "$pkgjson"'
check "the publish workflow re-runs this suite too" 'grep -qF "bash tests/run-tests.sh" "$publishwf"'
check "only a tag can reach the registry" 'grep -qF "github.ref_type" "$publishwf"'
check "--version reports the packaged version" 'bash "$SCRIPT" --version | grep -qF "$pkgver"'

echo "== S22 merge mode parks staged entries too (a merge refuses while the index differs from HEAD) =="
mk s22
pushseed s22 bash -c 'sed -i "s/^2$/two-up/" a.txt'
cd "$WORKROOT/s22/work" || exit 1
echo "staged-new" > staged.txt; git add staged.txt   # staged entry outside the overlap
run >"$WORKROOT/s22.log" 2>&1; rc=$?
check "the pull succeeds despite the unrelated staged entry" '[ '"$rc"' -eq 0 ]'
check "the staged file is reported as parked" 'grep -q "staged entry: a merge refuses" "$WORKROOT/s22.log"'
check "upstream content applied" 'grep -q "^two-up$" a.txt'
check "the staged entry is still staged afterwards" '[ "$(git status --porcelain staged.txt)" = "A  staged.txt" ]'
check "no temp commit residue" '! git log -n 5 --format=%s | grep -qF "wip: pullkeep temp commit"'

echo "== S23 --undo restores a staged new file exactly (file present, still staged) =="
mk s23
pushseed s23 bash -c 'sed -i "s/^2$/two-up/" a.txt'
cd "$WORKROOT/s23/work" || exit 1
sed -i 's/^2$/two-local/' a.txt              # same-line conflict with upstream
echo "staged-new" > staged.txt; git add staged.txt
run >"$WORKROOT/s23.log" 2>&1; rc=$?   # conflicts on purpose
check "the run stops for the conflict" '[ '"$rc"' -eq 20 ]'
run --undo -y >"$WORKROOT/s23u.log" 2>&1; rc=$?
check "--undo succeeds" '[ '"$rc"' -eq 0 ]'
check "the staged file is back on disk" '[ -f staged.txt ]'
check "the staged file is still staged (not A+deleted)" '[ "$(git status --porcelain staged.txt)" = "A  staged.txt" ]'

echo "== S24 --undo restores the two-layer staged/worktree state of one file =="
mk s24
pushseed s24 bash -c 'echo tail >> a.txt'
cd "$WORKROOT/s24/work" || exit 1
printf 'STAGED-VERSION\n' > a.txt; git add a.txt
printf 'WORKTREE-VERSION\n' > a.txt
run >/dev/null 2>&1
run --undo -y >/dev/null 2>&1
check "the index layer is the staged version" '[ "$(git show :a.txt)" = "STAGED-VERSION" ]'
check "the worktree layer is the worktree version" '[ "$(cat a.txt)" = "WORKTREE-VERSION" ]'

echo ""
echo "==== RESULT: PASS=$PASS FAIL=$FAIL ===="
[ "$FAIL" -eq 0 ]
