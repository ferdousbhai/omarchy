#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin"
export TEST_LOG="$tmp_dir/log"

# Package removal and systemd are stubbed; the script's job is what it asks
# for, and in what order. The drop fails when DROP_FAILS is set, and
# systemctl answers is-active from SERVICE_ACTIVE.
cat >"$tmp_dir/bin/omarchy-pkg-drop" <<'SCRIPT'
#!/bin/bash
printf 'omarchy-pkg-drop:%s\n' "$*" >>"$TEST_LOG"
[[ -z ${DROP_FAILS:-} ]]
SCRIPT
cat >"$tmp_dir/bin/systemctl" <<'SCRIPT'
#!/bin/bash
printf 'systemctl:%s\n' "$*" >>"$TEST_LOG"
for arg; do
  case $arg in
    is-active) [[ -n ${SERVICE_ACTIVE:-} ]]; exit ;;
    stop) [[ -z ${STOP_FAILS:-} ]]; exit ;;
  esac
done
SCRIPT
chmod +x "$tmp_dir/bin/omarchy-pkg-drop" "$tmp_dir/bin/systemctl"
export PATH="$tmp_dir/bin:$PATH"

# Runs the remover; leaves its output in $output and exit status in $status.
remove() {
  : >"$TEST_LOG"
  status=0
  output=$("$ROOT/bin/omarchy-remove-service-omacloud" 2>&1) || status=$?
}

logged() {
  grep -qx "$1" "$TEST_LOG"
}

line_of() {
  grep -nx "$1" "$TEST_LOG" | head -1 | cut -d: -f1
}

# The remover never reads whether sync is enabled: disable runs either way,
# so enabled or not only matters through whether sync is running.

# Running sync (enabled, or started by hand while disabled): dropped first,
# then stopped and its links cleared.
SERVICE_ACTIVE=1 remove
((status == 0)) || fail "remove succeeds when the package drops" "$output"
logged 'omarchy-pkg-drop:omacloud' ||
  fail "remove drops the omacloud package" "$(cat "$TEST_LOG")"
logged 'systemctl:--user stop omacloud' ||
  fail "remove stops running sync" "$(cat "$TEST_LOG")"
logged 'systemctl:--user disable omacloud' ||
  fail "remove clears enable links left in ~/.config" "$(cat "$TEST_LOG")"
(($(line_of 'omarchy-pkg-drop:omacloud') < $(line_of 'systemctl:--user stop omacloud'))) ||
  fail "remove drops the package before touching the service" "$(cat "$TEST_LOG")"
[[ $output == *"Your files stay"* ]] ||
  fail "remove says the files stay" "$output"
pass "remove drops the package, then stops sync and clears its links, and leaves the user's files where they are"

# Enabled but not running: nothing to stop, links still cleared.
SERVICE_ACTIVE="" remove
((status == 0)) || fail "remove succeeds when sync isn't running" "$output"
! logged 'systemctl:--user stop omacloud' ||
  fail "remove doesn't stop sync that isn't running" "$(cat "$TEST_LOG")"
logged 'systemctl:--user disable omacloud' ||
  fail "remove clears enable links when sync isn't running" "$(cat "$TEST_LOG")"
pass "remove clears the links of sync that's enabled but not running"

# A stop that fails after the drop is reported with the remedy, and the
# links are still cleared so sync doesn't come back at the next login.
SERVICE_ACTIVE=1 STOP_FAILS=1 remove
((status != 0)) || fail "remove fails when running sync can't be stopped" "$output"
[[ $output != *"has been removed"* ]] ||
  fail "remove doesn't claim success when sync can't be stopped" "$output"
[[ $output == *"systemctl --user stop omacloud"* ]] ||
  fail "remove tells the user how to stop sync when its stop fails" "$output"
logged 'systemctl:--user disable omacloud' ||
  fail "remove clears enable links even when the stop fails" "$(cat "$TEST_LOG")"
pass "remove fails with the remedy, and still clears sync's links, when running sync can't be stopped"

# A failed drop leaves the service alone in every state, so there's nothing
# to restore.
for active in 1 ""; do
  SERVICE_ACTIVE=$active DROP_FAILS=1 remove
  ((status != 0)) || fail "remove fails when the package can't be dropped" "$output"
  [[ $output != *"has been removed"* ]] ||
    fail "remove doesn't claim success when the drop fails" "$output"
  ! grep -q '^systemctl:' "$TEST_LOG" ||
    fail "remove leaves the service alone when the drop fails (active=${active:-no})" "$(cat "$TEST_LOG")"
done
pass "remove fails without claiming success, and without touching sync, when the package can't be dropped"

menu="$ROOT/default/omarchy/omarchy-menu.jsonc"
grep -q '"install.service.omacloud".*omarchy-install-and-launch Omacloud omacloud com.ferdousbhai.Omacloud' "$menu" ||
  fail "Install > Service > Omacloud installs the package and opens the app"
grep -q '"remove.service.omacloud".*omarchy-remove-service-omacloud' "$menu" ||
  fail "Remove > Service > Omacloud runs the remover"
pass "the menu offers Omacloud under Install and Remove > Service"
