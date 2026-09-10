# nvim-git-sha-goto-declaration

A tiny Neovim plugin that makes `gd` (goto declaration) jump to the commit under
the cursor when that "word" is a git SHA.

It works in **any** buffer: rebase todos, commit messages, code comments,
logs, `git show` output, whatever. On a word that isn't a commit SHA the key
keeps its usual meaning, so nothing is taken away from you.

## Install

Use whatever is your package manager
(the de-facto standard one has probably changed a couple of times since I wrote this README anyway...)

## Behavior

`gd` (and `<CR>`) in normal mode:

1. If the word under the cursor is a git SHA (7-40 hex chars) that resolves to a
   commit, run `git show --stat -p` and show the output in the current window,
   like any other goto-definition. `gd` works inside the diff too, so you can
   chase `Parent:` or any SHA mentioned in a commit message.
2. Otherwise the built-in `gd` / `<CR>` runs instead, unchanged.

## With vim-fugitive

If [vim-fugitive](https://github.com/tpope/vim-fugitive) is installed, step 1
hands off to it: `:Git ++curwin show --stat -p <sha>`. You get a real fugitive
buffer, with fugitive's own maps — notably `<CR>`, which jumps to the file under
the cursor in the diff — and the repository attached, so `gd` keeps chasing SHAs
from there. `++curwin` is fugitive's documented opt-out of the `:split` it does
by default for pager commands like `show`, so the commit still replaces the
current window rather than opening a new one.

Two differences from the built-in buffer, both deliberate:

- `<CR>` is fugitive's, not ours. It's more useful on a diff line than a second
  copy of `gd`.
- `q` is not mapped. Fugitive rebuilds its temp buffers as you navigate back
  into them, which drops anything the plugin adds; `<C-o>` is the trail that
  survives.

Nothing needs configuring — fugitive is detected at keypress time, so
lazy-loading it is fine, and if `:Git` fails for any reason the plugin falls
back to rendering the commit itself.

`<C-o>` (or `q`, without fugitive) and `<C-i>` walk that whole trail — commit, parent, grandparent
and back out to the file you started from — because every `gd` renders into a new
scratch buffer and those are kept around (a wiped buffer would take its jumplist
entries with it). They're unlisted, so they stay out of `:ls` and `:bnext`. Look
at the same commit twice and you get two buffers; the second shows as `[No Name]`
since the first already took the name. Deduplicating them isn't worth the code.
With fugitive, its temp buffers do this job instead.

The repository is picked from `b:git_dir` when something set it (fugitive does,
for its buffers and for ordinary files in a repo), otherwise from the directory
of the current buffer's file — so this works across repos in one Neovim session.

## Mappings

`gd` and `<CR>` are mapped globally, at plugin load. Two escape hatches:

- If you already have a **global** `gd` (or `<CR>`) mapping, the plugin leaves it
  alone and doesn't map that key at all.
- A **buffer-local** mapping from another plugin (quickfix, netrw, fugitive,
  `vim.lsp` in your `LspAttach`) always wins over the plugin's global one, per
  Vim's normal precedence. To take a buffer back, call `attach()` in that buffer
  — the plugin's handler then runs first and still falls through to the built-in
  key when there's no SHA under the cursor.

The plugin also teaches Neovim that `.git/sequencer/todo` (cherry-pick / revert)
is `gitrebase`, which it doesn't detect out of the box.

## Layout

```
lua/git_sha_goto_declaration.lua    -- goto_declaration, handler, setup, attach
plugin/git-sha-goto-declaration.lua -- global mappings + sequencer/todo filetype
test.sh                             -- headless tests
nvim.sh                             -- nvim with factory defaults + this plugin
```

`./nvim.sh` runs `nvim --clean` with only this plugin on the runtimepath, which
is the quickest way to tell a plugin bug from a config clash:

```sh
./nvim.sh some-file
GIT_SEQUENCE_EDITOR=/path/to/nvim.sh git rebase -i HEAD~5
```

## Customizing

The plugin is small enough to fork rather than configure, but the public API is:

```lua
local g = require("git_sha_goto_declaration")
g.goto_declaration()  -- run the lookup from the current cursor position (warns when there's no SHA)
g.handler("gd")       -- the mapping's rhs: lookup, else fall back to the given keys
g.setup()             -- map gd / <CR> globally (already called by plugin/)
g.attach()            -- map gd / <CR> buffer-locally in the current buffer
```

To open the diff in a split instead of the current window, drop the `++curwin`
from the `:Git` command and add a `vim.cmd("vsplit")` before `nvim_win_set_buf`,
both in `lua/git_sha_goto_declaration.lua`. The minimum SHA length is
`MIN_SHA_LEN` and the `git show` arguments are `SHOW_ARGS`, in the same file.

## Code quality

100% vibe coded. I didn't read the code.
