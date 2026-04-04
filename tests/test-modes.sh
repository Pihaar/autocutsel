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
_mouseonly_available=0
"$AUTOCUTSEL" -selection PRIMARY -mouseonly -debug 2>/dev/null &
_pid=$!
sleep 1
if kill -0 "$_pid" 2>/dev/null; then
  _mouseonly_available=1
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

# --- Fork/daemon mode (detailed checks) ---

echo ""
echo "Fork daemonization:"

"$AUTOCUTSEL" -selection PRIMARY -fork 2>&1
_fork_exit=$?

_tests_run=$((_tests_run + 1))
if [ "$_fork_exit" -eq 0 ]; then
  _tests_passed=$((_tests_passed + 1))
  echo "  PASS: fork parent exits with code 0"
else
  _tests_failed=$((_tests_failed + 1))
  echo "  FAIL: fork parent exits with code $_fork_exit (expected 0)"
fi

sleep 2
_fpid=$(pgrep -x autocutsel 2>/dev/null | head -1)
if [ -n "$_fpid" ]; then
  _tests_run=$((_tests_run + 1))
  _tests_passed=$((_tests_passed + 1))
  echo "  PASS: fork child process running"

  # Child should not be a zombie and should have init or systemd as parent
  if command -v ps >/dev/null 2>&1; then
    _ppid=$(ps -o ppid= -p "$_fpid" 2>/dev/null | tr -d ' ')
    _tests_run=$((_tests_run + 1))
    if [ -n "$_ppid" ] && [ "$_ppid" != "$$" ]; then
      _tests_passed=$((_tests_passed + 1))
      echo "  PASS: fork child re-parented (ppid=$_ppid, not test shell $$)"
    else
      _tests_failed=$((_tests_failed + 1))
      echo "  FAIL: fork child not re-parented (ppid=$_ppid)"
    fi
  else
    _tests_run=$((_tests_run + 1))
    _tests_skipped=$((_tests_skipped + 1))
    echo "  SKIP: ps not available for re-parent check"
  fi

  kill $_fpid 2>/dev/null
  sleep 1  # let process exit
else
  _tests_run=$((_tests_run + 1))
  _tests_failed=$((_tests_failed + 1))
  echo "  FAIL: fork mode daemonizes (process not found)"
fi

sleep 1

# --- Combination tests ---

echo ""
echo "Mode combinations:"

# mouseonly + fork (only if mouseonly is available)
if [ "$_mouseonly_available" -eq 1 ]; then
  "$AUTOCUTSEL" -mouseonly -fork 2>&1
  _fork_exit=$?
  sleep 2
  _fpid=$(pgrep -x autocutsel 2>/dev/null | head -1)

  _tests_run=$((_tests_run + 1))
  if [ -n "$_fpid" ] && [ "$_fork_exit" -eq 0 ]; then
    _tests_passed=$((_tests_passed + 1))
    echo "  PASS: mouseonly + fork starts"
    kill $_fpid 2>/dev/null
    sleep 1
  else
    _tests_failed=$((_tests_failed + 1))
    echo "  FAIL: mouseonly + fork (exit=$_fork_exit, pid=$_fpid)"
  fi
  sleep 1

  # mouseonly + selection PRIMARY
  "$AUTOCUTSEL" -mouseonly -selection PRIMARY 2>/dev/null &
  _pid=$!
  sleep 1
  assert_running "mouseonly + selection PRIMARY starts" "$_pid"
  kill "$_pid" 2>/dev/null
  wait "$_pid" 2>/dev/null
  sleep 1
else
  _tests_run=$((_tests_run + 2))
  _tests_skipped=$((_tests_skipped + 2))
  echo "  SKIP: mouseonly + fork (mouseonly not available)"
  echo "  SKIP: mouseonly + selection PRIMARY (mouseonly not available)"
fi

# buttonup + encoding
test_mode "buttonup + encoding" -buttonup -encoding ISO8859-1

# pause + buttonup
test_mode "pause + buttonup" -pause 200 -buttonup

test_summary
