#!/usr/bin/env bash
# nvim.sh plus vim-fugitive, so you get the fugitive code path -- the commit
# opens in a fugitive buffer rather than the plugin's own. Everything else is
# still factory defaults, with your own config out of the way.
#
#   ./nvim_fugitive.sh some-file
#   GIT_SEQUENCE_EDITOR=./nvim_fugitive.sh git rebase -i HEAD~5
#   FUGITIVE=~/src/vim-fugitive ./nvim_fugitive.sh some-file
#
# --print-path reports where fugitive was found and exits, which is how test.sh
# decides whether it can run the fugitive tests.

set -e          # Exit if one of commands exit with non-zero exit code
set -u          # Treat unset variables and parameters other than the special parameters '@' or '*' as an error
set -o pipefail # Any command failed in the pipe fails the whole pipe

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# $FUGITIVE wins, and a wrong one is an error rather than a quiet fallback to
# the search below -- otherwise a typo just looks like fugitive isn't installed.
fugitive="${FUGITIVE:-}"
if [[ -n "$fugitive" && ! -f "$fugitive/plugin/fugitive.vim" ]]; then
  echo "nvim_fugitive.sh: no plugin/fugitive.vim under FUGITIVE=$fugitive" >&2
  exit 1
fi

# Otherwise look where the usual plugin managers put it. An unmatched glob stays
# literal, and then simply fails the -f test.
if [[ -z "$fugitive" ]]; then
  for d in ~/.local/share/nvim/lazy/vim-fugitive \
           ~/.local/share/nvim/plugged/vim-fugitive \
           ~/.local/share/nvim/site/pack/*/*/vim-fugitive \
           ~/.config/nvim/pack/*/*/vim-fugitive \
           ~/.vim/plugged/vim-fugitive \
           ~/.vim/pack/*/*/vim-fugitive; do
    if [[ -f "$d/plugin/fugitive.vim" ]]; then
      fugitive="$d"
      break
    fi
  done
fi

if [[ "${1:-}" == "--print-path" ]]; then
  printf '%s\n' "$fugitive"
  exit 0
fi

if [[ -z "$fugitive" ]]; then
  echo "nvim_fugitive.sh: vim-fugitive not found. Set FUGITIVE=/path/to/vim-fugitive" >&2
  exit 1
fi

# --clean skips the user's config, shada and plugins, but leaves 'loadplugins'
# on, so prepending both directories to 'runtimepath' before startup is enough
# for each plugin/ to be sourced and lua/ to be require()-able.
exec nvim --clean --cmd "set runtimepath^=$here" --cmd "set runtimepath^=$fugitive" "$@"
