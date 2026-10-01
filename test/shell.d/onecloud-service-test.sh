#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin"
export TEST_LOG="$tmp_dir/log"

# Package management and the app launch are stubbed; the scripts' job is what
# they ask for.
for stub in omarchy-pkg-add omarchy-pkg-drop uwsm-app systemctl; do
  cat >"$tmp_dir/bin/$stub" <<SCRIPT
#!/bin/bash
printf '%s:%s\n' "$stub" "\$*" >>"\$TEST_LOG"
SCRIPT
  chmod +x "$tmp_dir/bin/$stub"
done
export PATH="$tmp_dir/bin:$PATH"

output=$("$ROOT/bin/omarchy-install-service-onecloud")
grep -qx 'omarchy-pkg-add:onecloud' "$TEST_LOG" ||
  fail "install adds onecloud" "$(cat "$TEST_LOG")"
for (( attempt=0; attempt<200; attempt++ )); do
  grep -q '^uwsm-app:' "$TEST_LOG" && break
  sleep 0.01
done
grep -qx 'uwsm-app:-- /usr/bin/onecloud-app' "$TEST_LOG" ||
  fail "install opens the OneCloud app" "$(cat "$TEST_LOG")"
[[ $output == *"join code"* ]] ||
  fail "install says how to set up" "$output"
pass "install adds onecloud, opens the app, and says how to set up"

: >"$TEST_LOG"
output=$("$ROOT/bin/omarchy-remove-service-onecloud")
grep -qx 'omarchy-pkg-drop:onecloud' "$TEST_LOG" ||
  fail "remove drops the onecloud package" "$(cat "$TEST_LOG")"
[[ $output == *"Your files stay"* ]] ||
  fail "remove says the files stay" "$output"
pass "remove drops the package and leaves the user's files where they are"

menu="$ROOT/default/omarchy/omarchy-menu.jsonc"
grep -q '"install.service.onecloud".*omarchy-install-service-onecloud' "$menu" ||
  fail "Install > Service > OneCloud runs the installer"
grep -q '"remove.service.onecloud".*omarchy-remove-service-onecloud' "$menu" ||
  fail "Remove > Service > OneCloud runs the remover"
pass "the menu offers OneCloud under Install and Remove > Service"
