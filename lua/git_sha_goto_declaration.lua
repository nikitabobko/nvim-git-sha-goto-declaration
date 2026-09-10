local M = {}

-- Git's default abbreviation is 7 hex chars. Anything shorter matches far too
-- many ordinary words (`add`, `face`, `dead`, ...), which matters now that the
-- mappings are live in every buffer rather than only in rebase todos.
local MIN_SHA_LEN = 7
local MAX_SHA_LEN = 40

local function is_hex(c)
  return c:match("%x") ~= nil
end

local function looks_like_sha(word)
  return word ~= nil
    and #word >= MIN_SHA_LEN
    and #word <= MAX_SHA_LEN
    and word:match("^%x+$") ~= nil
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

-- Returns nil on success, or a human-readable reason why nothing was shown.
local function try_goto()
  local sha = sha_under_cursor()
  if not sha then return "no SHA under cursor" end

  local cwd = buffer_cwd()
  local format = "commit %H%d%nParent: %P%nAuthor: %an <%ae>%nDate:   %ad%n%n%w(0,4,4)%B"
  local output, show_rc = git(cwd, { "show", "--format=" .. format, "--stat", "-p", "--no-color", sha .. "^{commit}" })
  if show_rc ~= 0 then return "not a valid commit: " .. sha end
  local full_sha = (output[1] or ""):match("^commit (%x+)") or sha

  -- Scratch, but not bufhidden=wipe: a wiped buffer would take its jumplist
  -- entries down with it, and those are what <C-o> / <C-i> walk.
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, output)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "git"
  vim.b[buf].git_sha_cwd = cwd
  pcall(vim.api.nvim_buf_set_name, buf, "git show " .. full_sha:sub(1, 12))
  vim.keymap.set("n", "q", "<C-o>", { buffer = buf, silent = true, desc = "Back to where gd was pressed" })

  vim.cmd("normal! m'") -- leave a jumplist entry, so <C-o> goes back
  vim.api.nvim_win_set_buf(0, buf)
  return nil
end

--- Show the commit under the cursor. Warns when there is none.
--- @return boolean whether a commit was shown
function M.goto_declaration()
  local err = try_goto()
  if err then
    vim.notify("git-sha-goto-declaration: " .. err, vim.log.levels.WARN)
    return false
  end
  return true
end

--- Build the function bound to `keys`: show the commit under the cursor, or,
--- when there is none, replay `keys` with its built-in meaning. Falling through
--- is what makes it safe to own `gd` / `<CR>` in every buffer.
--- @param keys string
function M.handler(keys)
  return function()
    if try_goto() == nil then return end
    local count = vim.v.count
    local prefix = count > 0 and tostring(count) or ""
    local rhs = prefix .. vim.api.nvim_replace_termcodes(keys, true, false, true)
    vim.api.nvim_feedkeys(rhs, "n", false)
  end
end

--- The mapping that would fire for `lhs` right now, or nil. `.buffer` is 1 when
--- it is buffer-local.
local function existing_map(lhs)
  local m = vim.fn.maparg(lhs, "n", false, true)
  if type(m) ~= "table" or vim.tbl_isempty(m) then return nil end
  return m
end

local KEYS = { "gd", "<CR>" }

--- Bind `gd` and `<CR>` globally, in every buffer. Keys already claimed by the
--- user or another plugin are left alone.
function M.setup()
  for _, lhs in ipairs(KEYS) do
    local m = existing_map(lhs)
    if not m or m.buffer == 1 then
      vim.keymap.set("n", lhs, M.handler(lhs), { silent = true, desc = "Goto declaration (git SHA)" })
    end
  end
end

--- Bind `gd` and `<CR>` buffer-locally in the current buffer. Only needed to
--- override a buffer-local mapping from another plugin; `setup()` already
--- covers ordinary buffers.
function M.attach()
  if vim.b.fugitive_type ~= nil then return end
  local buf = vim.api.nvim_get_current_buf()
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    vim.api.nvim_buf_call(buf, function()
      for _, lhs in ipairs(KEYS) do
        local m = existing_map(lhs)
        if not m or m.buffer ~= 1 then
          vim.keymap.set("n", lhs, M.handler(lhs), { buffer = buf, silent = true, desc = "Goto declaration (git SHA)" })
        end
      end
    end)
  end)
end

return M
