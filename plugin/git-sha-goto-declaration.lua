if vim.g.loaded_git_sha_goto_declaration == 1 then return end
vim.g.loaded_git_sha_goto_declaration = 1

local group = vim.api.nvim_create_augroup("GitShaGotoDeclaration", { clear = true })

vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  group = group,
  pattern = {
    "*/.git/sequencer/todo",
    "*/.git/sequencer/todo.backup",
  },
  callback = function() vim.bo.filetype = "gitrebase" end,
})
