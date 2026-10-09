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

output=$("$ROOT/bin/omarchy-install-service-omacloud")
grep -qx 'omarchy-pkg-add:omacloud' "$TEST_LOG" ||
  fail "install adds omacloud" "$(cat "$TEST_LOG")"
for (( attempt=0; attempt<200; attempt++ )); do
  grep -q '^uwsm-app:' "$TEST_LOG" && break
  sleep 0.01
done
grep -qx 'uwsm-app:-- /usr/bin/omacloud-app' "$TEST_LOG" ||
  fail "install opens the Omacloud app" "$(cat "$TEST_LOG")"
[[ $output == *"join code"* ]] ||
  fail "install says how to set up" "$output"
pass "install adds omacloud, opens the app, and says how to set up"

: >"$TEST_LOG"
output=$("$ROOT/bin/omarchy-remove-service-omacloud")
grep -qx 'systemctl:--user disable --now omacloud' "$TEST_LOG" ||
  fail "remove disables the user service" "$(cat "$TEST_LOG")"
grep -qx 'omarchy-pkg-drop:omacloud' "$TEST_LOG" ||
  fail "remove drops the omacloud package" "$(cat "$TEST_LOG")"
[[ $output == *"Your files stay"* ]] ||
  fail "remove says the files stay" "$output"
pass "remove disables the service, drops the package and leaves the user's files where they are"

: >"$TEST_LOG"
cat >"$tmp_dir/bin/omarchy-pkg-drop" <<'SCRIPT'
#!/bin/bash
printf 'omarchy-pkg-drop:%s\n' "$*" >>"$TEST_LOG"
exit 1
SCRIPT
if output=$("$ROOT/bin/omarchy-remove-service-omacloud"); then
  fail "remove fails when the package can't be dropped" "$output"
fi
[[ $output != *"has been removed"* ]] ||
  fail "remove doesn't claim success when the drop fails" "$output"
grep -qx 'systemctl:--user enable --now omacloud' "$TEST_LOG" ||
  fail "remove turns the service back on when the drop fails" "$(cat "$TEST_LOG")"
pass "remove fails without claiming success, and turns sync back on, when the package can't be dropped"

menu="$ROOT/default/omarchy/omarchy-menu.jsonc"
grep -q '"install.service.omacloud".*omarchy-install-service-omacloud' "$menu" ||
  fail "Install > Service > Omacloud runs the installer"
grep -q '"remove.service.omacloud".*omarchy-remove-service-omacloud' "$menu" ||
  fail "Remove > Service > Omacloud runs the remover"
pass "the menu offers Omacloud under Install and Remove > Service"
