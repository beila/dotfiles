# fzf — Context for AI Agent

`~/.dotfiles/fzf/`. Sourced into zsh via `fzf.zsh`.

## fzf.zsh

Env vars, sources `fzf --zsh` dynamically. **Overrides the generated `__fzfcmd`** so the built-in widgets (Ctrl-T file picker / Alt-C cd / Ctrl-R history / Ctrl-E custom cd) launch through `fzf-zellij` when inside a zellij session and `FZF_ZELLIJ` is unset (i.e. not a nested `become` invocation), else plain `fzf`. The branch lives in `__fzfcmd` itself (not buried in fzf-zellij) so the call chain `Ctrl-T → fzf-file-widget → __fzfcmd` stays readable.

`FZF_CTRL_T_COMMAND` / `FZF_ALT_C_COMMAND` emit raw paths (one per line) — earlier versions piped each path through `xargs ls --color=always -d` to render `ls -l`-style rows, which clipped names to invisibility inside the narrow floating-pane list column.

**Previews are single-line** (no `\<newline>` continuations and no multi-line `if/elif/fi`): zsh's outer quoting munges line continuations during the `export` of these strings, and `fzf-zellij` forwards the result into a bash subshell that then chokes on `bash: syntax error near unexpected token '('`. Use `;` and `||` separators on one line. Preview branches at runtime: directory → eza `-1 -F --group-directories-first` (with icons when eza is on PATH, else `ls -1 -F`); file → bat 500 lines (else `cat`, else `file`). Names-first so the narrow pane doesn't dedicate half its width to perm/size/date columns.

`FZF_DEFAULT_OPTS` includes `change-preview-window(down,50%|hidden|)` as the default ctrl-/ binding (covers `--reverse` widgets — see fzf-zellij below for the layout-aware override).

After sourcing, binds Ctrl-E to `fzf-cd-widget`.

Test harness: `fzf/test_fzf_widgets.sh` (7 assertions: function defined, returns fzf-zellij when ZELLIJ set, returns plain fzf when ZELLIJ unset or `FZF_ZELLIJ=1`, fzf-zellij executable + filter pipeline works in fallback paths).

## fzf-zellij

Drop-in `fzf-tmux` equivalent for zellij; runs fzf in a floating pane with FIFO stdin streaming and temp-file output.

**Adaptive default size**: ≥200 cols → 80%×85% (wide screens leave visible side context); else → 98%×92% (narrow laptops near-fullscreen since a thin margin would just waste columns). `-w`/`-h`/`-p` flags still override the defaults verbatim.

`FZF_ZELLIJ=1` env var prevents nested floating panes on `become` toggles and strips `--height`/`--min-height`. `zellij run` stdout is suppressed (otherwise prints pane name `terminal_##`); output post-processed to strip `\r` and residual `terminal_*` lines. `FZF_ZELLIJ_OUTPUT` exported for `become` targets via `_fzf_become` wrapper. Falls back to plain fzf outside zellij.

**Env propagation into the floating pane** is an explicit allowlist (`TERM`, `PATH`, `FZF_ZELLIJ`, `FZF_DEFAULT_OPTS`, `FZF_DEFAULT_COMMAND`, `BAT_THEME`). `FZF_DEFAULT_COMMAND` is load-bearing: built-in widgets (`fzf-cd-widget` / `fzf-file-widget`) set it from `FZF_ALT_C_COMMAND` / `FZF_CTRL_T_COMMAND` before invoking `__fzfcmd`; dropping it makes fzf fall back to its `--walker` and list cwd subdirectories.

**`ctrl-/` vertical-position injection**: scans args + `FZF_DEFAULT_OPTS` env var (whitespace-normalised) for `--reverse` / `--layout=reverse` / `--layout=reverse-list`. When none found, appends a later `--bind ctrl-/:change-preview-window(up,50%|hidden|)` so non-reversed widgets put the vertical preview at the top (last `--bind` wins, overriding the `down,50%` default in `FZF_DEFAULT_OPTS`). Detection runs before the plain-fzf early-return so `FZF_ZELLIJ=1` (nested-via-`become`) and non-zellij fallback paths get the same behaviour.

**Vertical-position rule**: prompt and preview anchor opposite ends with the list in between (visual flow: prompt → list → preview). `--reverse` (prompt at top) → vertical preview at bottom (`down,50%`); default layout (prompt at bottom) → vertical preview at top (`up,50%`). `--tac` (input-order reversal) does NOT trigger the override. fzf-tab bypasses `fzf-zellij` entirely so it relies on the FZF_DEFAULT_OPTS default — correct because fzf-tab uses `--reverse` and wants `down,50%` anyway.

Test harness: `fzf/test_fzf_zellij.sh` (run with `bash fzf/test_fzf_zellij.sh` inside a zellij session).

## functions.sh/

- **`functions.sh`** — jj-first / git-fallback functions. Each `_g*` dispatcher delegates to `_j*` (jj) or `_git_*` (git). `_jb`/`_jt` previews use `unique_boundary()` revset (see `jj.configsymlink/AGENTS.md`). `_jb` parses `jj bookmark list` output directly (indented remote-tracking lines like `  @hj …` get re-prefixed with the parent bookmark via awk so the row says `nix@hj …`). Toggles via `become`: `_jh`↔`_jhh` (ctrl-h), `_jb`↔`_jbb` (workspaces, ctrl-b), `_jy`↔`_jyy` (op log, ctrl-y). ctrl-o inserts empty revision after selected (`jj new --no-edit --after`), uses `transform:` colon form for error display. fzf query preserved across toggles via `{q}`→`--query`. **ctrl-s** (in `_jh`/`_jhh`) toggles a `jj log -s`-style file view by `reload`ing with the `fzf_files_suffix` template appended (`_jj_log_reload` builds the command). All log lines carry two **hidden tab fields** (`<display>\t<change-id>\t<path>`; see jj `config.toml`): `_jj_log_fzf` runs with `--delimiter='\t' --with-nth=1` so only the visible column shows/searches, `--accept-nth=2` and `_jj_change_id`/`_jj_extract_id` (`cut -s -f2`) read the id, and the preview reads the path from field 3 (`_jj_extract_path`, `cut -s -f3`) to diff just that file — commit lines (empty path) instead get `jj show --summary` + full `jj diff`. The tab columns are immune to the graph area's variable spaces, fixing both wrong extraction on file lines and the merge/elision-space bug. The `cut -s` (only-delimited) is essential: graph-only connector rows (`│ │`, `~`) carry no tab, and plain `cut -f2` would echo the whole row → the preview would run `jj -r "│ │"` → "Failed to parse revset"; `-s` makes those rows extract empty so the preview's `[ -z "$id" ] && exit 0` guard suppresses them. File names are coloured like native `jj log -s`; no id is shown on file lines. **Preview** (`_jj_log_preview`) branches three ways on the focused line's hidden fields + `$FZF_PROMPT`: files-view-off commit line → `jj show --summary` (with file list) + full diff; files-view-on commit line → header+desc only (`jj log -T builtin_log_detailed`, **no** file list since the names are already in the fzf list); files-view-on file line → header+desc + only that file's `jj diff -- <path>`. **Alignment**: jj's graph indents a commit's first continuation line one space less than the rest, so `_jj_log_reload` pipes file-view output through `_jj_align_files` = `gawk -f functions.sh/jj-align-files.awk` (gensub normalizes the gap after the last `│` to 3 spaces on file lines only); a template can't fix this. The gawk program MUST live in a file, not inline: the reload command crosses several shell hops (fzf transform → `echo` → fzf → `sh -c`), and an inline program's `$1`/`$3` get expanded away by those shells, corrupting it to `NF>=3 && != { = gensub(...) }` → "Command failed". A bare `-f <path>` has no `$` to eat. Toggle state lives in the prompt (`log> ` ↔ `log+files> `, the same prompt-as-state trick as `_file_browse`), which `ctrl-o` reads back so an insert keeps the current view; state does NOT survive the ctrl-h `become` swap (new process), same as the existing query-only handoff. Line-number focus uses `result:pos(N+1)+unbind(result)`. `fzf_down()` deliberately adds **no** `ctrl-/` binding — the layout-aware override lives in `fzf-zellij` so it can also detect `--reverse` injected via `FZF_DEFAULT_OPTS` env (e.g. by built-in `fzf-cd-widget` / `fzf-file-widget`).
- **`test_toggle_query.sh`** — non-interactive test for toggle query/focus preservation, ctrl-o binding, change-ID extraction, and the `ctrl-/` preview-cycle behaviour (incl. `fzf-zellij`'s `--reverse` detection via stubbed-fzf-on-PATH + `FZF_ZELLIJ=1` plain-fzf fallback path); run with `zsh fzf/functions.sh/test_toggle_query.sh`.
- **`key-binding.zsh`** — Ctrl-G sequences (`^G^F`, `^G^B`, etc.) bound in both viins and vicmd modes; `^G` rebound to undefined-key to prevent list-expand from swallowing the prefix; `^F` bound to `_file_browse`. All custom bindings must use `bindkey -M viins` and `bindkey -M vicmd` (vi mode).

## Known issues

- **fzf `--bind` `transform()` parens**: parenthesis form breaks with nested parens — use the colon form `transform:` instead.
- **fzf `become` toggle output mismatch (`_gy`↔`_gyy`)**: leaves emit different ID shapes (hex op ID for op log vs lowercase change ID for change log). A pipe-tail extractor in either leaf would mangle the other's output when `become` swaps fzf — e.g. `_jyy`'s change-id extractor `[a-z]\{1,\}$` reduces an op-log line like `2 minutes ago … <hex>` to `minutes`. **Fixed by moving extraction *inside* fzf** via `--accept-nth`: each leaf passes the field index of its ID (`--accept-nth=2` for change log, `--accept-nth=-1` for op log). fzf then prints just that field on accept, stripping ANSI for free. With no pipe-tail extractor at all, the become-swapped leaf's output flows through unchanged, and the dispatcher needs no postprocessing. Earlier attempts (dispatcher-level shape-tolerant extractor; side-channel via `FZF_BECOME_OUT` temp file + `_emit`) were either fooled by mock-stub tests or broken across `fzf-zellij`'s zellij-run process boundary, which doesn't forward arbitrary env vars.

## Cross-references

- fzf-tab tab-completion is configured in `zsh/completion.zsh` — see `zsh/AGENTS.md`. fzf-tab runs inline in zsh (NOT through fzf-zellij) for compsys-variable reasons.
- nvim's fzf-lua is configured in `nvim.configsymlink/vimrcs/fzf.lua` — see `nvim.configsymlink/AGENTS.md`.
