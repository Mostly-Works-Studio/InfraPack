#!/usr/bin/env bash
# Cut a release: bump VERSION and commit. Pushing that commit runs CI, and if
# lint, smoke and the full catalog boot are green, the same workflow tags
# vX.Y.Z, builds the console image, publishes the GitHub release and updates
# the Homebrew tap. No manual tagging.
#
#   scripts/release.sh 0.2.0            # bump + commit
#   git push                            # CI → release
#
#   scripts/release.sh formula 0.2.0    # print the tap formula for a tag that
#                                       # already exists on GitHub (sha256 filled in)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
REPO="Mostly-Works-Studio/infrapack"

formula() {
  local v="$1" url sha
  url="https://github.com/$REPO/archive/refs/tags/v$v.tar.gz"
  sha="$(curl -fsSL "$url" | shasum -a 256 | cut -d' ' -f1)" || { echo "cannot fetch $url" >&2; exit 1; }
  sed -e "s/__VERSION__/$v/g" -e "s/__SHA256__/$sha/g" "$HERE/packaging/homebrew/infrapack.rb"
}

case "${1:-}" in
  formula) formula "${2:?version}"; exit 0 ;;
  "") echo "usage: scripts/release.sh <version> | formula <version>" >&2; exit 1 ;;
esac

v="$1"
[[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must look like 1.2.3" >&2; exit 1; }
cd "$HERE"
[[ -z "$(git status --porcelain)" ]] || { echo "working tree is not clean" >&2; exit 1; }
bash -n bin/infrapack
python3 -m py_compile console/*.py
git rev-parse -q --verify "refs/tags/v$v" >/dev/null && { echo "v$v is already released" >&2; exit 1; }
git ls-remote --exit-code --tags origin "refs/tags/v$v" >/dev/null 2>&1 && { echo "v$v is already released (remote tag)" >&2; exit 1; }
[[ "$(tr -d '[:space:]' < VERSION)" != "$v" ]] || { echo "VERSION is already $v and not released — just git push" >&2; exit 0; }
printf '%s\n' "$v" > VERSION
git add VERSION
git commit -q -m "release v$v"
echo "VERSION → $v committed. Now: git push   (CI runs, then releases v$v if green)"
