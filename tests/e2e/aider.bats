#!/usr/bin/env bats
# bats file_tags=suite:e2e

load ../test_helper.bash
load tmux_utils.bash
load agent_tui_harness.bash

@test "[E2E-TUI] aider boots and completes roundtrip" {
  sft_require_cmd_or_skip "aider"
  sft_require_env_or_skip "OPENAI_API_KEY"

  local agent_home="${AGENT_TUI_WORKDIR}/aider-home"
  local config_dir="${AGENT_TUI_WORKDIR}/aider-config"
  local auth_log_path="${AGENT_TUI_ROOT}/aider-login.log"
  local input_history_path="${config_dir}/.aider.input.history"
  local chat_history_path="${config_dir}/.aider.chat.history.md"
  local model="gpt-5.6-luna"

  AGENT_TUI_READY_PATTERN='ask>'

  prepare_agent_state "${agent_home}" "${config_dir}" "${input_history_path}" "${chat_history_path}"
  login_agent "${config_dir}" "${auth_log_path}" "${model}"
  configure_agent_tui

  OPENAI_API_KEY="${OPENAI_API_KEY}" \
    sft_tmux_start \
      safehouse --env-pass=OPENAI_API_KEY -- \
      "HOME=${agent_home}" \
      aider \
      --model="${model}" \
      --yes-always \
      --chat-mode ask \
      --no-git \
      --no-pretty \
      --no-check-update \
      --no-show-release-notes \
      --no-analytics \
      --no-browser \
      --input-history-file "${input_history_path}" \
      --chat-history-file "${chat_history_path}"
  sft_agent_tui_handle_startup_gates
  sft_tmux_assert_roundtrip
}

prepare_agent_state() {
  local agent_home="$1"
  local config_dir="$2"
  local input_history_path="$3"
  local chat_history_path="$4"

  mkdir -p "${agent_home}" "${config_dir}"
  : >"${input_history_path}"
  : >"${chat_history_path}"
}

login_agent() {
  local _config_dir="$1"
  local _auth_log_path="$2"
  local _model="$3"

  return 0
}

configure_agent_tui() {
  if (( AGENT_TUI_STARTUP_WAIT_SECS < 40 )); then
    AGENT_TUI_STARTUP_WAIT_SECS=40
  fi

  return 0
}
