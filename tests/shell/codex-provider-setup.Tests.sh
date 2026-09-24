#!/bin/sh

set -u

project_root=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
script_path="$project_root/dist/codex-provider-setup.sh"
test_root="$project_root/.tmp/shell-tests-$$"
passed=0
failed=0

mkdir -p "$test_root"
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

export CODEX_PROVIDER_SETUP_SKIP_MAIN=1
export CODEX_PROVIDER_SETUP_TEST_INPUT=1
export NO_COLOR=1
export TERM=dumb

# shellcheck source=dist/codex-provider-setup.sh
. "$script_path"

pass() {
  printf '[PASS] %s\n' "$1"
  passed=$((passed + 1))
}

fail() {
  printf '[FAIL] %s\n  %s\n' "$1" "$2"
  failed=$((failed + 1))
}

run_test() {
  name=$1
  shift
  error_file="$test_root/error"
  if "$@" 2> "$error_file"; then
    pass "$name"
  else
    error=$(cat "$error_file")
    fail "$name" "${error:-Test assertion failed.}"
  fi
}

test_shell_syntax() {
  sh -n "$script_path"
}

test_no_optional_text_processors() {
  if grep -Eq '(^|[[:space:]])(awk|sed)([[:space:]]|$)' "$script_path"; then
    printf 'Generated runtime invokes awk or sed'
    return 1
  fi
}

run_test 'Shell syntax is valid' test_shell_syntax
run_test 'Runtime does not depend on awk or sed' test_no_optional_text_processors

printf '\nShell-specific checks: %s passed; %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
