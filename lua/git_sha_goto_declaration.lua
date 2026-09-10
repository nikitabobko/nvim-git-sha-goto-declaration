local M = {}

-- Git's default abbreviation is 7 hex chars. Anything shorter matches far too
-- many ordinary words (`add`, `face`, `dead`, ...), which matters now that the
-- mappings are live in every buffer rather than only in rebase todos.
local MIN_SHA_LEN = 7
local MAX_SHA_LEN = 40

local KEYS = { "gd", "<CR>" }
local DESC = "Goto declaration (git SHA)"
local BACK_DESC = "Back to where gd was pressed"

-- The headers git show doesn't print by default. `Parent:` is the one that
-- earns its keep: it makes the commit above this one just another `gd` away.
local FORMAT = "commit %H%d%nParent: %P%nAuthor: %an <%ae>%nDate:   %ad%n%n%w(0,4,4)%B"
local SHOW_ARGS = { "--format=" .. FORMAT, "--stat", "-p", "--no-color" }

--- The hex run the cursor sits on, if it is SHA-shaped. A cursor one past the
--- end of a run still counts, so `gd` works from the space after a SHA.
local function sha_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = math.min(vim.api.nvim_win_get_cursor(0)[2] + 1, #line)

  local from = 1
  while true do
    local s, e = line:find("%x+", from)
    -- Runs are separated by a non-hex char, so at most one can contain `col`.
    if not s or col <= e + 1 then
      local len = s and col >= s and e - s + 1 or 0
      return len >= MIN_SHA_LEN and len <= MAX_SHA_LEN and line:sub(s, e) or nil
    end
    from = e + 1
  end
end

--- Where to run git: the origin repo for buffers we rendered, fugitive's repo
--- for its buffers, else the directory of the current file, else Neovim's cwd.
--- b:git_dir points at the .git directory rather than the work tree, which is
--- fine -- git discovers the repo from inside it, linked worktrees included.
--- Without this a fugitive buffer would resolve to Neovim's temp directory,
--- and chasing a Parent: SHA out of one would find no repo at all.
local function buffer_cwd()
  local repo = vim.b.git_sha_cwd or vim.b.git_dir
  if repo then return repo end
  local dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":p:h")
  return vim.fn.isdirectory(dir) == 1 and dir or vim.fn.getcwd()
end

--- Show the commit through vim-fugitive, so it lands in a real fugitive buffer
--- with fugitive's own navigation (`<CR>` on a diff line opens that file) and
--- the repo attached, which is what lets `gd` keep chasing SHAs from there.
--- `++curwin` is fugitive's documented opt-out of the :split it does by default
--- for pager commands like show. Returns false when fugitive isn't installed,
--- or when it refused the command and our own buffer should take over.
local function show_with_fugitive(sha)
  if vim.fn.exists(":Git") ~= 2 then return false end

  -- :Git expands its arguments the way :edit does, so the `%` placeholders in
  -- --format= would come back as the current file name, and its spaces would
  -- split one argument into eight. Escaping is what keeps FORMAT intact.
  local args = {}
  for _, arg in ipairs(SHOW_ARGS) do
    args[#args + 1] = (arg:gsub("[%%#\\ ]", "\\%0"))
  end
  -- The buffer is fugitive's from here on: no `q` alias, no mappings of ours.
  -- Fugitive rebuilds its temp buffers as you navigate back into them, which
  -- drops anything we add; `<C-o>` is the trail that survives, and `<CR>` is
  -- better spent on fugitive's own jump-to-file than on ours.
  return pcall(vim.cmd, table.concat({ "Git ++curwin show", table.concat(args, " "), sha }, " "))
end

--- Render the commit ourselves, for when fugitive isn't around.
local function show_in_scratch(cwd, sha)
  local cmd = { "git", "-C", cwd, "show" }
  vim.list_extend(cmd, SHOW_ARGS)
  cmd[#cmd + 1] = sha

  -- Scratch, but not bufhidden=wipe: a wiped buffer would take its jumplist
  -- entries down with it, and those are what <C-o> / <C-i> walk.
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn.systemlist(cmd))
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "git"
  vim.b[buf].git_sha_cwd = cwd
  pcall(vim.api.nvim_buf_set_name, buf, "git show " .. sha:sub(1, 12))
  vim.keymap.set("n", "q", "<C-o>", { buffer = buf, silent = true, desc = BACK_DESC })
  vim.api.nvim_win_set_buf(0, buf)
end

-- Returns nil on success, or a human-readable reason why nothing was shown.
local function try_goto()
  local sha = sha_under_cursor()
  if not sha then return "no SHA under cursor" end

  -- Resolve before showing anything: on a hex word that is not a commit, `gd`
  -- has to fall through to its built-in meaning with the window untouched.
  local cwd = buffer_cwd()
  local full_sha = vim.fn.systemlist({
    "git", "-C", cwd, "rev-parse", "--verify", "--quiet", sha .. "^{commit}",
  })[1]
  if vim.v.shell_error ~= 0 or not full_sha then return "not a valid commit: " .. sha end

  vim.cmd("normal! m'") -- leave a jumplist entry, so <C-o> goes back
  if not show_with_fugitive(sha) then show_in_scratch(cwd, full_sha) end
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
    local prefix = vim.v.count > 0 and tostring(vim.v.count) or ""
    vim.api.nvim_feedkeys(prefix .. vim.api.nvim_replace_termcodes(keys, true, false, true), "n", false)
  end
end

--- Map whichever of `gd` / `<CR>` is not already claimed at this level: a
--- global mapping from the user's config blocks `setup()`, a buffer-local one
--- from another plugin blocks `attach()`. `maparg` reports the mapping that
--- would fire right now, with `.buffer == 1` when it is buffer-local.
--- @param buf integer|nil buffer to map in, or nil for a global mapping
local function map_keys(buf)
  for _, lhs in ipairs(KEYS) do
    local m = vim.fn.maparg(lhs, "n", false, true)
    local claimed = not vim.tbl_isempty(m) and (m.buffer == 1) == (buf ~= nil)
    if not claimed then
      vim.keymap.set("n", lhs, M.handler(lhs), { buffer = buf, silent = true, desc = DESC })
    end
  end
end

--- Bind `gd` and `<CR>` globally, in every buffer. Keys already claimed by the
--- user or another plugin are left alone.
function M.setup()
  map_keys(nil)
end

--- Bind `gd` and `<CR>` buffer-locally in the current buffer. Only needed to
--- override a buffer-local mapping from another plugin; `setup()` already
--- covers ordinary buffers.
function M.attach()
  if vim.b.fugitive_type ~= nil then return end
  local buf = vim.api.nvim_get_current_buf()
  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_call(buf, function() map_keys(buf) end)
    end
  end)
end

return M
