#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[POLICY-ONLY] enable=all-apps includes the Codex Desktop app profile and grants ~/.codex without the CLI profile" {
  local profile

  profile="$(safehouse_profile --enable=all-apps)"

  sft_assert_includes_source "$profile" "65-apps/codex-app.sb"
  # ~/.codex (session sqlite DB etc.) is opened by the desktop app at
  # startup; the app profile grants it directly because app selection
  # intentionally does not pull in 60-agents/codex.sb.
  sft_assert_omits_source "$profile" "60-agents/codex.sb"
  sft_assert_contains "$profile" '(home-subpath "/.codex")'
}

@test "[POLICY-ONLY] enable=all-apps grants both Codex Desktop bundle names" {
  local profile

  profile="$(safehouse_profile --enable=all-apps)"

  # Newer builds install as ChatGPT.app (bundle ID still com.openai.codex);
  # older builds installed as Codex.app.
  sft_assert_contains "$profile" '(subpath "/Applications/Codex.app")'
  sft_assert_contains "$profile" '(subpath "/Applications/ChatGPT.app")'
}

@test "[POLICY-ONLY] enable=all-apps grants both Codex Desktop cache directories" {
  local profile

  profile="$(safehouse_profile --enable=all-apps)"

  # The app writes disk caches under both the app-name and bundle-ID dirs.
  sft_assert_contains "$profile" '(home-subpath "/Library/Caches/Codex")'
  sft_assert_contains "$profile" '(home-subpath "/Library/Caches/com.openai.codex")'
}

@test "[POLICY-ONLY] enable=all-apps allows both directions of the Codex ProcessSingleton socket" {
  local profile

  profile="$(safehouse_profile --enable=all-apps)"

  # Chromium's ProcessSingleton socket lives in an app-branded darwin temp
  # dir. Without bind, launch aborts with "Failed to create a
  # ProcessSingleton for your profile directory"; without connect, a second
  # launch aborts the same way instead of handing off.
  sft_assert_contains "$profile" '(allow network-bind network-inbound
    (local unix-socket
        (path-regex #"^(/private)?/var/folders/[^/]+/[^/]+/T/com\.openai\.codex\.[^/]+/SingletonSocket$"))
)'
  sft_assert_contains "$profile" '(allow network-outbound
    (remote unix-socket
        (path-regex #"^(/private)?/var/folders/[^/]+/[^/]+/T/com\.openai\.codex\.[^/]+/SingletonSocket$"))
)'
}

@test "[POLICY-ONLY] enable=all-apps grants the Codex mojo apps channel mach names" {
  local profile

  profile="$(safehouse_profile --enable=all-apps)"

  sft_assert_contains "$profile" '(global-name-regex #"^com\.openai\.codex\.apps\.")'
}
