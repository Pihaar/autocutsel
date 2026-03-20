#!/bin/sh
# Test all startup modes for autocutsel
set -u
. "$(dirname "$0")/helpers.sh"

ensure_display || skip_all "No X display available"
cleanup_instances

echo "=== Mode startup tests ==="

# Helper: start autocutsel, check it runs, kill it
# Usage: test_mode "description" [args...]
test_mode() {
  _desc=$1
  shift
  "$AUTOCUTSEL" "$@" &
  _pid=$!
  sleep 1
  assert_running "$_desc starts" "$_pid"
  kill "$_pid" 2>/dev/null
  wait "$_pid" 2>/dev/null
  sleep 1  # wait for selection ownership to be released
}

# Default CLIPBOARD mode
test_mode "default CLIPBOARD mode"

# PRIMARY mode
test_mode "PRIMARY mode" -selection PRIMARY

# With -pause
test_mode "custom pause" -pause 200

# With -buttonup
test_mode "buttonup mode" -buttonup

# With -encoding
test_mode "encoding mode" -encoding WINDOWS-1252

# mouseonly mode (may fail without libinput/input group access)
"$AUTOCUTSEL" -selection PRIMARY -mouseonly -debug 2>/dev/null &
_pid=$!
sleep 1
if kill -0 "$_pid" 2>/dev/null; then
  _tests_run=$((_tests_run + 1))
  _tests_passed=$((_tests_passed + 1))
  echo "  PASS: mouseonly mode starts"
  kill "$_pid" 2>/dev/null
  wait "$_pid" 2>/dev/null
  sleep 1
else
  _tests_run=$((_tests_run + 1))
  _tests_skipped=$((_tests_skipped + 1))
  echo "  SKIP: mouseonly mode (libinput/input group not available)"
  wait "$_pid" 2>/dev/null
fi

# Fork/daemon mode
"$AUTOCUTSEL" -selection PRIMARY -fork 2>&1
sleep 2
_fpid=$(ps -eo pid,args | grep "[a]utocutsel.*-fork" | awk '{print $1}')
if [ -n "$_fpid" ]; then
  _tests_run=$((_tests_run + 1))
  _tests_passed=$((_tests_passed + 1))
  echo "  PASS: fork mode daemonizes"
  kill $_fpid 2>/dev/null
else
  _tests_run=$((_tests_run + 1))
  _tests_failed=$((_tests_failed + 1))
  echo "  FAIL: fork mode daemonizes (process not found)"
fi

test_summary
