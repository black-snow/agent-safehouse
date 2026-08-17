#!/usr/bin/env bats
# bats file_tags=suite:e2e

load ../test_helper.bash
load tmux_utils.bash
load agent_tui_harness.bash

@test "[E2E-TUI] cline boots and completes roundtrip" {
  sft_require_cmd_or_skip "cline"
  sft_require_env_or_skip "OPENAI_API_KEY"

  local agent_home="${AGENT_TUI_WORKDIR}/cline-home"
  local config_dir="${AGENT_TUI_WORKDIR}/cline-config"
  local auth_log_path="${AGENT_TUI_ROOT}/cline-login.log"
  local input_ready_pattern='What can I do for you\?|/ for commands|Plan .* Act'
  local trust_gate_pattern=""
  local permission_gate_pattern=""
  local restart_gate_pattern=""
  # cline overlays a "Try ClinePass" subscription promo on the input line at startup.
  # It closes on any key other than Enter (Enter opens the signup URL in a browser).
  local promo_gate_pattern='Try ClinePass|any other key to close'
  local promo_settle_secs="${SAFEHOUSE_AGENT_TUI_CLINE_PROMO_SETTLE_SECS:-1.5}"
  local model="gpt-5.6-luna"

  prepare_agent_state "${agent_home}" "${config_dir}"
  login_agent "${config_dir}" "${auth_log_path}" "${model}"
  configure_agent_tui

  sft_tmux_start \
    safehouse -- \
    "HOME=${agent_home}" \
    cline --config "${config_dir}" --model "${model}" -a -y

  # Wait for input ready. Sequence:
  # 1. ${input_ready_pattern} observed. Input IGNORED (if promo coming).
  # 2. About 300-400ms pass.
  #    ${promo_gate_pattern} observed.
  # 3. Press Escape.
  #    ${input_ready_pattern} observed. Input accepted.
  handle_startup_gates 1  # wait for first ${input_ready_pattern}
  sleep "${promo_settle_secs}"  # wait for promo to display (if there is one)
  handle_startup_gates 1  # dismiss promo (if there is one); wait for last ${input_ready_pattern}

  sft_tmux_assert_roundtrip
}

prepare_agent_state() {
  local agent_home="$1"
  local config_dir="$2"

  mkdir -p "${agent_home}" "${config_dir}"
}

login_agent() {
  local config_dir="$1"
  local auth_log_path="$2"
  local model="$3"

  if ! sft_safehouse_run_capture "${auth_log_path}" cline auth --config "${config_dir}" --provider openai-native --apikey "${OPENAI_API_KEY}" --modelid "${model}"; then
    cat "${auth_log_path}" >&2
    return 1
  fi
}

configure_agent_tui() {
  return 0
}

handle_startup_gates() {
  local pass="${1:-1}"
  local combined_pattern="${input_ready_pattern}"
  local gate_pattern=""
  local -a gate_patterns=(
    "${trust_gate_pattern:-}"
    "${permission_gate_pattern:-}"
    "${restart_gate_pattern:-}"
    "${promo_gate_pattern:-}"
  )

  (( pass <= 5 )) || {
    AGENT_TUI_FAILED=1
    printf 'too many startup gate passes\n' >&2
    sft_agent_tui_write_screen_capture >&2 || true
    return 1
  }

  for gate_pattern in "${gate_patterns[@]}"; do
    [[ -n "${gate_pattern}" ]] || continue
    combined_pattern="${combined_pattern}|${gate_pattern}"
  done

  sft_tmux_wait_until_regex \
    "${combined_pattern}" \
    "${AGENT_TUI_STARTUP_WAIT_SECS}" \
    "${AGENT_TUI_POLL_INTERVAL_SECS}" || {
      AGENT_TUI_FAILED=1
      sft_agent_tui_write_screen_capture >&2 || true
      return 1
    }
  local -a frame=("${SFT_TMUX_LAST_CAPTURE[@]}")

  # Dismiss the promo before checking input readiness: the overlay leaves part of the
  # input line visible, so input_ready can match while the prompt is still covered.
  if [[ -n "${promo_gate_pattern:-}" ]] && sft_tmux_matches_regex "${promo_gate_pattern}" "${frame[@]}"; then
    sft_agent_tui_dismiss_gate "${promo_gate_pattern}" Escape
    handle_startup_gates "$((pass + 1))"
    return $?
  fi

  if sft_tmux_matches_regex "${input_ready_pattern}" "${frame[@]}"; then
    return 0
  fi

  if [[ -n "${trust_gate_pattern:-}" ]] && sft_tmux_matches_regex "${trust_gate_pattern}" "${frame[@]}"; then
    sft_agent_tui_dismiss_gate "${trust_gate_pattern}" Enter
    handle_startup_gates "$((pass + 1))"
    return $?
  fi

  if [[ -n "${permission_gate_pattern:-}" ]] && sft_tmux_matches_regex "${permission_gate_pattern}" "${frame[@]}"; then
    sft_agent_tui_dismiss_gate "${permission_gate_pattern}" Enter
    handle_startup_gates "$((pass + 1))"
    return $?
  fi

  if [[ -n "${restart_gate_pattern:-}" ]] && sft_tmux_matches_regex "${restart_gate_pattern}" "${frame[@]}"; then
    sft_agent_tui_dismiss_gate "${restart_gate_pattern}"
    handle_startup_gates "$((pass + 1))"
    return $?
  fi

  AGENT_TUI_FAILED=1
  printf 'unhandled startup gate\n' >&2
  sft_agent_tui_write_screen_capture "${frame[@]}" >&2 || true
  return 1
}
