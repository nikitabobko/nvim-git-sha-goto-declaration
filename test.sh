#!/usr/bin/env bash
# Headless tests for git-sha-goto-declaration.
# Each test spins up nvim --headless against a throwaway git repo and asserts
# on the plugin's printed output.

set -e          # Exit if one of commands exit with non-zero exit code
set -u          # Treat unset variables and parameters other than the special parameters '@' or '*' as an error
set -o pipefail # Any command failed in the pipe fails the whole pipe

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
failed=()

# run_nvim <cwd> <script> [pre-script]
# The optional pre-script runs *before* plugin/*.lua, so a test can pretend the
# user already claimed a mapping in their config.
run_nvim() {
  local cwd="$1" script="$2" pre="${3:-}"
  local pre_args=()
  [[ -n "$pre" ]] && pre_args=(-c "luafile $pre")
  (
    cd "$cwd"
    nvim --headless --clean -u NONE \
      --cmd "set rtp+=$here" \
      "${pre_args[@]}" \
      -c "runtime! plugin/*.lua" \
      -c "luafile $script" \
      -c "qa!" 2>&1
  )
}

# Where vim-fugitive lives, if it is installed at all -- nvim_fugitive.sh owns
# that search, so the two can't drift. The fugitive tests skip rather than fail
# when it isn't installed; the plugin works without it.
fugitive="$("$here/nvim_fugitive.sh" --print-path)"

# run_fugitive <cwd> <script> -- like run_nvim, with fugitive on the runtimepath.
run_fugitive() {
  local cwd="$1" script="$2"
  (
    cd "$cwd"
    nvim --headless --clean -u NONE \
      --cmd "set rtp+=$fugitive" \
      --cmd "set rtp+=$here" \
      -c "runtime! plugin/*.vim" \
      -c "runtime! plugin/*.lua" \
      -c "luafile $script" \
      -c "qa!" 2>&1
  )
}

assert_match() {
  local name="$1" output="$2" pattern="$3"
  if printf '%s\n' "$output" | grep -qE "$pattern"; then
    printf '  ok   %s\n' "$name"
    pass=$((pass + 1))
  else
    printf '  FAIL %s\n' "$name"
    printf '       pattern: %s\n' "$pattern"
    printf '       output:\n'
    printf '%s\n' "$output" | sed 's/^/         /'
    fail=$((fail + 1))
    failed+=("$name")
  fi
}

assert_no_match() {
  local name="$1" output="$2" pattern="$3"
  if printf '%s\n' "$output" | grep -qE "$pattern"; then
    printf '  FAIL %s\n' "$name"
    printf '       unexpected match: %s\n' "$pattern"
    printf '       output:\n'
    printf '%s\n' "$output" | sed 's/^/         /'
    fail=$((fail + 1))
    failed+=("$name")
  else
    printf '  ok   %s\n' "$name"
    pass=$((pass + 1))
  fi
}

new_repo() {
  local dir="$1"
  rm -rf "$dir"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email t@t
  git -C "$dir" config user.name t
  for msg in first second third; do
    git -C "$dir" commit -q --allow-empty -m "$msg"
  done
}

# --------------------------------------------------------------------------- #
echo "== happy path: gd on a SHA shows the commit in the same window"
# --------------------------------------------------------------------------- #
repo="$tmp/happy"
new_repo "$repo"
sha2=$(git -C "$repo" rev-parse --short HEAD~1)
sha3=$(git -C "$repo" rev-parse --short HEAD)
printf 'pick %s second\npick %s third\n' "$sha2" "$sha3" > "$repo/rebase-todo"

