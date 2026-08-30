#!/usr/bin/env bats
# bats file_tags=suite:e2e

load ../test_helper.bash
load tmux_utils.bash
load agent_tui_harness.bash

@test "[E2E-TUI] opencode boots and completes roundtrip" {
  sft_require_cmd_or_skip "opencode"
  sft_require_env_or_skip "ANTHROPIC_API_KEY"

  local agent_home="${AGENT_TUI_WORKDIR}/opencode-home"
  local config_dir="${AGENT_TUI_WORKDIR}/opencode-config"
  local auth_log_path="${AGENT_TUI_ROOT}/opencode-login.log"
  local model="anthropic/claude-sonnet-5"

  AGENT_TUI_READY_PATTERN='Ask anything'

  prepare_agent_state "${agent_home}" "${config_dir}"
  login_agent "${config_dir}" "${auth_log_path}" "${model}"
  configure_agent_tui

  ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}" \
  sft_tmux_start \
    safehouse --env-pass=ANTHROPIC_API_KEY -- \
    "HOME=${agent_home}" \
    opencode --model="${model}"
  sft_agent_tui_handle_startup_gates
  sft_tmux_assert_roundtrip
}

prepare_agent_state() {
  local agent_home="$1"
  local config_dir="$2"

  mkdir -p "${agent_home}" "${config_dir}"
}

login_agent() {
  local _config_dir="$1"
  local _auth_log_path="$2"
  local _model="$3"

  return 0
}

configure_agent_tui() {
  if (( AGENT_TUI_STARTUP_WAIT_SECS < 60 )); then
    AGENT_TUI_STARTUP_WAIT_SECS=60
  fi

  return 0
}
