# jj — Context for AI Agent

Symlinked to `~/.config/jj/`. User email kept in `private-dotfiles/jj/user.toml`, symlinked into `conf.d/user.toml`.

## Revset aliases (`config.toml`)

- `workspace_view()` — view used in workspace dispatchers (`fzf/functions.sh`).
- `unique(x, markers)` / `unique_boundary(x, markers)` — used by `_jb`/`_jt` previews and by `commit-msg` for merge-commit context.

## Template aliases

- `commit_timestamp(commit)` — **overridden to `commit.author().timestamp()`** (builtin default is the committer timestamp). The builtin log templates and `fzf_oneline` both call this alias, so `jj log`, `_jh`/`_gh`, etc. all show the author timestamp — fixed at the moment the revision first became non-empty and stable across later `squash`/`describe`/rebase, i.e. a creation time rather than a last-rewrite time. The git-fallback log functions (`_git_h`/`_git_hh`/`_git_yy` in `fzf/functions.sh`) use `%ad` to match.
- `short_ago(ts)` — compact relative time (m/h/d/w/M/y). Internal label is `"timestamp ago"` (renamed from `"committer timestamp ago"` after the override above).
- `fzf_change_id(commit)` — shortest change id plus a `/N` change-offset suffix when the change is **divergent** (e.g. `lurk/0`), matching `jj log`'s notation; non-divergent changes get no suffix. Used by `fzf_oneline`/`fzf_files_suffix` for BOTH the visible column and the hidden extraction field, so a divergent row is disambiguated on screen and the previewed/selected revset (`jj -r lurk/0`) resolves to the single commit under the cursor instead of erroring on the ambiguous bare change id.
- `fzf_oneline` — shortest change ID (`fzf_change_id`, with `/N` offset when divergent), no author/git-id, short relative time, bookmarks after description. Ends each line with two **hidden tab fields**: `<display>\t<change-id>\t<path>` (path empty on commit lines). `_jj_log_fzf` shows/searches only field 1 (`--with-nth=1`), extracts the id from field 2 (`--accept-nth=2`), previews field 3 as a path. Tab columns are fixed regardless of the graph area's variable leading spaces (merges, elisions), so positional extraction is robust where whitespace splitting wasn't.
- `fzf_oneline_author` — same + author first name via `.split(" ").first()`, falls back to email local part; same two hidden tab fields.
- `fzf_files_suffix` — one modified file per line, appended to a oneline template by `_jh`/`_jhh`'s ctrl-s toggle for a `jj log -s` view. Visible field 1 is coloured exactly like native `jj log -s` (whole `M path` wrapped in `label("diff " ++ f.status(), …)` → modified=cyan/added=green/removed=red), with **no change id shown** on file lines. The id and path ride in the same two hidden tab fields as the commit line, so Enter on a file line yields its commit's id and the preview diffs just that path. Alignment of the first vs later file lines is fixed downstream by `_jj_align_files` (`gawk -f fzf/functions.sh/jj-align-files.awk`), not in the template — jj indents the first graph continuation line one space less, which a template can't compensate for.

## Known issues

- **`empty()` revset vs `empty` template keyword**: the revset predicate excludes commits that contain conflicts, even when the template keyword reports them as empty. So `files(X) & empty()` (revset) will NOT match conflict-only auto-merges; use `-T 'if(empty, …)'` (template) when you need merge-with-no-user-work semantics (e.g. filtering out boilerplate merges in `bin/jj-untrack-files`, `bin/commit-msg`).
- **`diff_lines(regex:".", X)` vs `files(X)`**: `diff_lines` matches only commits with visible diff text in X — submodule pointer changes, mode-only changes, and binary-only changes are NOT matched (gitlinks have no textual content). Use `files(X)` for tree-level change detection; use `diff_lines` when you want to ignore conflict-only tree diffs on merges.
