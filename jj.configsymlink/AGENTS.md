# jj — Context for AI Agent

Symlinked to `~/.config/jj/`. User email kept in `private-dotfiles/jj/user.toml`, symlinked into `conf.d/user.toml`.

## Revset aliases (`config.toml`)

- `workspace_view()` — view used in workspace dispatchers (`fzf/functions.sh`).
- `unique(x, markers)` / `unique_boundary(x, markers)` — used by `_jb`/`_jt` previews and by `commit-msg` for merge-commit context.

## Template aliases

- `commit_timestamp(commit)` — **overridden to `commit.author().timestamp()`** (builtin default is the committer timestamp). The builtin log templates and `fzf_oneline` both call this alias, so `jj log`, `_jh`/`_gh`, etc. all show the author timestamp — fixed at the moment the revision first became non-empty and stable across later `squash`/`describe`/rebase, i.e. a creation time rather than a last-rewrite time. The git-fallback log functions (`_git_h`/`_git_hh`/`_git_yy` in `fzf/functions.sh`) use `%ad` to match.
- `short_ago(ts)` — compact relative time (m/h/d/w/M/y). Internal label is `"timestamp ago"` (renamed from `"committer timestamp ago"` after the override above).
- `fzf_oneline` — shortest change ID, no author/git-id, short relative time, bookmarks after description.
- `fzf_oneline_author` — same + author first name via `.split(" ").first()`, falls back to email local part.

## Known issues

- **`empty()` revset vs `empty` template keyword**: the revset predicate excludes commits that contain conflicts, even when the template keyword reports them as empty. So `files(X) & empty()` (revset) will NOT match conflict-only auto-merges; use `-T 'if(empty, …)'` (template) when you need merge-with-no-user-work semantics (e.g. filtering out boilerplate merges in `bin/jj-untrack-files`, `bin/commit-msg`).
- **`diff_lines(regex:".", X)` vs `files(X)`**: `diff_lines` matches only commits with visible diff text in X — submodule pointer changes, mode-only changes, and binary-only changes are NOT matched (gitlinks have no textual content). Use `files(X)` for tree-level change detection; use `diff_lines` when you want to ignore conflict-only tree diffs on merges.
