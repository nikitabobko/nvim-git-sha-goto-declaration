local M = {}

local function is_hex(c)
  return c:match("[0-9a-fA-F]") ~= nil
end

local function looks_like_sha(word)
  return word ~= nil
    and #word >= 4
    and #word <= 40
    and word:match("^[0-9a-fA-F]+$") ~= nil
end

local function sha_under_cursor()
  local line = vim.api.nvim_get_current_line()
  if line == "" then return nil end

  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  if col > #line then col = #line end

  if not is_hex(line:sub(col, col)) then
    if col > 1 and is_hex(line:sub(col - 1, col - 1)) then
      col = col - 1
    else
      return nil
    end
  end

  local s = col
  while s > 1 and is_hex(line:sub(s - 1, s - 1)) do
    s = s - 1
  end

  local e = col
  while e < #line and is_hex(line:sub(e + 1, e + 1)) do
    e = e + 1
  end

  local word = line:sub(s, e)
  if looks_like_sha(word) then return word end
  return nil
end

local function buffer_cwd()
  local cached = vim.b.git_sha_cwd
  if cached and cached ~= "" then return cached end

  local bufname = vim.api.nvim_buf_get_name(0)
  if bufname == "" then return vim.fn.getcwd() end

  local dir = vim.fn.fnamemodify(bufname, ":p:h")
  if vim.fn.isdirectory(dir) == 1 then return dir end
  return vim.fn.getcwd()
end

local function git(cwd, args)
  local cmd = { "git", "-C", cwd }
  vim.list_extend(cmd, args)
  local out = vim.fn.systemlist(cmd)
  return out, vim.v.shell_error
end

function M.goto_declaration()
  local sha = sha_under_cursor()
  if not sha then
    vim.notify("git-sha-goto-declaration: no SHA under cursor", vim.log.levels.WARN)
    return
  end

  local cwd = buffer_cwd()
  local format = "commit %H%d%nParent: %P%nAuthor: %an <%ae>%nDate:   %ad%n%n%w(0,4,4)%B"
  local output, show_rc = git(cwd, { "show", "--format=" .. format, "--stat", "-p", "--no-color", sha .. "^{commit}" })
  if show_rc ~= 0 then
    vim.notify("git-sha-goto-declaration: not a valid commit: " .. sha, vim.log.levels.WARN)
    return
  end
  local full_sha = (output[1] or ""):match("^commit (%x+)") or sha

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local b = vim.api.nvim_win_get_buf(win)
    local ok, marked = pcall(vim.api.nvim_buf_get_var, b, "git_sha_show_buffer")
    if ok and marked then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end

  vim.cmd("botright new")
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, output)
  vim.bo[buf].modifiable = false
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "git"
  vim.b[buf].git_sha_cwd = cwd
  vim.b[buf].git_sha_show_buffer = true
  pcall(vim.api.nvim_buf_set_name, buf, "git show " .. full_sha:sub(1, 12))
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true, desc = "Close git show" })
end

function M.attach()
  vim.keymap.set("n", "gd", M.goto_declaration, {
    buffer = true,
    silent = true,
    desc = "Goto declaration (git SHA)",
  })
end

return M
