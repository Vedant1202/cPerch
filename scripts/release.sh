#!/usr/bin/env bash
# cPerch — one-command release.
#
#   scripts/release.sh X.Y.Z [--dry-run]
#
# Bumps build.sh VERSION, stamps CHANGELOG ([Unreleased] -> [X.Y.Z] - <today>, with a fresh
# empty [Unreleased]), commits "release: vX.Y.Z", creates an annotated tag vX.Y.Z, and pushes
# main + the tag. The tag push triggers .github/workflows/release.yml, which builds the app and
# publishes the GitHub Release (zip + DMG) with this version's changelog section as the notes.
#
# --dry-run previews the edits and the tag without committing or pushing (and skips the
# branch/remote guards so you can preview from any branch).
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root

VERSION=""
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    *) VERSION="$arg" ;;
  esac
done

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "✗ usage: scripts/release.sh X.Y.Z [--dry-run]   (semantic version, e.g. 0.6.0)" >&2
  exit 2
fi
TAG="v$VERSION"
TODAY="$(date +%Y-%m-%d)"

grep -q '^## \[Unreleased\]' CHANGELOG.md || { echo "✗ CHANGELOG.md has no [Unreleased] section" >&2; exit 1; }

if ! $DRY_RUN; then
  [ "$(git branch --show-current)" = "main" ] || { echo "✗ must be on main (currently on $(git branch --show-current))" >&2; exit 1; }
  [ -z "$(git status --porcelain)" ] || { echo "✗ working tree is not clean — commit or stash first" >&2; exit 1; }
  git fetch -q origin
  [ "$(git rev-parse @)" = "$(git rev-parse '@{u}')" ] || { echo "✗ local main is out of sync with origin/main — pull/push first" >&2; exit 1; }
  git rev-parse "$TAG" >/dev/null 2>&1 && { echo "✗ tag $TAG already exists" >&2; exit 1; }
fi

echo "▸ Release $TAG  ($TODAY)$($DRY_RUN && echo '   [dry-run]')"

# 1) build.sh VERSION
NEW_BUILD="$(sed -E "s/^VERSION=\"[0-9]+\.[0-9]+\.[0-9]+\"/VERSION=\"$VERSION\"/" build.sh)"

# 2) CHANGELOG: replace the [Unreleased] heading with a fresh empty [Unreleased] + a dated [X.Y.Z],
#    leaving the existing entries beneath the new version heading.
NEW_CHANGELOG="$(awk -v ver="$VERSION" -v date="$TODAY" '
  /^## \[Unreleased\]/ && !done {
    print "## [Unreleased]"; print ""; print "## [" ver "] - " date; done = 1; next
  }
  { print }
' CHANGELOG.md)"

if $DRY_RUN; then
  echo "── build.sh ──"; printf '%s\n' "$NEW_BUILD" | grep '^VERSION='
  echo "── CHANGELOG.md (head) ──"; printf '%s\n' "$NEW_CHANGELOG" | sed -n '7,20p'
  echo "── would commit \"release: $TAG\", tag $TAG, push origin main + $TAG ──"
  exit 0
fi

printf '%s\n' "$NEW_BUILD" > build.sh
printf '%s\n' "$NEW_CHANGELOG" > CHANGELOG.md
git add build.sh CHANGELOG.md
git commit -m "release: $TAG"
git tag -a "$TAG" -m "cPerch $VERSION"
git push origin main
git push origin "$TAG"

echo "✓ pushed $TAG — the release workflow will build and publish it:"
echo "  https://github.com/Vedant1202/cPerch/actions"
