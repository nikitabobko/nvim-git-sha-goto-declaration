if vim.g.loaded_git_sha_goto_declaration == 1 then return end
vim.g.loaded_git_sha_goto_declaration = 1

local group = vim.api.nvim_create_augroup("GitShaGotoDeclaration", { clear = true })

-- Neovim doesn't recognize the cherry-pick / revert todo out of the box.
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  group = group,
  pattern = {
    "*/.git/sequencer/todo",
    "*/.git/sequencer/todo.backup",
  },
  callback = function() vim.bo.filetype = "gitrebase" end,
})

require("git_sha_goto_declaration").setup()
