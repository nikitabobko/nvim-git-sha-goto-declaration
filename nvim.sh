#!/usr/bin/env bash
# Run nvim with factory-default settings plus this plugin, and nothing else.
# Handy for reproducing a bug without your own config in the way.
#
#   ./nvim.sh some-file
#   GIT_SEQUENCE_EDITOR=./nvim.sh git rebase -i HEAD~5

set -e          # Exit if one of commands exit with non-zero exit code
set -u          # Treat unset variables and parameters other than the special parameters '@' or '*' as an error
set -o pipefail # Any command failed in the pipe fails the whole pipe

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --clean skips the user's config, shada and plugins, but leaves 'loadplugins'
# on, so prepending the repo to 'runtimepath' before startup is enough for
# plugin/ to be sourced and lua/ to be require()-able.
exec nvim --clean --cmd "set runtimepath^=$here" "$@"
