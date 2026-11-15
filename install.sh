#!/bin/sh
# git-pullkeep installer for macOS / Linux (and Git Bash on Windows).
#   curl -fsSL https://raw.githubusercontent.com/aiti-ai/git-pullkeep/main/install.sh | sh
# Env:
#   GIT_PULLKEEP_REPO   GitHub owner/repo (default: aiti-ai/git-pullkeep) or a raw base URL,
#                       e.g. https://gitee.com/aiti-ai/git-pullkeep/raw
#   GIT_PULLKEEP_REF    branch or tag to install (default: main)
#   GIT_PULLKEEP_DIR    install directory (default: ~/.local/bin)
set -eu

REPO=${GIT_PULLKEEP_REPO:-aiti-ai/git-pullkeep}
REF=${GIT_PULLKEEP_REF:-main}
DIR=${GIT_PULLKEEP_DIR:-$HOME/.local/bin}

case "$REPO" in
  http://*|https://*) BASE="${REPO%/}/$REF" ;;                                   # explicit raw base (e.g. Gitee mirror)
  *)                  BASE="https://raw.githubusercontent.com/$REPO/$REF" ;;
esac

command -v git >/dev/null 2>&1 || { echo "git-pullkeep: git is required" >&2; exit 1; }

mkdir -p "$DIR"
TMP=$(mktemp "${TMPDIR:-/tmp}/git-pullkeep.XXXXXX")
trap 'rm -f "$TMP"' EXIT

if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$BASE/git-pullkeep" -o "$TMP"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$TMP" "$BASE/git-pullkeep"
else
  echo "git-pullkeep: need curl or wget to download" >&2
  exit 1
fi

# Force LF line endings: a CRLF shebang breaks the script on Linux/macOS.
tr -d '\r' < "$TMP" > "$TMP.lf" && mv "$TMP.lf" "$TMP"

head -n 1 "$TMP" | grep -q '^#!' || { echo "git-pullkeep: download looks wrong" >&2; exit 1; }
chmod +x "$TMP"
mv "$TMP" "$DIR/git-pullkeep"

printf 'installed: %s\n' "$DIR/git-pullkeep"
case ":$PATH:" in
  *":$DIR:"*) ;;
  *) printf '\nNOTE: add it to PATH, e.g.\n  echo '\''export PATH="%s:$PATH"'\'' >> ~/.profile\n' "$DIR" ;;
esac
printf '\nverify with:  git help -a | grep pullkeep\n'
