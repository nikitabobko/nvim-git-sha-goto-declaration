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

run_nvim() {
  local cwd="$1" script="$2"
  (
    cd "$cwd"
    nvim --headless --clean -u NONE \
      --cmd "set rtp+=$here" \
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
  git -C "$dir" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "first"
  git -C "$dir" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "second"
  git -C "$dir" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "third"
}

# --------------------------------------------------------------------------- #
echo "== happy path: gd on a SHA opens split with commit + parent header"
# --------------------------------------------------------------------------- #
repo="$tmp/happy"
new_repo "$repo"
sha2=$(git -C "$repo" rev-parse --short HEAD~1)
sha3=$(git -C "$repo" rev-parse --short HEAD)
printf 'pick %s second\npick %s third\n' "$sha2" "$sha3" > "$repo/rebase-todo"

cat > "$tmp/t.lua" <<'EOF'
vim.cmd("edit rebase-todo")
vim.cmd("set ft=gitrebase")
vim.api.nvim_win_set_cursor(0, {1, 5})
require('git_sha_goto_declaration').goto_declaration()
print("LINES_BEGIN")
for _, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, 5, false)) do print(l) end
print("LINES_END")
print("WINCOUNT " .. #vim.api.nvim_list_wins())
print("MODIFIABLE " .. tostring(vim.bo.modifiable))
print("FILETYPE " .. vim.bo.filetype)
print("BUFNAME " .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t"))
EOF
out=$(run_nvim "$repo" "$tmp/t.lua")
assert_match "happy: commit header"      "$out" '^commit [0-9a-f]{40}'
assert_match "happy: parent header"      "$out" '^Parent: [0-9a-f]{40}'
assert_match "happy: author header"      "$out" '^Author: '
assert_match "happy: window count is 2"  "$out" '^WINCOUNT 2$'
assert_match "happy: buffer not modifiable" "$out" '^MODIFIABLE false$'
assert_match "happy: filetype is git"    "$out" '^FILETYPE git$'
assert_match "happy: buffer named"       "$out" '^BUFNAME git show [0-9a-f]{12}$'

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
print("WINCOUNT " .. #vim.api.nvim_list_wins())
EOF
out=$(run_nvim "$repo" "$tmp/t.lua")
assert_match    "no-sha: warns"          "$out" '^NOTIFY .*no SHA under cursor'
assert_match    "no-sha: no split"       "$out" '^WINCOUNT 1$'

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
print("WINCOUNT " .. #vim.api.nvim_list_wins())
EOF
out=$(run_nvim "$repo" "$tmp/t.lua")
assert_match    "invalid: warns"         "$out" '^NOTIFY .*not a valid commit: deadbeef'
assert_match    "invalid: no split"      "$out" '^WINCOUNT 1$'

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
print("WINCOUNT " .. #vim.api.nvim_list_wins())
EOF
out=$(run_nvim "$repo" "$tmp/t.lua")
assert_match    "tree: warns"            "$out" '^NOTIFY .*not a valid commit'
assert_match    "tree: no split"         "$out" '^WINCOUNT 1$'

# --------------------------------------------------------------------------- #
echo "== reuse: second gd swaps contents in place (same win + buffer)"
# --------------------------------------------------------------------------- #
cat > "$tmp/t.lua" <<'EOF'
vim.cmd("edit rebase-todo")
vim.cmd("set ft=gitrebase")
local todo_win = vim.api.nvim_get_current_win()

vim.api.nvim_win_set_cursor(0, {1, 5})
require('git_sha_goto_declaration').goto_declaration()
local win1 = vim.api.nvim_get_current_win()
local buf1 = vim.api.nvim_get_current_buf()
local name1 = vim.api.nvim_buf_get_name(buf1)

vim.api.nvim_set_current_win(todo_win)
vim.api.nvim_win_set_cursor(0, {2, 5})
require('git_sha_goto_declaration').goto_declaration()
local win2 = vim.api.nvim_get_current_win()
local buf2 = vim.api.nvim_get_current_buf()
local name2 = vim.api.nvim_buf_get_name(buf2)

print("SAME_WIN " .. tostring(win1 == win2))
print("SAME_BUF " .. tostring(buf1 == buf2))
print("NAME_CHANGED " .. tostring(name1 ~= name2))
print("WINCOUNT " .. #vim.api.nvim_list_wins())
local shows = 0
for _, w in ipairs(vim.api.nvim_list_wins()) do
  local b = vim.api.nvim_win_get_buf(w)
  local ok, m = pcall(vim.api.nvim_buf_get_var, b, "git_sha_show_buffer")
  if ok and m then shows = shows + 1 end
end
print("SHOWS " .. shows)
EOF
out=$(run_nvim "$repo" "$tmp/t.lua")
assert_match    "reuse: same window"     "$out" '^SAME_WIN true$'
assert_match    "reuse: same buffer"     "$out" '^SAME_BUF true$'
assert_match    "reuse: name changed"    "$out" '^NAME_CHANGED true$'
assert_match    "reuse: 2 windows total" "$out" '^WINCOUNT 2$'
assert_match    "reuse: 1 show buffer"   "$out" '^SHOWS 1$'

# --------------------------------------------------------------------------- #
echo "== chase: gd inside the show split jumps to the parent commit"
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
echo "== q is mapped to close the show split"
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
assert_match    "q: maps to close"       "$out" '^QRHS <[Cc]md>close<[Cc][Rr]>$'

# --------------------------------------------------------------------------- #
echo "== gd is mapped in gitrebase / gitcommit / git filetypes"
# --------------------------------------------------------------------------- #
for ft in gitrebase gitcommit git; do
  cat > "$tmp/t.lua" <<EOF
vim.cmd("enew")
vim.bo.filetype = "$ft"
vim.cmd("doautocmd FileType $ft")
local found = false
for _, m in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
  if m.lhs == "gd" then found = true end
end
print("GDMAP " .. tostring(found))
EOF
  out=$(run_nvim "$repo" "$tmp/t.lua")
  assert_match  "ft $ft: gd is mapped"   "$out" '^GDMAP true$'
done

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
print("FILETYPE " .. vim.bo.filetype)
local found = false
for _, m in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
  if m.lhs == "gd" then found = true end
end
print("GDMAP " .. tostring(found))
EOF
out=$(run_nvim "$seq_repo" "$tmp/t.lua")
assert_match    "sequencer: filetype gitrebase" "$out" '^FILETYPE gitrebase$'
assert_match    "sequencer: gd mapped"          "$out" '^GDMAP true$'

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
