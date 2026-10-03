#!/bin/sh

set -u

project_root=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
script_path="$project_root/dist/claude-provider-setup.sh"
test_root="$project_root/.tmp/claude-shell-tests-$$"
passed=0
failed=0

mkdir -p "$test_root"
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

export NO_COLOR=1
export TERM=dumb

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

configure_script() {
  claude_home=$1
  printf '%s\n' \
    'Proxy' \
    'https://proxy.example/v1' \
    'third-party-model' \
    'test-token' \
    | CLAUDE_CONFIG_DIR="$claude_home" \
      CLAUDE_PROVIDER_SETUP_TEST_INPUT=1 \
      sh "$script_path" configure > /dev/null
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

test_new_settings() {
  case_root="$test_root/new-settings"
  mkdir -p "$case_root"
  configure_script "$case_root"
  node - "$case_root/settings.json" << 'NODE'
const fs = require('node:fs');
const settings = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const expectedKeys = [
  'ANTHROPIC_MODEL',
  'ANTHROPIC_DEFAULT_OPUS_MODEL',
  'ANTHROPIC_DEFAULT_SONNET_MODEL',
  'ANTHROPIC_DEFAULT_HAIKU_MODEL',
];
for (const key of expectedKeys) {
  if (settings.env[key] !== 'third-party-model') throw new Error(`${key} was not initialized`);
}
if (settings.env.ANTHROPIC_BASE_URL !== 'https://proxy.example/v1') throw new Error('Base URL is missing');
if (settings.env.ANTHROPIC_AUTH_TOKEN !== 'test-token') throw new Error('Auth token is missing');
if (settings.env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC !== '1') throw new Error('Traffic flag is missing');
NODE
  grep -q '^original_settings_existed=0$' "$case_root/.provider-backup/manifest.txt"
}

test_existing_settings_are_preserved() {
  case_root="$test_root/existing-settings"
  mkdir -p "$case_root"
  original='{"env":{"ANTHROPIC_DEFAULT_OPUS_MODEL":"opus-x","ANTHROPIC_DEFAULT_SONNET_MODEL":"sonnet-x","ANTHROPIC_DEFAULT_HAIKU_MODEL":"haiku-x","CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC":"1","KEEP":"yes"},"permissions":{"defaultMode":"acceptEdits"}}'
  printf '%s\n' "$original" > "$case_root/settings.json"
  configure_script "$case_root"
  node - "$case_root/settings.json" << 'NODE'
const fs = require('node:fs');
const settings = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (settings.env.ANTHROPIC_MODEL) throw new Error('Existing model mappings were overridden');
if (settings.env.ANTHROPIC_DEFAULT_SONNET_MODEL !== 'sonnet-x') throw new Error('Existing model mapping changed');
if (settings.env.KEEP !== 'yes') throw new Error('Existing env setting changed');
if (settings.permissions.defaultMode !== 'acceptEdits') throw new Error('Unrelated setting changed');
if (settings.env.ANTHROPIC_BASE_URL !== 'https://proxy.example/v1') throw new Error('Base URL was not updated');
NODE
  printf '%s\n' "$original" | cmp - "$case_root/.provider-backup/settings.json"
  CLAUDE_CONFIG_DIR="$case_root" sh "$script_path" restore > /dev/null
  printf '%s\n' "$original" | cmp - "$case_root/settings.json"
  [ ! -d "$case_root/.provider-backup" ]
}

test_invalid_json_does_not_overwrite_original() {
  case_root="$test_root/invalid-json"
  mkdir -p "$case_root"
  printf '%s\n' '{invalid' > "$case_root/settings.json"
  if configure_script "$case_root" > "$test_root/invalid-output" 2>&1; then
    printf 'Invalid JSON was accepted'
    return 1
  fi
  printf '%s\n' '{invalid' | cmp - "$case_root/settings.json"
}

run_test 'Claude Code Shell syntax is valid' test_shell_syntax
run_test 'Claude Code runtime does not depend on awk or sed' test_no_optional_text_processors
run_test 'Claude Code creates third-party settings without an original file' test_new_settings
run_test 'Claude Code preserves mappings and restores the original settings' test_existing_settings_are_preserved
run_test 'Claude Code rejects invalid JSON without overwriting it' test_invalid_json_does_not_overwrite_original

printf '\nClaude Code Shell tests: %s passed; %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
