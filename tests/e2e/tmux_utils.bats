#!/usr/bin/env bats
# bats file_tags=suite:e2e

load ../test_helper.bash
load tmux_utils.bash
load agent_tui_harness.bash

@test "[E2E-TUI] tmux literal wait matches question marks literally" {
  local literal_prompt='What is the capital of England? [literal] (chars) + .*'

  sft_tmux_start_session cat
  sft_tmux_type_and_wait_visible "${literal_prompt}" 2 0.1

  run sft_tmux_capture
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"${literal_prompt}"* ]]
}

@test "[E2E-TUI] tmux respawn preserves requested workdir" {
  local session_name workdir

  session_name="$(sft_tmux_unique_name tmux-cwd)"
  workdir="${SAFEHOUSE_WORKSPACE}/tmux-respawn-workdir"
  mkdir -p "${workdir}"
  workdir="$(cd -- "${workdir}" && pwd -P)"

  sft_tmux_create_session_named "${session_name}" "${workdir}"
  sft_tmux_run /bin/sh -c 'pwd; sleep 3'

  sft_tmux_wait_until "${workdir}" 2 0.1
}

@test "[E2E-TUI] prompt visibility regex handles normalized agent echoes" {
  local fake_agent_code=""

  sft_require_cmd_or_skip "python3"

  fake_agent_code=$'import sys, termios, tty\nfd = sys.stdin.fileno()\nold = termios.tcgetattr(fd)\nbuf = []\nprint("Ready", flush=True)\ntry:\n    tty.setcbreak(fd)\n    while True:\n        ch = sys.stdin.read(1)\n        if not ch:\n            break\n        if ch in "\\r\\n":\n            print("* " + "".join(buf).replace("?", ""), flush=True)\n            print("London", flush=True)\n            break\n        buf.append(ch)\n        print("* " + "".join(buf).replace("?", ""), flush=True)\n        sys.stdout.flush()\nfinally:\n    termios.tcsetattr(fd, termios.TCSADRAIN, old)\n'

  # NOTE: Intentionally contains a '?', which some compositors (like Codex) drop.
  AGENT_TUI_PROMPT_TEXT="What is the capital of England? Reply with only the city name."
  AGENT_TUI_PROMPT_VISIBLE_MODE="regex"
  AGENT_TUI_PROMPT_VISIBLE_REGEX='What is the capital of England\?? Reply with only the city name\.'
  AGENT_TUI_SUBMIT_DELAY_SECS=0

  sft_tmux_start_session python3 -u -c "${fake_agent_code}"
  sft_tmux_wait_until "Ready" 2 0.1
  sft_tmux_assert_roundtrip
}

@test "[E2E-TUI] waits match prompt and response on alternate screen" {
  local fake_agent_code=""

  sft_require_cmd_or_skip "python3"

  fake_agent_code=$'import sys, termios, tty\nfd = sys.stdin.fileno()\nold = termios.tcgetattr(fd)\nbuf = []\nprint("Ready", flush=True)\nprint("Normal screen filler " * 12, flush=True)\ntry:\n    tty.setcbreak(fd)\n    while True:\n        ch = sys.stdin.read(1)\n        if not ch:\n            break\n        if ch in "\\r\\n":\n            sys.stdout.write("\\x1b[?1049h\\x1b[2J\\x1b[H")\n            print("* " + "".join(buf), flush=True)\n            print("London", flush=True)\n            break\n        buf.append(ch)\n        sys.stdout.write("\\x1b[?1049h\\x1b[2J\\x1b[H")\n        print("* " + "".join(buf), flush=True)\n        sys.stdout.flush()\nfinally:\n    termios.tcsetattr(fd, termios.TCSADRAIN, old)\n'

  AGENT_TUI_PROMPT_VISIBLE_MODE="regex"
  AGENT_TUI_PROMPT_VISIBLE_REGEX='Name the capital city of England\. Reply with only the city name\.'
  AGENT_TUI_SUBMIT_DELAY_SECS=0

  sft_tmux_start_session python3 -u -c "${fake_agent_code}"
  sft_tmux_wait_until "Ready" 2 0.1
  sft_tmux_assert_roundtrip
}

