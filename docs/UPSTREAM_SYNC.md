# Keeping This Fork in Sync With Upstream Chirpy

This repository is a **direct fork** of [`cotes2020/jekyll-theme-chirpy`](https://github.com/cotes2020/jekyll-theme-chirpy)
(rather than consuming the theme as a gem), so that design updates and
personal customizations live side by side. That makes it easy to
customize, but it also means a naive `git pull`/merge from upstream can
silently overwrite personal settings such as `_config.yml`, `_data/`,
`_posts/`, branding files, and this fork's own CI workflows.

The `tools/sync-upstream.sh` script and the `Sync Upstream Theme`
GitHub Actions workflow solve this by merging upstream's design and
security fixes while **guaranteeing protected paths are always
restored to your version**.

## How it works

1. **Protected paths list** — [`\.github/sync-upstream/protected-paths.txt`](../.github/sync-upstream/protected-paths.txt)
   enumerates every file/directory that is a personal customization and
   must never be replaced by an upstream sync (site config, content,
   branding, and this fork's own docs/CI).
2. **`tools/sync-upstream.sh`**:
   - Adds/updates a git remote named `upstream` pointing at
     `cotes2020/jekyll-theme-chirpy`.
   - Fetches the upstream `master` branch.
   - Creates a `sync/upstream-YYYYMMDD` branch and merges upstream into it.
   - If the merge conflicts on a protected path, keeps your version
     automatically; real conflicts outside protected paths are left for
     you to resolve manually.
   - After the merge (clean or resolved), restores **every** protected
     path to your current branch's version, even if upstream changed
     or deleted it, so your settings can never be silently overwritten.
   - Prints a summary of the files that changed for review.
3. **`.github/workflows/sync-upstream.yml`** runs the script on a
   weekly schedule (and on demand via `workflow_dispatch`), pushes the
   resulting branch, and opens a pull request labeled `upstream-sync`
   for you to review and merge — nothing is auto-merged.

## Running it locally

```bash
tools/sync-upstream.sh
# or with a custom branch name
tools/sync-upstream.sh sync/upstream-manual-check
```

Review the diff (`git diff <base>...HEAD`), run the site locally to
confirm the build still works, then push and open a PR.

## Adding a new protected path

Whenever you add a new personal customization (a new config file, a
custom `_data` file, a fork-specific workflow, etc.), add its path to
`.github/sync-upstream/protected-paths.txt` in the same PR. One path
per line; directories protect everything underneath them.

## What is NOT protected

Everything not listed in `protected-paths.txt` is considered part of
the upstream theme framework (e.g. `_includes/`, `_layouts/`, `_sass/`,
`_javascript/`, `_plugins/`, `Gemfile`, `jekyll-theme-chirpy.gemspec`,
`rollup.config.js`, `purgecss.js`) and will receive upstream's design
updates and security fixes during a sync. Review the sync PR's diff
before merging in case a customization you made in one of these files
needs to be re-applied on top of the upstream change.
