#!/usr/bin/env bats
# bats file_tags=suite:e2e

load ../test_helper.bash
load tmux_utils.bash
load agent_tui_harness.bash

@test "[E2E-TUI] copilot boots and completes roundtrip" {
  sft_require_cmd_or_skip "copilot"
  sft_require_env_or_skip "OPENAI_API_KEY"

  local agent_home="${AGENT_TUI_WORKDIR}/copilot-home"
  local config_dir="${AGENT_TUI_WORKDIR}/copilot-config"
  local auth_log_path="${AGENT_TUI_ROOT}/copilot-login.log"
  local input_ready_pattern='Please use /login|/ commands .* \? help'
  local trust_gate_pattern='Confirm folder trust|Do you trust the files in this folder\?'
  local permission_gate_pattern=""
  local restart_gate_pattern=""
  # Print if the `copilot` on PATH is the VS Code Copilot Chat launcher shim rather
  # than the standalone GitHub Copilot CLI
  local vsc_copilot_pattern='Cannot find GitHub Copilot CLI'
  local model="gpt-5.6-luna"

  prepare_agent_state "${agent_home}" "${config_dir}"
  login_agent "${config_dir}" "${auth_log_path}" "${model}"
  configure_agent_tui

  # Copilot CLI's BYOK (bring-your-own-key) mode <https://docs.github.com/copilot/how-tos/copilot-cli/customize-copilot/use-byok-models>
  # skips GitHub authentication entirely once COPILOT_PROVIDER_BASE_URL is set, so
  # the OpenAI key the E2E suite already has can drive the roundtrip directly.
  # The var name doesn't match COPILOT_PROVIDER_API_KEY, so it's re-exported under
  # that name before --env-pass hands it to the sandboxed session (never on the
  # command line -- see sft_agent_tui_apply_env_pass_names).
  COPILOT_PROVIDER_API_KEY="${OPENAI_API_KEY}" \
    sft_tmux_start \
      safehouse --env-pass=COPILOT_PROVIDER_API_KEY -- \
      "HOME=${agent_home}" \
      "COPILOT_PROVIDER_BASE_URL=https://api.openai.com/v1" \
      "COPILOT_PROVIDER_WIRE_API=responses" \
      "COPILOT_MODEL=${model}" \
      copilot --no-auto-update
  handle_startup_gates 1 || {
    local gate_status=$?
    (( gate_status == SFT_AGENT_TUI_GATE_SKIP )) \
      && skip "GitHub Copilot CLI not installed, although VS Code Copilot Chat launcher is present"
    return "${gate_status}"
  }
  sft_tmux_assert_roundtrip
}

prepare_agent_state() {
  local agent_home="$1"
  local config_dir="$2"

  mkdir -p "${agent_home}/Library/Caches" "${config_dir}"
}

login_agent() {
  local _config_dir="$1"
  local _auth_log_path="$2"
  local _model="$3"

  return 0
}

configure_agent_tui() {
  # Each test run gets a fresh HOME, so the packaged Node SEA launcher has to
  # unpack its bundled package into ~/Library/Caches/copilot/pkg on every run;
  # that alone has been observed taking ~26s inside the sandbox, on top of the
  # BYOK provider/model-catalog validation and the trust-gate render.
  if (( AGENT_TUI_STARTUP_WAIT_SECS < 60 )); then
    AGENT_TUI_STARTUP_WAIT_SECS=60
  fi

  return 0
}

# NOTE: Exits with special code SFT_AGENT_TUI_GATE_SKIP if
#       ${vsc_copilot_pattern} is observed.
handle_startup_gates() {
  local pass="${1:-1}"
  local combined_pattern="${input_ready_pattern}"
  local gate_pattern=""
  local -a gate_patterns=(
    "${trust_gate_pattern:-}"
    "${permission_gate_pattern:-}"
    "${restart_gate_pattern:-}"
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

  if [[ -n "${vsc_copilot_pattern:-}" ]]; then
    combined_pattern="${combined_pattern}|${vsc_copilot_pattern}"
  fi

  sft_tmux_wait_until_regex \
    "${combined_pattern}" \
    "${AGENT_TUI_STARTUP_WAIT_SECS}" \
    "${AGENT_TUI_POLL_INTERVAL_SECS}" || {
      AGENT_TUI_FAILED=1
      sft_agent_tui_write_screen_capture >&2 || true
      return 1
    }
  local -a frame=("${SFT_TMUX_LAST_CAPTURE[@]}")

  if [[ -n "${vsc_copilot_pattern:-}" ]] && sft_tmux_matches_regex "${vsc_copilot_pattern}" "${frame[@]}"; then
    return "${SFT_AGENT_TUI_GATE_SKIP}"
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
