#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[POLICY-ONLY] enable=all-apps includes the Claude Desktop app profile" {
  local profile

  profile="$(safehouse_profile --enable=all-apps)"

  sft_assert_includes_source "$profile" "65-apps/claude-app.sb"
}

@test "[POLICY-ONLY] enable=all-apps grants Claude Desktop MachPortRendezvousServer lookup and register, including the team-ID-prefixed form" {
  local profile

  profile="$(safehouse_profile --enable=all-apps)"

  # Claude Desktop 1.x (Electron 37+/Chromium) registers the rendezvous port
  # under a signing-team-ID-prefixed name; older builds use the bare bundle-ID
  # name. Both forms must stay allowed or startup aborts with
  # "bootstrap_check_in ... Permission denied".
  sft_assert_contains "$profile" '(allow mach-lookup
    (global-name-regex #"^(Q6L2SF6YDW\.)?com\.anthropic\.claudefordesktop\.MachPortRendezvousServer\.")
)'
  sft_assert_contains "$profile" '(allow mach-register
    (global-name-regex #"^(Q6L2SF6YDW\.)?com\.anthropic\.claudefordesktop\.MachPortRendezvousServer\.")
)'
}
