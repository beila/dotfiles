# Handoff: harper + vale prose tooling (nvim + Claude Code hook)

Session date 2026-07-28 (handoff written 2026-08-08). Original request: TODO item
"set up harper and vale for neovim and for ai agents hook after modifying
markdown files" (https://lukicdejan.com/writing-editing-stack/ — NOTE: that
article has zero config content; it's a Zed user's tool list. Everything below
was designed from harper/vale docs + this repo's conventions.)

## Design that was settled (with the user, over several turns)

Three-layer prose checking, each tool doing ONE job, all sharing the nvim spell
allowlist `nvim.configsymlink/spell/en.utf-8.add` (~/.config/nvim/spell/en.utf-8.add):

| layer    | tool                                                                  | scope                     | notes                                                                         |
| -------- | --------------------------------------------------------------------- | ------------------------- | ----------------------------------------------------------------------------- |
| spelling | built-in `:set spell` (nvim) / `spellcheck-md` = codespell (CLI/hook) | md, gitcommit / any prose | typo-LIST-based → no unknown-word false positives                             |
| grammar  | harper (`harper_ls` in nvim, `harper-cli` in hook)                    | prose filetypes only      | `SpellCheck` rule **disabled** (see below), `SentenceCapitalization` disabled |
| style    | vale                                                                  | prose filetypes           | `Vale.Spelling` **disabled** in vale.ini                                      |

Key decisions and WHY (do not relitigate without new info):

