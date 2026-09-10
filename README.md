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
   like any other goto-definition. `<C-o>` (or `q`) goes back.
   `gd` / `<CR>` work inside the diff too, so you can chase parent commits.
2. Otherwise the built-in `gd` / `<CR>` runs instead, unchanged.

The diff lives in a throwaway scratch buffer that is wiped as soon as you leave
it, so it never piles up in your buffer list (which also means `<C-i>` won't
bring it back — press `gd` again).

The repository is picked from the directory of the current buffer's file, so
this works across repos in one Neovim session.

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

To open the diff in a split instead of the current window, add a `vim.cmd("vsplit")`
before `nvim_win_set_buf` in `lua/git_sha_goto_declaration.lua`. The minimum SHA
length is `MIN_SHA_LEN` in the same file.

## Code quality

100% vibe coded. I didn't read the code.
