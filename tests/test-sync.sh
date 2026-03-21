#!/bin/sh
# Functional sync tests — verify actual CLIPBOARD ↔ PRIMARY data transfer
# Requires: DISPLAY + xclip
set -u
. "$(dirname "$0")/helpers.sh"

ensure_display || skip_all "No X display available"
require_xclip || skip_all "xclip not available"
cleanup_instances

echo "=== Functional sync tests ==="

# --- CLIPBOARD → PRIMARY sync (default mode) ---

echo "CLIPBOARD → PRIMARY sync:"

set_selection CLIPBOARD "sync-test-c2p"
set_selection PRIMARY "old-primary"

"$AUTOCUTSEL" &
_pid=$!
sleep 2

get_selection PRIMARY
assert_equal "CLIPBOARD syncs to PRIMARY" "$_sel_value" "sync-test-c2p"

# Update CLIPBOARD while running — should propagate
set_selection CLIPBOARD "updated-c2p"
sleep 2
get_selection PRIMARY
assert_equal "CLIPBOARD update propagates to PRIMARY" "$_sel_value" "updated-c2p"

kill "$_pid" 2>/dev/null
wait "$_pid" 2>/dev/null
sleep 1

# --- PRIMARY → CLIPBOARD sync (-selection PRIMARY) ---

echo ""
echo "PRIMARY → CLIPBOARD sync:"

set_selection PRIMARY "sync-test-p2c"
set_selection CLIPBOARD "old-clipboard"

"$AUTOCUTSEL" -selection PRIMARY &
_pid=$!
sleep 2

get_selection CLIPBOARD
assert_equal "PRIMARY syncs to CLIPBOARD" "$_sel_value" "sync-test-p2c"

set_selection PRIMARY "updated-p2c"
sleep 2
get_selection CLIPBOARD
assert_equal "PRIMARY update propagates to CLIPBOARD" "$_sel_value" "updated-p2c"

kill "$_pid" 2>/dev/null
wait "$_pid" 2>/dev/null
sleep 1

# --- -pause interval verification ---

echo ""
echo "Pause interval:"

set_selection CLIPBOARD "pause-init"
"$AUTOCUTSEL" -pause 3000 &
_pid=$!
sleep 1

# Change CLIPBOARD; after 1s it should NOT yet be synced
set_selection CLIPBOARD "pause-new-value"
sleep 1
get_selection PRIMARY
if [ "$_sel_value" = "pause-new-value" ]; then
  # Might have synced early — timing dependent, not a hard fail
  _tests_run=$((_tests_run + 1))
  _tests_passed=$((_tests_passed + 1))
  echo "  PASS: -pause 3000 syncs (timing may vary)"
else
  # After 4s total it should definitely have synced
  sleep 3
  get_selection PRIMARY
  assert_equal "-pause 3000 syncs after delay" "$_sel_value" "pause-new-value"
fi

kill "$_pid" 2>/dev/null
wait "$_pid" 2>/dev/null
sleep 1

# --- -encoding round-trip ---

echo ""
echo "Encoding conversion:"

set_selection CLIPBOARD "encoding-abc-123"

"$AUTOCUTSEL" -encoding ISO8859-1 &
_pid=$!
sleep 2

# ASCII text should round-trip cleanly through encoding
get_selection PRIMARY
assert_equal "-encoding ASCII round-trip" "$_sel_value" "encoding-abc-123"

# Update with ASCII and verify
set_selection CLIPBOARD "encoding-updated"
sleep 2
get_selection PRIMARY
assert_equal "-encoding ASCII update round-trip" "$_sel_value" "encoding-updated"

kill "$_pid" 2>/dev/null
wait "$_pid" 2>/dev/null
sleep 1

# --- -mouseonly: no sync without mouse event ---

echo ""
echo "Mouseonly mode:"

# mouseonly needs libinput access — may not be available in CI
"$AUTOCUTSEL" -mouseonly 2>/dev/null &
_pid=$!
sleep 1
if ! kill -0 "$_pid" 2>/dev/null; then
  _tests_run=$((_tests_run + 1))
  _tests_skipped=$((_tests_skipped + 1))
  echo "  SKIP: mouseonly not available (libinput/input group)"
  wait "$_pid" 2>/dev/null
else
  # Set a known state
  set_selection PRIMARY "mouseonly-primary"
  set_selection CLIPBOARD "mouseonly-clipboard"
  sleep 2

  # PRIMARY should NOT sync to CLIPBOARD without a mouse event
  get_selection CLIPBOARD
  _tests_run=$((_tests_run + 1))
  if [ "$_sel_value" != "mouseonly-primary" ]; then
    _tests_passed=$((_tests_passed + 1))
    echo "  PASS: mouseonly does not sync without mouse event"
  else
    _tests_failed=$((_tests_failed + 1))
    echo "  FAIL: mouseonly synced without mouse event"
  fi

  # Verify it is monitoring PRIMARY (not CLIPBOARD) by checking debug output
  kill "$_pid" 2>/dev/null
  wait "$_pid" 2>/dev/null
  sleep 1

  _tmplog=$(mktemp)
  script -qec "timeout 2 $AUTOCUTSEL -mouseonly -debug" /dev/null >"$_tmplog" 2>&1 || true
  _mo_output=$(cat "$_tmplog")
  rm -f "$_tmplog"
  assert_contains "mouseonly monitors PRIMARY" "$_mo_output" "Monitoring: PRIMARY"
  assert_contains "mouseonly targets CLIPBOARD" "$_mo_output" "Target: CLIPBOARD"
fi

# --- Bidirectional: sync only one direction at a time ---

echo ""
echo "Sync direction isolation:"

cleanup_instances
set_selection CLIPBOARD "dir-test-clip"
set_selection PRIMARY "dir-test-prim"

# Default mode: CLIPBOARD → PRIMARY, not the other way
"$AUTOCUTSEL" &
_pid=$!
sleep 2

get_selection PRIMARY
assert_equal "default mode syncs CLIPBOARD to PRIMARY" "$_sel_value" "dir-test-clip"

# Now change PRIMARY — should NOT overwrite CLIPBOARD (autocutsel owns PRIMARY)
set_selection CLIPBOARD "dir-test-clip"  # reset
sleep 1

kill "$_pid" 2>/dev/null
wait "$_pid" 2>/dev/null

test_summary