cat > "$tmp/t.lua" <<'EOF'
vim.cmd("edit rebase-todo")
vim.cmd("set ft=gitrebase")
local todo_win = vim.api.nvim_get_current_win()
local todo_buf = vim.api.nvim_get_current_buf()
vim.api.nvim_win_set_cursor(0, {1, 5})
require('git_sha_goto_declaration').goto_declaration()
print("LINES_BEGIN")
for _, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, 5, false)) do print(l) end
print("LINES_END")
print("WINCOUNT " .. #vim.api.nvim_list_wins())
print("SAME_WIN " .. tostring(todo_win == vim.api.nvim_get_current_win()))
print("BUF_REPLACED " .. tostring(todo_buf ~= vim.api.nvim_get_current_buf()))
print("MODIFIABLE " .. tostring(vim.bo.modifiable))
print("BUFTYPE " .. vim.bo.buftype)
print("FILETYPE " .. vim.bo.filetype)
print("BUFNAME " .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t"))
print("ROW " .. vim.api.nvim_win_get_cursor(0)[1])
EOF
out=$(run_nvim "$repo" "$tmp/t.lua")
assert_match "happy: commit header"      "$out" '^commit [0-9a-f]{40}'
assert_match "happy: parent header"      "$out" '^Parent: [0-9a-f]{40}'
assert_match "happy: author header"      "$out" '^Author: '
assert_match "happy: no new window"      "$out" '^WINCOUNT 1$'
assert_match "happy: reuses the window"  "$out" '^SAME_WIN true$'
assert_match "happy: buffer replaced"    "$out" '^BUF_REPLACED true$'
assert_match "happy: buffer not modifiable" "$out" '^MODIFIABLE false$'
assert_match "happy: scratch buffer"     "$out" '^BUFTYPE nofile$'
assert_match "happy: filetype is git"    "$out" '^FILETYPE git$'
assert_match "happy: buffer named"       "$out" '^BUFNAME git show [0-9a-f]{12}$'
assert_match "happy: cursor at the top"  "$out" '^ROW 1$'

# --------------------------------------------------------------------------- #
echo "== <C-o> goes back to where gd was pressed"
# --------------------------------------------------------------------------- #
cat > "$tmp/t.lua" <<'EOF'
vim.cmd("edit rebase-todo")
vim.cmd("set ft=gitrebase")
vim.api.nvim_win_set_cursor(0, {2, 5})
require('git_sha_goto_declaration').goto_declaration()
local shown = vim.bo.filetype
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-o>", true, false, true), "x", false)
print("SHOWN_FT " .. shown)
print("BACK_NAME " .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t"))
print("BACK_ROW " .. vim.api.nvim_win_get_cursor(0)[1])
EOF
out=$(run_nvim "$repo" "$tmp/t.lua")
assert_match "back: showed the commit"   "$out" '^SHOWN_FT git$'
assert_match "back: returns to the todo" "$out" '^BACK_NAME rebase-todo$'
assert_match "back: returns to the line" "$out" '^BACK_ROW 2$'

# --------------------------------------------------------------------------- #
echo "== <CR> on a SHA opens split (same behavior as gd)"
# --------------------------------------------------------------------------- #
cat > "$tmp/t.lua" <<'EOF'
vim.cmd("edit rebase-todo")
vim.cmd("set ft=gitrebase")
vim.api.nvim_win_set_cursor(0, {1, 5})
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
print("LINES_BEGIN")
for _, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, 5, false)) do print(l) end
print("LINES_END")
print("WINCOUNT " .. #vim.api.nvim_list_wins())
print("BUFNAME " .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t"))
EOF
out=$(run_nvim "$repo" "$tmp/t.lua")
assert_match "cr: commit header"     "$out" '^commit [0-9a-f]{40}'
assert_match "cr: no new window"     "$out" '^WINCOUNT 1$'
assert_match "cr: buffer named"      "$out" '^BUFNAME git show [0-9a-f]{12}$'

# --------------------------------------------------------------------------- #
echo "== no SHA under cursor: warns, no split opens"
# --------------------------------------------------------------------------- #
cat > "$tmp/t.lua" <<'EOF'
vim.cmd("edit rebase-todo")
vim.cmd("set ft=gitrebase")
local notes = {}
vim.notify = function(msg, _) table.insert(notes, msg) end
vim.api.nvim_win_set_cursor(0, {1, 0})  -- on 'p' of 'pick'
require('git_sha_goto_declaration').goto_declaration()
print("NOTIFY " .. (notes[1] or ""))
print("FILETYPE " .. vim.bo.filetype)
EOF
out=$(run_nvim "$repo" "$tmp/t.lua")
assert_match    "no-sha: warns"          "$out" '^NOTIFY .*no SHA under cursor'
assert_match    "no-sha: buffer untouched" "$out" '^FILETYPE gitrebase$'

# --------------------------------------------------------------------------- #
echo "== invalid SHA: warns, no split opens"
# --------------------------------------------------------------------------- #
cat > "$tmp/t.lua" <<'EOF'
vim.cmd("edit rebase-todo")
vim.cmd("set ft=gitrebase")
vim.api.nvim_set_current_line("pick deadbeef nope")
local notes = {}
vim.notify = function(msg, _) table.insert(notes, msg) end
vim.api.nvim_win_set_cursor(0, {1, 5})
require('git_sha_goto_declaration').goto_declaration()
print("NOTIFY " .. (notes[1] or ""))
print("FILETYPE " .. vim.bo.filetype)
EOF
out=$(run_nvim "$repo" "$tmp/t.lua")
assert_match    "invalid: warns"         "$out" '^NOTIFY .*not a valid commit: deadbeef'
assert_match    "invalid: buffer untouched" "$out" '^FILETYPE gitrebase$'

# --------------------------------------------------------------------------- #
echo "== tree (non-commit) SHA: warns, no split opens"
# --------------------------------------------------------------------------- #
tree_sha=$(git -C "$repo" rev-parse HEAD^{tree})
short_tree="${tree_sha:0:12}"
cat > "$tmp/t.lua" <<EOF
vim.cmd("edit rebase-todo")
vim.cmd("set ft=gitrebase")
vim.api.nvim_set_current_line("pick $short_tree tree-not-commit")
local notes = {}
vim.notify = function(msg, _) table.insert(notes, msg) end
vim.api.nvim_win_set_cursor(0, {1, 5})
require('git_sha_goto_declaration').goto_declaration()
print("NOTIFY " .. (notes[1] or ""))
print("FILETYPE " .. vim.bo.filetype)
EOF
out=$(run_nvim "$repo" "$tmp/t.lua")
assert_match    "tree: warns"            "$out" '^NOTIFY .*not a valid commit'
assert_match    "tree: buffer untouched" "$out" '^FILETYPE gitrebase$'

# --------------------------------------------------------------------------- #
echo "== a second gd replaces the shown commit in place"
# --------------------------------------------------------------------------- #
cat > "$tmp/t.lua" <<'EOF'
vim.cmd("edit rebase-todo")
vim.cmd("set ft=gitrebase")

vim.api.nvim_win_set_cursor(0, {1, 5})
require('git_sha_goto_declaration').goto_declaration()
local buf1 = vim.api.nvim_get_current_buf()
local name1 = vim.api.nvim_buf_get_name(buf1)

vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-o>", true, false, true), "x", false)
vim.api.nvim_win_set_cursor(0, {2, 5})
require('git_sha_goto_declaration').goto_declaration()
local name2 = vim.api.nvim_buf_get_name(0)

print("NAME_CHANGED " .. tostring(name1 ~= name2))
print("WINCOUNT " .. #vim.api.nvim_list_wins())
print("OLD_ALIVE " .. tostring(vim.api.nvim_buf_is_valid(buf1)))
EOF
out=$(run_nvim "$repo" "$tmp/t.lua")
assert_match    "second gd: shows another commit" "$out" '^NAME_CHANGED true$'
assert_match    "second gd: still one window"     "$out" '^WINCOUNT 1$'
assert_match    "second gd: old buffer kept alive" "$out" '^OLD_ALIVE true$'

# --------------------------------------------------------------------------- #
echo "== chase: gd on the Parent: line jumps to the parent commit"
# --------------------------------------------------------------------------- #
parent_full=$(git -C "$repo" rev-parse HEAD~2)
cat > "$tmp/t.lua" <<'EOF'
vim.cmd("edit rebase-todo")
vim.cmd("set ft=gitrebase")
vim.api.nvim_win_set_cursor(0, {1, 5})  -- second commit
require('git_sha_goto_declaration').goto_declaration()

-- Find the Parent: line and put the cursor on its SHA, then gd again.
local lines = vim.api.nvim_buf_get_lines(0, 0, 5, false)
local pline
for i, l in ipairs(lines) do
  if l:match("^Parent: ") then pline = i; break end
end
print("PLINE " .. tostring(pline))
vim.api.nvim_win_set_cursor(0, {pline, 10})
require('git_sha_goto_declaration').goto_declaration()
local first = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]
print("FIRST " .. (first or ""))
EOF
out=$(run_nvim "$repo" "$tmp/t.lua")
assert_match    "chase: found parent line" "$out" '^PLINE 2$'
assert_match    "chase: shows parent commit" "$out" "^FIRST commit $parent_full"

# --------------------------------------------------------------------------- #
echo "== <C-o> / <C-i> walk the whole chain of visited commits"
# --------------------------------------------------------------------------- #
cat > "$tmp/t.lua" <<'EOF'
local g = require('git_sha_goto_declaration')
vim.cmd("edit rebase-todo")
vim.cmd("set ft=gitrebase")
local todo = vim.api.nvim_get_current_buf()

vim.api.nvim_win_set_cursor(0, {1, 5})
g.goto_declaration()                      -- todo -> commit A
local a = vim.api.nvim_get_current_buf()
vim.api.nvim_win_set_cursor(0, {2, 10})   -- the "Parent: <sha>" line
g.goto_declaration()                      -- A -> commit B (A's parent)
local b = vim.api.nvim_get_current_buf()

local names = {[todo] = "todo", [a] = "A", [b] = "B"}
local function where()
  local buf = vim.api.nvim_get_current_buf()
  return (names[buf] or "?") .. ":" .. vim.api.nvim_win_get_cursor(0)[1]
end
local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
  return where()
end

local trail = {where()}
table.insert(trail, feed("<C-o>"))
table.insert(trail, feed("<C-o>"))
table.insert(trail, feed("<C-i>"))
table.insert(trail, feed("<C-i>"))
print("DISTINCT " .. tostring(todo ~= a and a ~= b and todo ~= b))
print("TRAIL " .. table.concat(trail, " "))
EOF
out=$(run_nvim "$repo" "$tmp/t.lua")
assert_match    "history: three distinct buffers" "$out" '^DISTINCT true$'
# B -> back to A (on the Parent: line we jumped from) -> back to the todo, then forward again.
assert_match    "history: <C-o>/<C-i> round trip"  "$out" '^TRAIL B:1 A:2 todo:1 A:2 B:1$'

# --------------------------------------------------------------------------- #
echo "== revisiting a commit just renders it again"
# --------------------------------------------------------------------------- #
cat > "$tmp/t.lua" <<'EOF'
local g = require('git_sha_goto_declaration')
vim.cmd("edit rebase-todo")
vim.cmd("set ft=gitrebase")

vim.api.nvim_win_set_cursor(0, {1, 5})
g.goto_declaration()
local first = vim.api.nvim_get_current_buf()
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-o>", true, false, true), "x", false)

vim.api.nvim_win_set_cursor(0, {1, 5})    -- same SHA again
g.goto_declaration()
print("FRESH_BUF " .. tostring(first ~= vim.api.nvim_get_current_buf()))
print("OLD_ALIVE " .. tostring(vim.api.nvim_buf_is_valid(first)))
print("FIRST " .. (vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""))
EOF
out=$(run_nvim "$repo" "$tmp/t.lua")
assert_match    "revisit: new buffer"      "$out" '^FRESH_BUF true$'
assert_match    "revisit: old one is kept" "$out" '^OLD_ALIVE true$'
assert_match    "revisit: commit header"   "$out" '^FIRST commit [0-9a-f]{40}'

# --------------------------------------------------------------------------- #
echo "== show buffers stay out of the buffer list"
# --------------------------------------------------------------------------- #
cat > "$tmp/t.lua" <<'EOF'
vim.cmd("edit rebase-todo")
vim.cmd("set ft=gitrebase")
vim.api.nvim_win_set_cursor(0, {1, 5})
require('git_sha_goto_declaration').goto_declaration()
print("BUFLISTED " .. tostring(vim.bo.buflisted))
print("LISTED_COUNT " .. #vim.fn.getbufinfo({buflisted = 1}))
EOF
out=$(run_nvim "$repo" "$tmp/t.lua")
assert_match    "unlisted: show buffer is unlisted" "$out" '^BUFLISTED false$'
assert_match    "unlisted: only the todo is listed" "$out" '^LISTED_COUNT 1$'

# --------------------------------------------------------------------------- #
echo "== q is mapped to go back"
# --------------------------------------------------------------------------- #
cat > "$tmp/t.lua" <<'EOF'
vim.cmd("edit rebase-todo")
vim.cmd("set ft=gitrebase")
vim.api.nvim_win_set_cursor(0, {1, 5})
require('git_sha_goto_declaration').goto_declaration()
local rhs = ""
for _, m in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
  if m.lhs == "q" then rhs = m.rhs or "" end
end
print("QRHS " .. rhs)
EOF
out=$(run_nvim "$repo" "$tmp/t.lua")
assert_match    "q: maps to <C-o>"      "$out" '^QRHS <C-[Oo]>$'

# --------------------------------------------------------------------------- #
echo "== gd and <CR> are mapped globally, not per filetype"
# --------------------------------------------------------------------------- #
cat > "$tmp/t.lua" <<'EOF'
local gd_found, cr_found = false, false
for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
  if m.lhs == "gd" then gd_found = true end
  if m.lhs == "<CR>" then cr_found = true end
end
print("GDMAP " .. tostring(gd_found))
print("CRMAP " .. tostring(cr_found))
EOF
out=$(run_nvim "$repo" "$tmp/t.lua")
assert_match    "global: gd is mapped"   "$out" '^GDMAP true$'
assert_match    "global: <CR> is mapped" "$out" '^CRMAP true$'

# --------------------------------------------------------------------------- #
echo "== any buffer: gd on a SHA in a plain file opens the split"
# --------------------------------------------------------------------------- #
printf 'Regression introduced by %s, see the diff.\n' "$sha3" > "$repo/notes.md"
cat > "$tmp/t.lua" <<'EOF'
vim.cmd("edit notes.md")
local src_ft = vim.bo.filetype
vim.fn.search("[0-9a-f]\\{7\\}")
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("gd", true, false, true), "x", false)
print("SRC_FILETYPE " .. src_ft)
print("FIRST " .. (vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""))
print("WINCOUNT " .. #vim.api.nvim_list_wins())
print("FILETYPE " .. vim.bo.filetype)
EOF
out=$(run_nvim "$repo" "$tmp/t.lua")
assert_match    "any buffer: source is markdown" "$out" '^SRC_FILETYPE markdown$'
assert_match    "any buffer: commit header"   "$out" '^FIRST commit [0-9a-f]{40}'
assert_match    "any buffer: no new window"   "$out" '^WINCOUNT 1$'
assert_match    "any buffer: show ft is git"  "$out" '^FILETYPE git$'

# --------------------------------------------------------------------------- #
echo "== fallback: gd on a non-SHA word keeps its built-in meaning"
# --------------------------------------------------------------------------- #
printf 'int f(void) {\n  int bar = 1;\n  return bar;\n}\n' > "$repo/fallback.c"
cat > "$tmp/t.lua" <<'EOF'
vim.cmd("edit fallback.c")
vim.api.nvim_win_set_cursor(0, {3, 9})  -- on "bar" in `return bar;`
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("gd", true, false, true), "x", false)
print("LINE " .. vim.api.nvim_win_get_cursor(0)[1])
print("WINCOUNT " .. #vim.api.nvim_list_wins())
EOF
out=$(run_nvim "$repo" "$tmp/t.lua")
assert_match    "fallback gd: jumped to declaration" "$out" '^LINE 2$'
assert_match    "fallback gd: nothing shown"         "$out" '^WINCOUNT 1$'

# --------------------------------------------------------------------------- #
echo "== fallback: <CR> on a non-SHA line keeps its built-in meaning"
# --------------------------------------------------------------------------- #
cat > "$tmp/t.lua" <<'EOF'
vim.cmd("edit fallback.c")
vim.api.nvim_win_set_cursor(0, {1, 0})
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
print("LINE " .. vim.api.nvim_win_get_cursor(0)[1])
print("WINCOUNT " .. #vim.api.nvim_list_wins())
EOF
out=$(run_nvim "$repo" "$tmp/t.lua")
assert_match    "fallback <CR>: moved down" "$out" '^LINE 2$'
assert_match    "fallback <CR>: nothing shown" "$out" '^WINCOUNT 1$'

# --------------------------------------------------------------------------- #
echo "== short hex words (< 7 chars) are not treated as SHAs"
# --------------------------------------------------------------------------- #
printf 'int f(void) {\n  int cafe = 1;\n  return cafe;\n}\n' > "$repo/short.c"
cat > "$tmp/t.lua" <<'EOF'
vim.cmd("edit short.c")
local notes = {}
vim.notify = function(msg, _) table.insert(notes, msg) end
vim.api.nvim_win_set_cursor(0, {3, 9})  -- on "cafe"
require('git_sha_goto_declaration').goto_declaration()
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("gd", true, false, true), "x", false)
print("NOTIFY " .. (notes[1] or ""))
print("LINE " .. vim.api.nvim_win_get_cursor(0)[1])
print("WINCOUNT " .. #vim.api.nvim_list_wins())
EOF
out=$(run_nvim "$repo" "$tmp/t.lua")
assert_match    "short hex: not a SHA"       "$out" '^NOTIFY .*no SHA under cursor'
assert_match    "short hex: gd falls back"   "$out" '^LINE 2$'
assert_match    "short hex: nothing shown"   "$out" '^WINCOUNT 1$'

# --------------------------------------------------------------------------- #
echo "== outside a git repo: gd falls back instead of erroring"
# --------------------------------------------------------------------------- #
bare="$tmp/not-a-repo"
mkdir -p "$bare"
printf 'int f(void) {\n  int deadbeef = 1;\n  return deadbeef;\n}\n' > "$bare/x.c"
cat > "$tmp/t.lua" <<'EOF'
vim.cmd("edit x.c")
vim.api.nvim_win_set_cursor(0, {3, 9})  -- on "deadbeef"
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("gd", true, false, true), "x", false)
print("LINE " .. vim.api.nvim_win_get_cursor(0)[1])
print("WINCOUNT " .. #vim.api.nvim_list_wins())
EOF
out=$(run_nvim "$bare" "$tmp/t.lua")
assert_match    "no repo: gd falls back" "$out" '^LINE 2$'
assert_match    "no repo: nothing shown" "$out" '^WINCOUNT 1$'

# --------------------------------------------------------------------------- #
echo "== a global gd from the user's config is not hijacked"
# --------------------------------------------------------------------------- #
cat > "$tmp/pre.lua" <<'EOF'
vim.keymap.set("n", "gd", "<cmd>echom 'pre-existing'<cr>")
EOF
cat > "$tmp/t.lua" <<'EOF'
local gd_rhs, cr_found = "", false
for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
  if m.lhs == "gd" then gd_rhs = m.rhs or "" end
  if m.lhs == "<CR>" then cr_found = true end
end
print("GDRHS " .. gd_rhs)
print("CRMAP " .. tostring(cr_found))
EOF
out=$(run_nvim "$repo" "$tmp/t.lua" "$tmp/pre.lua")
assert_match    "global guard: user gd preserved" "$out" "^GDRHS <[Cc]md>echom 'pre-existing'<[Cc][Rr]>$"
assert_match    "global guard: <CR> still mapped" "$out" '^CRMAP true$'

# --------------------------------------------------------------------------- #
echo "== a buffer-local <CR> from another plugin wins over the global mapping"
# --------------------------------------------------------------------------- #
cat > "$tmp/t.lua" <<'EOF'
vim.cmd("edit rebase-todo")
vim.cmd("set ft=gitrebase")
-- e.g. quickfix / fugitive / netrw, all of which map <CR> buffer-locally.
vim.keymap.set("n", "<CR>", "<cmd>echom 'other plugin'<cr>", { buffer = true })
vim.api.nvim_win_set_cursor(0, {1, 5})
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
print("FILETYPE " .. vim.bo.filetype)
EOF
out=$(run_nvim "$repo" "$tmp/t.lua")
assert_match    "buffer-local wins: buffer untouched" "$out" '^FILETYPE gitrebase$'

# --------------------------------------------------------------------------- #
echo "== .git/sequencer/todo is auto-detected as gitrebase"
# --------------------------------------------------------------------------- #
seq_repo="$tmp/seq"
new_repo "$seq_repo"
sha=$(git -C "$seq_repo" rev-parse --short HEAD~1)
mkdir -p "$seq_repo/.git/sequencer"
printf 'pick %s second\n' "$sha" > "$seq_repo/.git/sequencer/todo"

cat > "$tmp/t.lua" <<'EOF'
vim.cmd("edit .git/sequencer/todo")
local todo_ft = vim.bo.filetype
vim.api.nvim_win_set_cursor(0, {1, 5})
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("gd", true, false, true), "x", false)
print("FILETYPE " .. todo_ft)
print("FIRST " .. (vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""))
EOF
out=$(run_nvim "$seq_repo" "$tmp/t.lua")
assert_match    "sequencer: filetype gitrebase" "$out" '^FILETYPE gitrebase$'
assert_match    "sequencer: gd shows commit"    "$out" '^FIRST commit [0-9a-f]{40}'

# --------------------------------------------------------------------------- #
echo "== root commit (no parent): shows blank parent, does not crash"
# --------------------------------------------------------------------------- #
root_full=$(git -C "$repo" rev-parse HEAD~2)
root_short="${root_full:0:7}"
cat > "$tmp/t.lua" <<EOF
vim.cmd("edit rebase-todo")
vim.cmd("set ft=gitrebase")
vim.api.nvim_set_current_line("pick $root_short root")
vim.api.nvim_win_set_cursor(0, {1, 5})
require('git_sha_goto_declaration').goto_declaration()
print("LINES_BEGIN")
for _, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, 3, false)) do print(l) end
print("LINES_END")
EOF
out=$(run_nvim "$repo" "$tmp/t.lua")
assert_match    "root: commit header"    "$out" "^commit $root_full"
assert_match    "root: empty parent line" "$out" '^Parent: $'

# --------------------------------------------------------------------------- #
echo "== fugitive: b:fugitive_type set -> attach() is a no-op"
# --------------------------------------------------------------------------- #
cat > "$tmp/t.lua" <<'EOF'
vim.cmd("enew")
vim.b.fugitive_type = "commit"  -- simulate a fugitive :G show buffer
require('git_sha_goto_declaration').attach()
vim.wait(50)  -- drain attach()'s vim.schedule
local gd_found, cr_found = false, false
for _, m in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
  if m.lhs == "gd" then gd_found = true end
  if m.lhs == "<CR>" then cr_found = true end
end
print("GDMAP " .. tostring(gd_found))
print("CRMAP " .. tostring(cr_found))
EOF
out=$(run_nvim "$repo" "$tmp/t.lua")
assert_match    "fugitive: gd NOT mapped"   "$out" '^GDMAP false$'
assert_match    "fugitive: <CR> NOT mapped" "$out" '^CRMAP false$'

# --------------------------------------------------------------------------- #
echo "== attach(): pre-existing buffer-local <CR> survives; gd still mapped"
# --------------------------------------------------------------------------- #
cat > "$tmp/t.lua" <<'EOF'
vim.cmd("enew")
-- Pretend another plugin has already claimed <CR> in this buffer.
vim.keymap.set("n", "<CR>", "<cmd>echom 'pre-existing'<cr>", { buffer = true })
require('git_sha_goto_declaration').attach()
vim.wait(50)
local gd_found, cr_rhs = false, ""
for _, m in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
  if m.lhs == "gd" then gd_found = true end
  if m.lhs == "<CR>" then cr_rhs = m.rhs or "" end
end
print("GDMAP " .. tostring(gd_found))
print("CRRHS " .. cr_rhs)
EOF
out=$(run_nvim "$repo" "$tmp/t.lua")
assert_match    "guard <CR>: gd still mapped"        "$out" '^GDMAP true$'
assert_match    "guard <CR>: pre-existing preserved" "$out" "^CRRHS <[Cc]md>echom 'pre-existing'<[Cc][Rr]>$"

# --------------------------------------------------------------------------- #
echo "== attach(): pre-existing buffer-local gd survives; <CR> still mapped"
# --------------------------------------------------------------------------- #
cat > "$tmp/t.lua" <<'EOF'
vim.cmd("enew")
vim.keymap.set("n", "gd", "<cmd>echom 'pre-existing'<cr>", { buffer = true })
require('git_sha_goto_declaration').attach()
vim.wait(50)
local cr_found, gd_rhs = false, ""
for _, m in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
  if m.lhs == "<CR>" then cr_found = true end
  if m.lhs == "gd" then gd_rhs = m.rhs or "" end
end
print("CRMAP " .. tostring(cr_found))
print("GDRHS " .. gd_rhs)
EOF
out=$(run_nvim "$repo" "$tmp/t.lua")
assert_match    "guard gd: <CR> still mapped"        "$out" '^CRMAP true$'
assert_match    "guard gd: pre-existing preserved"   "$out" "^GDRHS <[Cc]md>echom 'pre-existing'<[Cc][Rr]>$"

# --------------------------------------------------------------------------- #
echo "== vim-fugitive: :Git ++curwin show, in the same window"
# --------------------------------------------------------------------------- #
if [[ -z "$fugitive" ]]; then
  echo "  SKIP vim-fugitive not installed"
else
  repo="$tmp/fug"
  new_repo "$repo"
  sha3=$(git -C "$repo" rev-parse --short HEAD)
  printf 'pick %s third\n' "$sha3" > "$repo/rebase-todo"

  cat > "$tmp/t.lua" <<'EOF'
vim.cmd("edit rebase-todo")
local todo_win = vim.api.nvim_get_current_win()
local todo_buf = vim.api.nvim_get_current_buf()
-- Collect, then print once at the end: a print() interleaved with feedkeys()
-- comes back out of headless nvim without its newline.
local R = {}
local function say(s) R[#R + 1] = s end
local function line1() return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] end
local function keys(k)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(k, true, false, true), "x", false)
end
vim.api.nvim_win_set_cursor(0, {1, 5})
say("SHOWED " .. tostring(require('git_sha_goto_declaration').goto_declaration()))
say("WINCOUNT " .. #vim.api.nvim_list_wins())
say("SAME_WIN " .. tostring(todo_win == vim.api.nvim_get_current_win()))
say("FUGTYPE " .. tostring(vim.b.fugitive_type))
say("FILETYPE " .. vim.bo.filetype)
say("L1 " .. line1())
say("L2 " .. vim.api.nvim_buf_get_lines(0, 1, 2, false)[1])
-- fugitive keeps its own <CR> (jump to the file under the cursor) in its buffers
say("CR_IS_FUGITIVES " .. tostring(vim.fn.maparg("<CR>", "n", false, true).buffer == 1))
-- chase the Parent: SHA from inside the fugitive buffer, then walk back out
vim.api.nvim_win_set_cursor(0, {2, 10})
keys("gd")
say("PARENT_L1 " .. line1())
say("PARENT_WINCOUNT " .. #vim.api.nvim_list_wins())
keys("<C-o>")
say("BACK1_L1 " .. line1())
keys("<C-o>")
say("BACK2_IS_TODO " .. tostring(vim.api.nvim_get_current_buf() == todo_buf))
keys("<C-i>")
say("FWD_IS_COMMIT " .. tostring(vim.b.fugitive_type ~= nil))
for _, l in ipairs(R) do print(l) end
EOF
  out=$(run_fugitive "$repo" "$tmp/t.lua")
  parent=$(git -C "$repo" rev-parse HEAD~1)
  head_full=$(git -C "$repo" rev-parse HEAD)
  assert_match "fugitive: reported success"     "$out" '^SHOWED true$'
  assert_match "fugitive: no new window"        "$out" '^WINCOUNT 1$'
  assert_match "fugitive: reuses the window"    "$out" '^SAME_WIN true$'
  assert_match "fugitive: fugitive owns buffer" "$out" '^FUGTYPE temp$'
  assert_match "fugitive: filetype is git"      "$out" '^FILETYPE git$'
  assert_match "fugitive: our --format survived" "$out" "^L1 commit $head_full"
  assert_match "fugitive: Parent header kept"   "$out" "^L2 Parent: $parent"
  assert_match "fugitive: <CR> left to fugitive" "$out" '^CR_IS_FUGITIVES true$'
  assert_match "fugitive: gd chases the parent" "$out" "^PARENT_L1 commit $parent"
  assert_match "fugitive: parent in same window" "$out" '^PARENT_WINCOUNT 1$'
  assert_match "fugitive: <C-o> back to commit" "$out" "^BACK1_L1 commit $head_full"
  assert_match "fugitive: <C-o> back to todo"   "$out" '^BACK2_IS_TODO true$'
  assert_match "fugitive: <C-i> forward again"  "$out" '^FWD_IS_COMMIT true$'

  # A hex word that is not a commit must leave the window alone, fugitive or not.
  cat > "$tmp/t.lua" <<'EOF'
vim.cmd("edit rebase-todo")
vim.api.nvim_set_current_line("pick deadbeef nope")
local notes = {}
vim.notify = function(msg, _) table.insert(notes, msg) end
vim.api.nvim_win_set_cursor(0, {1, 5})
require('git_sha_goto_declaration').goto_declaration()
print("NOTIFY " .. (notes[1] or ""))
print("WINCOUNT " .. #vim.api.nvim_list_wins())
print("FUGTYPE " .. tostring(vim.b.fugitive_type))
EOF
  out=$(run_fugitive "$repo" "$tmp/t.lua")
  assert_match "fugitive: invalid SHA warns"        "$out" '^NOTIFY .*not a valid commit: deadbeef'
  assert_match "fugitive: invalid opens no window"  "$out" '^WINCOUNT 1$'
  assert_match "fugitive: invalid leaves buffer"    "$out" '^FUGTYPE nil$'
fi

# --------------------------------------------------------------------------- #
echo
if [[ $fail -eq 0 ]]; then
  printf '\n  %d passed, 0 failed\n\n' "$pass"
  exit 0
else
  printf '\n  %d passed, %d failed\n' "$pass" "$fail"
  printf '  failed:\n'
  for n in "${failed[@]}"; do printf '    - %s\n' "$n"; done
  echo
  exit 1
fi
