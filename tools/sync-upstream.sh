#!/usr/bin/env bash
#
# sync-upstream.sh
#
# Pulls design/security updates from the upstream Chirpy theme repo
# (cotes2020/jekyll-theme-chirpy) into this fork, while guaranteeing that
# personal customizations listed in .github/sync-upstream/protected-paths.txt
# are never overwritten.
#
# Usage:
#   tools/sync-upstream.sh [branch-name]
#
# What it does:
#   1. Adds/updates a git remote named "upstream" pointing at the
#      canonical theme repo.
#   2. Fetches the upstream default branch.
#   3. Creates (or reuses) a local branch to stage the sync.
#   4. Merges upstream into the branch. Conflicts are expected on files
#      that both sides touched; the script resolves conflicts in
#      protected paths automatically by keeping our version, but leaves
#      real conflicts elsewhere for you to resolve.
#   5. Restores every protected path to the current branch's version,
#      even if the merge changed or removed it cleanly.
#   6. Prints a summary of what changed so you can review before pushing.
#
# This script never pushes or opens a PR itself; it only prepares a
# branch for review. Run it locally, or let the scheduled
# .github/workflows/sync-upstream.yml workflow run it in CI and open a
# PR for you to review.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

UPSTREAM_URL="https://github.com/cotes2020/jekyll-theme-chirpy.git"
UPSTREAM_REMOTE="upstream"
UPSTREAM_BRANCH="master"
PROTECTED_PATHS_FILE=".github/sync-upstream/protected-paths.txt"
SYNC_BRANCH="${1:-sync/upstream-$(date +%Y%m%d)}"

if [ ! -f "$PROTECTED_PATHS_FILE" ]; then
  echo "error: protected paths file not found at $PROTECTED_PATHS_FILE" >&2
  exit 1
fi

# Read protected paths, ignoring blank lines and comments.
mapfile -t PROTECTED_PATHS < <(grep -vE '^\s*(#|$)' "$PROTECTED_PATHS_FILE")

if [ "${#PROTECTED_PATHS[@]}" -eq 0 ]; then
  echo "error: no protected paths configured; refusing to sync" >&2
  exit 1
fi

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"

echo "==> Configuring '$UPSTREAM_REMOTE' remote"
if git remote get-url "$UPSTREAM_REMOTE" >/dev/null 2>&1; then
  git remote set-url "$UPSTREAM_REMOTE" "$UPSTREAM_URL"
else
  git remote add "$UPSTREAM_REMOTE" "$UPSTREAM_URL"
fi

echo "==> Fetching $UPSTREAM_REMOTE/$UPSTREAM_BRANCH"
git fetch "$UPSTREAM_REMOTE" "$UPSTREAM_BRANCH" --depth=1000

if git rev-parse --verify "$SYNC_BRANCH" >/dev/null 2>&1; then
  echo "==> Reusing existing branch $SYNC_BRANCH"
  git checkout "$SYNC_BRANCH"
else
  echo "==> Creating branch $SYNC_BRANCH from $CURRENT_BRANCH"
  git checkout -b "$SYNC_BRANCH"
fi

echo "==> Merging $UPSTREAM_REMOTE/$UPSTREAM_BRANCH into $SYNC_BRANCH"
set +e
git merge --no-edit "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH"
MERGE_STATUS=$?
set -e

if [ $MERGE_STATUS -ne 0 ]; then
  echo "==> Merge produced conflicts; auto-resolving conflicts inside protected paths"
  for path in "${PROTECTED_PATHS[@]}"; do
    if [ -e "$path" ] || git ls-files --error-unmatch "$path" >/dev/null 2>&1; then
      git checkout --ours -- "$path" 2>/dev/null || true
      git add -- "$path" 2>/dev/null || true
    fi
  done

  if git diff --name-only --diff-filter=U | grep -q .; then
    echo ""
    echo "!! Unresolved conflicts remain outside protected paths:"
    git diff --name-only --diff-filter=U
    echo ""
    echo "Resolve them manually, then run:"
    echo "  git add <file> && git commit"
    exit 1
  fi

  git commit --no-edit
fi

echo "==> Restoring protected paths to this fork's versions"
for path in "${PROTECTED_PATHS[@]}"; do
  if git cat-file -e "${CURRENT_BRANCH}:${path}" 2>/dev/null || [ -e "$path" ]; then
    git checkout "$CURRENT_BRANCH" -- "$path" 2>/dev/null || true
  fi
done

if ! git diff --quiet --cached || ! git diff --quiet; then
  git add -A
  if ! git diff --cached --quiet; then
    git commit -m "chore: restore protected paths after upstream sync"
  fi
fi

echo ""
echo "==> Sync complete on branch $SYNC_BRANCH"
echo "==> Files changed vs $CURRENT_BRANCH:"
git diff --name-status "$CURRENT_BRANCH"...HEAD || true

echo ""
echo "Review the diff, then push and open a pull request, e.g.:"
echo "  git push -u origin $SYNC_BRANCH"
