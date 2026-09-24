#!/bin/sh

set -eu

action=$1
script_path=$2
shift 2

export CODEX_PROVIDER_SETUP_SKIP_MAIN=1
export CODEX_PROVIDER_SETUP_TEST_INPUT=1
export NO_COLOR=1
export TERM=dumb

# shellcheck source=dist/codex-provider-setup.sh
. "$script_path"

set_codex_home() {
  CODEX_HOME_DIR=$1
  CONFIG_PATH="$CODEX_HOME_DIR/config.toml"
  BACKUP_DIR="$CODEX_HOME_DIR/$BACKUP_DIRNAME"
  BACKUP_CONFIG="$BACKUP_DIR/config.toml"
  MANIFEST_PATH="$BACKUP_DIR/manifest.txt"
}

case $action in
  transform)
    input_path=$1
    output_path=$2
    report_path=$3
    SELECTED_PROVIDER=$4
    SELECTED_BASE_URL=$5
    SELECTED_MODEL=$6
    SELECTED_REASONING_EFFORT=$7
    SELECTED_CONTEXT_WINDOW=$8
    API_KEY=$9
    escaped_model=$(toml_escape "$SELECTED_MODEL")
    transform_config \
      "$input_path" \
      "$output_path" \
      "$report_path" \
      "$escaped_model" \
      "$SELECTED_REASONING_EFFORT" \
      "$SELECTED_CONTEXT_WINDOW"
    write_managed_provider "$output_path"
    ;;
  contains-managed-provider)
    CONFIG_PATH=$1
    if contains_managed_provider; then printf true; else printf false; fi
    ;;
  resolve-base-url)
    resolve_base_url "$1" > /dev/null
    printf '%s' "$RESOLVED_BASE_URL"
    ;;
  ui-layout)
    HAS_INTERACTION_UI=0
    write_feedback_message Notice Info
    write_feedback_table Summary Unordered Info 'Name: Value'
    write_feedback_table Changes Unordered Change Changed
    write_feedback_table Menu Ordered 1 First 2 Second
    ;;
  message-types)
    for type in Info Detail Success Warning Error Prompt Change 7; do
      write_message "$type" "$type"
    done
    if write_message Invalid Arbitrary > /dev/null 2>&1; then
      printf 'Unknown message type was accepted\n' >&2
      exit 1
    fi
    printf 'INVALID=REJECTED'
    ;;
  choice)
    HAS_INTERACTION_UI=0
    read_choice Choose Select 1 First 2 Second
    printf 'RESULT=%s' "$CHOICE_VALUE"
    ;;
  default-input)
    HAS_INTERACTION_UI=0
    read_value_with_default 'Base URL' 'Enter Base URL' 'https://api.example/v1'
    printf 'RESULT=%s' "$DEFAULTED_VALUE"
    ;;
  messages)
    message ConfigUpdated config.toml
    printf '\n'
    message ConfigWriteFailed backup 'write failed'
    ;;
  configure)
    set_codex_home "$1"
    SELECTED_PROVIDER=$2
    SELECTED_BASE_URL=$3
    SELECTED_MODEL=$4
    SELECTED_REASONING_EFFORT=$5
    SELECTED_CONTEXT_WINDOW=$6
    API_KEY=$7
    read_api_key() { :; }
    invoke_configure
    ;;
  restore)
    set_codex_home "$1"
    read_choice() { CHOICE_VALUE=1; }
    invoke_restore
    ;;
  *)
    printf 'Unknown adapter action: %s\n' "$action" >&2
    exit 1
    ;;
esac
