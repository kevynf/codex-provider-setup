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

test_menu_items_are_fixed() {
  keys=$(setup_menu_items | while IFS="$(printf '\t')" read -r key label; do
    [ -n "$label" ] || exit 1
    printf '%s,' "$key"
  done)
  [ "$keys" = '1,2,3,4,9,' ]
}

test_provider_info_ignores_other_sections() {
  config="$test_root/managed.toml"
  {
    printf 'model = "gpt-6-sol"\n'
    printf '\n'
    printf '[model_providers.keep]\n'
    printf 'name = "Keep"\n'
    printf '\n'
    printf '[model_providers.codex_provider_setup_1]\n'
    printf 'name = "Current"\n'
    printf 'base_url = "https://current.example/v1"\n'
    printf '\n'
    printf '[model_providers.codex_provider_setup_1.headers]\n'
    printf 'X-Custom = "1"\n'
  } > "$config"
  CONFIG_PATH=$config
  get_provider_info codex_provider_setup_1
  [ "$PROVIDER_PRESENT" -eq 1 ] || return 1
  [ "$PROVIDER_RECOGNIZABLE" -eq 0 ] || return 1
  [ "$PROVIDER_NAME" = 'Current' ] || return 1
  [ "$PROVIDER_BASE_URL" = 'https://current.example/v1' ] || return 1
  printf 'model = "gpt-6-sol"\n' > "$config"
  get_provider_info codex_provider_setup_1
  [ "$PROVIDER_PRESENT" -eq 0 ] || return 1
}

run_test 'Shell syntax is valid' test_shell_syntax
run_test 'Runtime does not depend on awk or sed' test_no_optional_text_processors
run_test 'Menu exposes the fixed provider operations' test_menu_items_are_fixed
run_test 'Provider read-back ignores unrelated sections' test_provider_info_ignores_other_sections

printf '\nShell-specific checks: %s passed; %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
