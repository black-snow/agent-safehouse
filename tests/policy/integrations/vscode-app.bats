#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[POLICY-ONLY] enable=all-apps keeps VS Code launchable from the system Applications root" {
  local profile

  profile="$(safehouse_profile --enable=all-apps)"

  sft_assert_omits_source "$profile" "55-integrations-optional/vscode.sb"
  sft_assert_includes_source "$profile" "65-apps/vscode-app.sb"
  sft_assert_contains "$profile" '(literal "/Applications")'
}

@test "[POLICY-ONLY] enable=vscode includes the explicit VS Code integration and app profile" {
  local profile

  profile="$(safehouse_profile --enable=vscode)"

  sft_assert_includes_source "$profile" "55-integrations-optional/vscode.sb"
  sft_assert_includes_source "$profile" "65-apps/vscode-app.sb"
  sft_assert_contains "$profile" '(home-subpath "/.cache/claude/vscode-editor-stable")'
  sft_assert_contains "$profile" '(home-subpath "/.cache/claude/vscode-editor-insiders")'
}

@test "[POLICY-ONLY] enable=vscode grants the listen side of the CLI IPC socket" {
  local profile

  profile="$(safehouse_profile --enable=vscode)"

  # VS Code launched inside the sandbox binds/accepts on its own
  # vscode-ipc-<uuid>.sock; this is safe because it hands no capability out of
  # the sandbox.
  sft_assert_contains "$profile" '(allow network-bind network-inbound'
  sft_assert_contains "$profile" '(local unix-socket'
  sft_assert_contains "$profile" '(path-regex #"^(/private)?/var/folders/[^/]+/[^/]+/T/vscode-ipc-[0-9A-Fa-f-]+\.sock$")'
}

@test "[POLICY-ONLY] enable=vscode explicitly denies the connect side of the CLI IPC socket" {
  local profile

  profile="$(safehouse_profile --enable=vscode)"

  # Connecting out to this socket can drive an out-of-sandbox editor
  # (openExternal / directory-open with workspace-trust behavior), so outbound
  # connect is denied explicitly rather than left to the default deny.
  sft_assert_contains "$profile" '(deny network-outbound'
  sft_assert_contains "$profile" '(path-regex #"^(/private)?/var/folders/[^/]+/[^/]+/T/vscode-ipc-[0-9A-Fa-f-]+\.sock$")'
}

@test "[POLICY-ONLY] enable=vscode denies both directions of the git IPC socket" {
  local profile

  profile="$(safehouse_profile --enable=vscode)"

  # The git IPC socket (VSCODE_GIT_IPC_HANDLE) is a credential conduit whose
  # path does not identify the owning editor, so it cannot be scoped to a trust
  # domain. Both connect and listen are denied.
  sft_assert_contains "$profile" '(deny network-outbound
    (remote unix-socket
        (path-regex #"^(/private)?/var/folders/[^/]+/[^/]+/T/vscode-git-[0-9a-f]+\.sock$")))'
  sft_assert_contains "$profile" '(deny network-bind network-inbound
    (local unix-socket
        (path-regex #"^(/private)?/var/folders/[^/]+/[^/]+/T/vscode-git-[0-9a-f]+\.sock$")))'
}

@test "[POLICY-ONLY] enable=vscode allows both directions of the Safehouse-managed editor's single-instance socket" {
  local profile

  profile="$(safehouse_profile --enable=vscode)"

  # The Electron single-instance socket under the Safehouse-owned isolated
  # editor profile is first-party: bind lets the cold-start editor become a
  # primary instance, connect lets a repeat cold-start hand off to it instead
  # of spawning another full instance.
  sft_assert_contains "$profile" '(allow network-bind network-inbound
    (local unix-socket
        (path-regex (string-append "^" HOME_DIR "/\\.cache/claude/vscode-editor-(stable|insiders)/user-data/[0-9.]+-main\\.sock$"))))'
  sft_assert_contains "$profile" '(allow network-outbound
    (remote unix-socket
        (path-regex (string-append "^" HOME_DIR "/\\.cache/claude/vscode-editor-(stable|insiders)/user-data/[0-9.]+-main\\.sock$"))))'
}

@test "[POLICY-ONLY] enable=vscode explicitly denies connecting to the user's real VS Code single-instance socket" {
  local profile

  profile="$(safehouse_profile --enable=vscode)"

  # Connecting to the main socket under the user's real data dir hands
  # arbitrary CLI args (including --open-url deep links) to a potentially
  # unsandboxed primary instance across the trust boundary.
  sft_assert_contains "$profile" '(deny network-outbound
    (remote unix-socket
        (path-regex (string-append "^" HOME_DIR "/Library/Application Support/Code( - Insiders)?/[0-9.]+-main\\.sock$"))))'
}

@test "[EXECUTION] VS Code CLI can report its version when launched via bash if the CLI is installed" {
  local code_bin

  code_bin="/usr/local/bin/code"
  [ -x "$code_bin" ] || skip "VS Code CLI is not installed at /usr/local/bin/code"

  HOME="$SAFEHOUSE_HOST_HOME" "$code_bin" --version >/dev/null 2>&1 || skip "VS Code CLI precheck failed outside sandbox"

  run safehouse_ok_env HOME="$SAFEHOUSE_HOST_HOME" -- --enable=all-apps -- /bin/bash "$code_bin" --version
  [ "$status" -eq 0 ]
}