@test "[E2E-TUI] prompt visibility can be skipped for submit-only UIs" {
  local fake_agent_code=""

  sft_require_cmd_or_skip "python3"

  fake_agent_code=$'import sys, termios, tty\nfd = sys.stdin.fileno()\nold = termios.tcgetattr(fd)\nbuf = []\nprint("Ready", flush=True)\nprint("  Type your message or @path/to/file", flush=True)\ntry:\n    tty.setcbreak(fd)\n    while True:\n        ch = sys.stdin.read(1)\n        if not ch:\n            break\n        if ch in "\\r\\n":\n            print("London", flush=True)\n            break\n        buf.append(ch)\n        print("  Type your message or @path/to/file", flush=True)\n        sys.stdout.flush()\nfinally:\n    termios.tcsetattr(fd, termios.TCSADRAIN, old)\n'

  AGENT_TUI_PROMPT_VISIBLE_MODE="none"
  AGENT_TUI_SUBMIT_DELAY_SECS=0

  sft_tmux_start_session python3 -u -c "${fake_agent_code}"
  sft_tmux_wait_until "Ready" 2 0.1
  sft_tmux_assert_roundtrip
}

@test "[E2E-TUI] gate dismissal waits for the gate to clear" {
  local fake_agent_code=""
  local gate_pattern='Confirm folder trust'
  local started_at=0
  local elapsed=0

  sft_require_cmd_or_skip "python3"

  # A gate that keeps painting for a while after it accepts the keypress, the
  # way a loaded agent TUI does.
  fake_agent_code=$'import sys, termios, tty, time\nfd = sys.stdin.fileno()\nold = termios.tcgetattr(fd)\nprint("Confirm folder trust", flush=True)\ntry:\n    tty.setcbreak(fd)\n    while True:\n        ch = sys.stdin.read(1)\n        if not ch:\n            break\n        if ch in "\\r\\n":\n            time.sleep(1.5)\n            sys.stdout.write("\\x1b[2J\\x1b[H")\n            print("Ready", flush=True)\n            break\nfinally:\n    termios.tcsetattr(fd, termios.TCSADRAIN, old)\ntime.sleep(5)\n'

  sft_tmux_start_session python3 -u -c "${fake_agent_code}"
  sft_tmux_wait_until "${gate_pattern}" 2 0.1

  started_at="$(date +%s)"
  sft_agent_tui_dismiss_gate "${gate_pattern}" Enter
  elapsed=$(( $(date +%s) - started_at ))

  # The helper blocked until the gate stopped matching. A caller that re-checked
  # the screen immediately after sending the key would still have seen the gate
  # and answered it again, spending its pass budget on a single gate.
  (( elapsed >= 1 ))
  run sft_tmux_matches_regex "${gate_pattern}"
  [ "${status}" -ne 0 ]
}

@test "[E2E-TUI] pre-prompt delay and slow typing tolerate late input readiness" {
  local fake_agent_code=""

  sft_require_cmd_or_skip "python3"

  fake_agent_code=$'import sys, termios, tty, time\nfd = sys.stdin.fileno()\nold = termios.tcgetattr(fd)\nbuf = []\nready_at = time.time() + 0.5\nprint("Ready", flush=True)\nprint("  Type your message or @path/to/file", flush=True)\ntry:\n    tty.setcbreak(fd)\n    while True:\n        ch = sys.stdin.read(1)\n        if not ch:\n            break\n        if time.time() < ready_at:\n            continue\n        if ch in "\\r\\n":\n            print("* " + "".join(buf), flush=True)\n            print("London", flush=True)\n            break\n        buf.append(ch)\n        print("* " + "".join(buf), flush=True)\n        sys.stdout.flush()\nfinally:\n    termios.tcsetattr(fd, termios.TCSADRAIN, old)\n'

  AGENT_TUI_PRE_PROMPT_DELAY_SECS=0.6
  AGENT_TUI_PROMPT_SEND_MODE="slow"
  AGENT_TUI_PROMPT_CHAR_DELAY_SECS=0
  AGENT_TUI_PROMPT_VISIBLE_MODE="regex"
  AGENT_TUI_PROMPT_VISIBLE_REGEX='Name the capital city of England\. Reply with only the city name\.'
  AGENT_TUI_SUBMIT_DELAY_SECS=0

  sft_tmux_start_session python3 -u -c "${fake_agent_code}"
  sft_tmux_wait_until "Ready" 2 0.1
  sft_tmux_assert_roundtrip
}

