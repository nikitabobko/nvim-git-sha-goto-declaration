# nvim-git-sha-goto-declaration

A tiny Neovim plugin that makes `gd` (goto declaration) jump to the commit under
the cursor when that "word" is a git SHA.

It is built for interactive rebase / cherry-pick / revert workflows, where the
buffer is full of short SHAs and you want to peek at what a commit actually
does before reordering, squashing, or dropping it.

## Install

Use whatever is your package manager
(the de-facto standard one has probably changed a couple of times since I wrote this README anyway...)

## Behavior

Pressing `gd` in a supported buffer:

1. Runs `git show --stat -p` and shows the output in a right-hand vertical split.
2. `q` closes the split. `gd` works again inside it, so you can chase parent commits from the diff.

## Supported filetypes

| Filetype    | Triggered for                                                   |
|-------------|-----------------------------------------------------------------|
| `gitrebase` | `.git/rebase-merge/git-rebase-todo`, `.git/rebase-apply/...`    |
| `gitrebase` | `.git/sequencer/todo` (cherry-pick / revert) — set by this plugin |
| `gitcommit` | `COMMIT_EDITMSG`, `MERGE_MSG`, etc.                             |
| `git`       | The `git show` split this plugin opens (chain `gd` on parents)  |

Neovim does not detect `.git/sequencer/todo` as `gitrebase` by default, so the
plugin registers an autocmd that does that.

## Layout

```
lua/git_sha_goto_declaration.lua   -- main module: goto_declaration, attach
ftplugin/gitrebase.lua             -- wires gd in rebase-todo / sequencer todo
ftplugin/gitcommit.lua             -- wires gd in commit messages
ftplugin/git.lua                   -- wires gd in the git show split
plugin/git-sha-goto-declaration.lua-- filetype detection for .git/sequencer/todo
```

## Customizing

The plugin is small enough to fork rather than configure, but the public API is:

```lua
local g = require("git_sha_goto_declaration")
g.goto_declaration()  -- run the lookup from the current cursor position
g.attach()            -- bind `gd` in the current buffer
```

To use a horizontal split instead of a vertical one, change `botright vnew` to
`botright new` in `lua/git_sha_goto_declaration.lua`.

To enable it in extra filetypes (e.g. `fugitive`, `diff`), drop a one-liner
`ftplugin/<filetype>.lua` that calls `require("git_sha_goto_declaration").attach()`.

## Code quality

100% vibe coded
