# jj — Context for AI Agent

Symlinked to `~/.config/jj/`. User email kept in `private-dotfiles/jj/user.toml`, symlinked into `conf.d/user.toml`.

## Revset aliases (`config.toml`)

- `workspace_view()` — view used in workspace dispatchers (`fzf/functions.sh`).
- `unique(x, markers)` / `unique_boundary(x, markers)` — used by `_jb`/`_jt` previews and by `commit-msg` for merge-commit context.

## Template aliases

- `short_ago(ts)` — compact relative time (m/h/d/w/M/y).
- `fzf_oneline` — shortest change ID, no author/git-id, short relative time, bookmarks after description.
- `fzf_oneline_author` — same + author first name via `.split(" ").first()`, falls back to email local part.

## Known issues

- **`empty()` revset vs `empty` template keyword**: the revset predicate excludes commits that contain conflicts, even when the template keyword reports them as empty. So `files(X) & empty()` (revset) will NOT match conflict-only auto-merges; use `-T 'if(empty, …)'` (template) when you need merge-with-no-user-work semantics (e.g. filtering out boilerplate merges in `bin/jj-untrack-files`, `bin/commit-msg`).
- **`diff_lines(regex:".", X)` vs `files(X)`**: `diff_lines` matches only commits with visible diff text in X — submodule pointer changes, mode-only changes, and binary-only changes are NOT matched (gitlinks have no textual content). Use `files(X)` for tree-level change detection; use `diff_lines` when you want to ignore conflict-only tree diffs on merges.