@test "[E2E-TUI] a frozen capture keeps judging the frame it was taken from" {
  local fake_agent_code=""
  local -a frame=()

  sft_require_cmd_or_skip "python3"

  # Paints gate 1, waits for a key, then paints gate 2
  fake_agent_code=$'import sys, termios, tty, time\nfd = sys.stdin.fileno()\nold = termios.tcgetattr(fd)\nprint("GATE ONE", flush=True)\ntry:\n    tty.setcbreak(fd)\n    sys.stdin.read(1)\n    sys.stdout.write("\\x1b[2J\\x1b[H")\n    print("GATE TWO", flush=True)\nfinally:\n    termios.tcsetattr(fd, termios.TCSADRAIN, old)\ntime.sleep(5)\n'

  # Capture frame of gate 1
  sft_tmux_start_session python3 -u -c "${fake_agent_code}"
  sft_tmux_wait_until_regex 'GATE ONE' 2 0.1
  frame=("${SFT_TMUX_LAST_CAPTURE[@]}")

  # Wait until live screen shows gate 2
  sft_tmux_send_keys Enter
  sft_tmux_wait_until_regex 'GATE TWO' 2 0.1

  # Ensure sft_tmux_matches_regex uses a frame that is provided
  run sft_tmux_matches_regex 'GATE ONE' "${frame[@]}"
  [ "${status}" -eq 0 ]
  run sft_tmux_matches_regex 'GATE TWO' "${frame[@]}"
  [ "${status}" -ne 0 ]

  # Ensure sft_tmux_matches_regex uses the live screen if no frame provided
  run sft_tmux_matches_regex 'GATE ONE'
  [ "${status}" -ne 0 ]
  run sft_tmux_matches_regex 'GATE TWO'
  [ "${status}" -eq 0 ]
}

@test "[E2E-TUI] a failure dump reports the judged frame and also the live one" {
  local fake_agent_code=""
  local -a frame=()

  sft_require_cmd_or_skip "python3"

  # Paints gate 1, waits for a key, then paints gate 2
  fake_agent_code=$'import sys, termios, tty, time\nfd = sys.stdin.fileno()\nold = termios.tcgetattr(fd)\nprint("GATE ONE", flush=True)\ntry:\n    tty.setcbreak(fd)\n    sys.stdin.read(1)\n    sys.stdout.write("\\x1b[2J\\x1b[H")\n    print("GATE TWO", flush=True)\nfinally:\n    termios.tcsetattr(fd, termios.TCSADRAIN, old)\ntime.sleep(5)\n'

  # Capture frame of gate 1
  sft_tmux_start_session python3 -u -c "${fake_agent_code}"
  sft_tmux_wait_until_regex 'GATE ONE' 2 0.1
  frame=("${SFT_TMUX_LAST_CAPTURE[@]}")

  # Wait until live screen shows gate 2
  sft_tmux_send_keys Enter
  sft_tmux_wait_until_regex 'GATE TWO' 2 0.1

  run sft_agent_tui_write_screen_capture "${frame[@]}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"decision frame"* ]]
  [[ "${output}" == *"GATE ONE"* ]]
  [[ "${output}" == *"current frame ("*"buffer"*")"* ]]
  [[ "${output}" == *"GATE TWO"* ]]

  # A screen that has not moved gets one section, not two.
  run sft_agent_tui_write_screen_capture "${SFT_TMUX_LAST_CAPTURE[@]}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"decision frame"* ]]
  [[ "${output}" != *"current frame"* ]]
}

@test "[E2E-TUI] a failure dump reports a state that lands just after the timeout" {
  local fake_agent_code=""
  local -a frame=()

  sft_require_cmd_or_skip "python3"

  # A screen that reaches the awaited state about a second late.
  fake_agent_code=$'import sys, time\nprint("WAITING", flush=True)\ntime.sleep(1)\nsys.stdout.write("\\x1b[2J\\x1b[H")\nprint("ARRIVED", flush=True)\ntime.sleep(5)\n'

  sft_tmux_start_session python3 -u -c "${fake_agent_code}"
  sft_tmux_wait_until_regex 'WAITING' 2 0.1
  frame=("${SFT_TMUX_LAST_CAPTURE[@]}")

  # A timeout too short to see what is about to arrive.
  run sft_tmux_wait_until_regex 'ARRIVED' 0 0.1
  [ "${status}" -ne 0 ]

  AGENT_TUI_FAILURE_SETTLE_SECS=2.0
  run sft_agent_tui_write_screen_capture "${frame[@]}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"WAITING"* ]]
  [[ "${output}" == *"settled frame, +2.0s ("*"buffer"*")"* ]]
  [[ "${output}" == *"ARRIVED"* ]]

  # Turning the settle delay off drops the extra section.
  AGENT_TUI_FAILURE_SETTLE_SECS=0
  run sft_agent_tui_write_screen_capture "${frame[@]}"
  [ "${status}" -eq 0 ]
  [[ "${output}" != *"settled frame"* ]]
}