- **harper `SpellCheck = false`**: it is dictionary-based (flags every word not
  in its dict). On the user's real doc
  `~/hjdocs/public-docs/native-module-path-mapping-design.md` it produced 297
  SpellCheck hits even WITH the shared user dictionary (816 without, 380 with
  `--user-dict-path`; the remainder were possessives like `musl's`, terms like
  `wasip1`, `CSPRNG`, `libwebsockets`, anchor fragments). The same doc passes
  `spellcheck-md` clean (exit 0). Dictionary sharing WAS verified working
  (adding a word to en.utf-8.add suppresses harper's lint for it) — the false
  positives are inherent to the unknown-word model, not a wiring bug.
- **`Vale.Spelling = NO`**: vale has its own dictionary, doesn't read
  en.utf-8.add at all → would flag EC2/brazil/musl etc.
- **markdownlint-cli2 stays** (structure linting; no overlap with the above).
- **Hook is non-blocking** (`additionalContext`, not `decision:"block"`): the
  write already happened, and findings cover the WHOLE file, so blocking a
  one-line edit to a legacy doc would trap the agent fixing hundreds of
  pre-existing nits. User explicitly probed this ("should we block the current
  edit?") and the non-blocking form is the answer we implemented.
- Hook message must tell the agent **how to allowlist a legitimate word**:
  append it on its own line to en.utf-8.add (shared by all checkers + nvim).
  User explicitly requested this. Already in the `ctx` string.

## State: ALL COMMITTED (auto-sync committed everything ~2026-07-28/29)

Public repo `~/.dotfiles` (branch main):

- `d762381929fc` feat(nvim): add harper-ls grammar checker for prose filetypes
- `4ffd6e61d825` fix(nvim): disable harper SpellCheck linter, covered by :set spell + codespell

Files (verified present on main 2026-08-08):

- `home-manager.configsymlink/nvim.nix` — `harper` package added (# text/md LSP,
  line ~199). **home-manager switch already run, harper-ls + harper-cli are on
  PATH** (harper 2.6.0 from nixpkgs).
- `nvim.configsymlink/vimrcs/harper.lua` — NEW. `vim.lsp.config.harper_ls` with
  `filetypes = { text, markdown, gitcommit, rst, org, asciidoc, tex, mail }`
  (deliberately narrowed from lspconfig's default which lints code comments —
  too noisy next to per-language tooling), `userDictPath = en.utf-8.add`,
  `linters.SentenceCapitalization = false`, `linters.SpellCheck = false`.
  Verified attaching: 1 client on a markdown buffer.
- `nvim.configsymlink/vimrcs/nvim-lint.lua` — vale extended from text-only to
  all prose fts via loop (`text rst asciidoc tex org mail gitcommit`);
  markdown = `{ markdownlint-cli2, vale }`.
- `vale.ini.symlink` (→ ~/.vale.ini) — `Vale.Spelling = NO` + why-comment.

Private repo `~/.dotfiles/private-dotfiles`:

- `e2082ddb` feat(claude-hooks): switch prose-lint to non-blocking additionalContext and layer codespell
- `f1bf1bc9` fix(prose-lint): ignore SentenceCapitalization in harper-cli to match nvim
- `claude.symlink/hooks/prose-lint.sh` — NEW, executable, tracked. Runs
  spellcheck-md + vale + harper-cli (`--ignore SpellCheck,SentenceCapitalization
--user-dict-path en.utf-8.add`) on the edited file when its extension is
  prose (`*.md|*.markdown|*.mdx|*.txt|*.rst|*.adoc|*.asciidoc|*.tex|*.org`),
  emits `{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:…}}`
  or exits 0 silently. Degrades gracefully when a checker is missing from PATH.

## NOT done / open items

1. **Hook is NOT wired into settings.json** — user said "disable claude hook
   for now" then "not yet" when I tried to re-add. The script sits ready at
   `~/.claude/hooks/prose-lint.sh`. To enable, add to
   `private-dotfiles/claude.symlink/settings.json` →
   `hooks.PostToolUse[0].hooks` (the existing `Write|Edit` matcher block,
   AFTER the prettier entry so formatting runs first):

   ```json
   {
     "type": "command",
     "command": "\"$HOME\"/.claude/hooks/prose-lint.sh",
     "statusMessage": "Checking prose (vale + harper)..."
   }
   ```

   settings.json is machine-local/gitignored (Amazon claude binary rewrites
   it), so this is a per-machine edit. **Wait for the user to ask.**

2. **Remaining harper noise, undecided**: on the design doc the hook still
   reports ~230 harper findings, dominated by
   `Capitalization::OrthographicConsistency` (78 — mostly prose written in
   lowercase-convention), `Capitalization::UseTitleCase` (43 — headings),
   `Typo::SplitWords` (39), `Formatting::NumericRangeEnDash` (10). If the user
   finds the hook/nvim output still too noisy, next candidates to add to the
   ignore set (BOTH places: `vimrcs/harper.lua` linters table AND the
   `--ignore` list in prose-lint.sh — keep them mirrored) are
   `OrthographicConsistency`, `UseTitleCase`, `SplitWords`. Not done because
   the user hasn't judged the current output yet.
3. **kiro/codex hooks not set up** — user asked "are kiro and codex set up
   too?"; answer was no. codex config.toml `[hooks.state]` entries are just AIM
   plugin trust hashes. If asked: codex supports hooks via its plugin hook
   mechanism, kiro via its own hooks; prose-lint.sh's core is
   CLI-agnostic (stdin JSON → path; only the JSON shape is Claude-specific).
4. **Docs not updated** (instructions rule 6, still owed):
   - `CLAUDE.md` TODO: flip the harper/vale item to `[x]` with a summary line
     (nvim side done; agent hook built but unwired-by-choice).
   - `nvim.configsymlink/AGENTS.md`: "Linting" and "Spell check" bullets don't
     mention harper or the vale-everywhere change; my-text.lua comment header
     ("vale linting configured in nvim-lint.lua") still accurate, but consider
     a note in the Per-language section for harper.lua.
   - `private-dotfiles/CLAUDE.md`/`AGENTS.md` contents list: mention
     `claude.symlink/hooks/prose-lint.sh`.
   - `bin/AGENTS.md` unaffected (nothing added to bin — user rejected bin/ as
     location: "bin is where I put scripts. put it somewhere else").
5. `docs/` also contains `agent-tts-guide.md`; this handoff file itself is new
   and should be deleted (or updated) once the open items land.

## Verification commands (all previously passing)

```sh
command -v harper-ls harper-cli          # both in ~/.nix-profile/bin
vale --output=line /tmp/somefile.md      # Vale.Spelling absent from output
printf '{"tool_input":{"file_path":"/tmp/x.md"}}' | "$HOME/.claude/hooks/prose-lint.sh"
# test corpus that exercises all three checkers:
printf '# Test\n\n이것은 한국어 문장입니다. This is a Englsih sentence with teh mistake. We could of done it.\n' > /tmp/x.md
# expect: spellcheck-md "teh ==> the"; harper AnA + ModalOf + Typo::The; no SpellCheck; no Vale.Spelling
# nvim LSP attach check:
nvim --headless "+edit /tmp/x.md" "+lua vim.defer_fn(function() print('harper_ls clients: '..#vim.lsp.get_clients({name='harper_ls'})); vim.cmd('qa') end, 2000)"
```

Korean text: harper/vale simply don't flag Hangul (verified) — no isolateEnglish
needed so far.

## Session gotchas (will bite a fresh session)

- **bash-gate.py** (PreToolUse hook) blocks: `$(…)` substitution, leading
  `cd X && …`, mixing review-needed + safe commands on one line, `grep`
  (use `rg`), sed beyond plain print/delete, running interpreter scripts from
  /tmp. Piping stdin JSON into `$HOME/.claude/hooks/*.sh` is trusted
  (gate_self_script) — that's how you test prose-lint.sh.
- **Paths in tool calls must be literal absolute paths** — `$USER_HOME`-style
  placeholders are NOT expanded by Read/Write; a Write to such a path silently
  creates a literal `$USER_HOME/` directory under the cwd (it happened writing
  this very file). Home is `$USER_HOME`.
- settings.json edits: file is regenerated by the Amazon claude launcher but
  custom hook entries survive; it's gitignored so no commit worry.
- home-manager switch: `home-manager switch --impure --flake
~/.dotfiles/home-manager.configsymlink` (already done for harper; only needed
  again if nvim.nix changes).
- The user communicates mid-turn; scope changed several times (hook location
  bin/ → claude.symlink/hooks/, blocking → non-blocking, enable → disable).
  Re-read the "NOT done" list before doing anything proactive.
