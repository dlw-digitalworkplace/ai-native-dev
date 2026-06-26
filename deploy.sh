#!/usr/bin/env bash
# deploy.sh — publish the AIND plugin to GitHub (no marketplace).
#   1. builds a root-structured plugin zip from the committed HEAD (git archive),
#   2. uploads it as a GitHub Release asset — stable URL: releases/latest/download/aind.zip,
#   3. publishes aind-flow.html as the GitHub Pages site (this branch, /docs/index.html).
#
# Load the plugin remotely afterwards (no local clone needed):
#   claude --plugin-url https://github.com/<owner>/<repo>/releases/latest/download/aind.zip
#
# Prereqs: a PUBLIC GitHub repo with this committed and an 'origin' remote; `gh` authenticated
# with admin on the repo (for Pages); `git`, `gh`, `jq` installed. Run from the repo root.
#
# Note: the published zip is a SNAPSHOT of HEAD — re-run after changes. Bump the version in
# .claude-plugin/plugin.json for a clean new release tag (otherwise the asset is re-uploaded to
# the existing tag).

set -euo pipefail

die(){ echo "deploy: $*" >&2; exit 1; }
for c in git gh jq; do command -v "$c" >/dev/null 2>&1 || die "missing required command: $c"; done

[[ -f .claude-plugin/plugin.json ]] || die "run from the repo root (.claude-plugin/plugin.json not found)"
git rev-parse HEAD >/dev/null 2>&1 || die "no commits yet — commit the plugin first"

# Released zip must match committed state; the docs/ update below is the only change we make.
if ! git diff --quiet || ! git diff --cached --quiet; then
  die "working tree has uncommitted changes — commit them first so the release matches HEAD"
fi

SLUG="$(gh repo view --json nameWithOwner -q .nameWithOwner)" \
  || die "could not resolve the GitHub repo (is 'origin' a GitHub remote and is gh authed?)"
OWNER="${SLUG%%/*}"; NAME="${SLUG##*/}"
OWNER_LC="$(printf '%s' "$OWNER" | tr '[:upper:]' '[:lower:]')"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
VERSION="$(jq -r '.version // empty' .claude-plugin/plugin.json)"
[[ -n "$VERSION" ]] || die "no \"version\" in .claude-plugin/plugin.json"
TAG="v$VERSION"
ZIP_LATEST="https://github.com/${SLUG}/releases/latest/download/aind.zip"
PAGES_URL="https://${OWNER_LC}.github.io/${NAME}/"

echo "deploy: repo=$SLUG  branch=$BRANCH  version=$VERSION"

# --- 1. Publish the diagram via Pages (this branch, /docs/index.html) ---
mkdir -p docs
cp aind-flow.html docs/index.html
git add docs/index.html
if ! git diff --cached --quiet -- docs/index.html; then
  git commit -q -m "deploy: publish aind-flow.html to Pages (docs/index.html)"
  echo "deploy: committed docs/index.html"
fi
git push -q origin "$BRANCH"

# Enable Pages from this branch /docs if not already configured (idempotent).
if ! gh api "repos/${SLUG}/pages" >/dev/null 2>&1; then
  if printf '{"source":{"branch":"%s","path":"/docs"}}' "$BRANCH" \
      | gh api -X POST "repos/${SLUG}/pages" --input - >/dev/null 2>&1; then
    echo "deploy: enabled GitHub Pages (${BRANCH} /docs)"
  else
    echo "deploy: [WARN] could not auto-enable Pages — enable once in Settings → Pages (source: ${BRANCH} /docs)"
  fi
fi

# --- 2. Build the root-structured plugin zip from HEAD (tracked files, no nesting) ---
rm -f aind.zip
git archive --format=zip -o aind.zip HEAD
echo "deploy: built aind.zip ($(du -h aind.zip | cut -f1))"

# --- 3. Upload as a Release asset (stable releases/latest/download URL) ---
if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" aind.zip --clobber
  echo "deploy: updated release $TAG asset"
else
  gh release create "$TAG" aind.zip --title "AIND plugin $TAG" --notes "AIND plugin $VERSION" --latest
  echo "deploy: created release $TAG"
fi
rm -f aind.zip

echo
echo "deploy: done."
echo "  Plugin (latest):  $ZIP_LATEST"
echo "  Plugin (pinned):  https://github.com/${SLUG}/releases/download/${TAG}/aind.zip"
echo "  Diagram (Pages):  $PAGES_URL   (first enable can take a minute)"
echo
echo "  Load it:  claude --plugin-url $ZIP_LATEST"
