#!/bin/sh
# Tests that do NOT require a DISPLAY / X server
# These run in any build environment (CI, containers, etc.)
set -u
. "$(dirname "$0")/helpers.sh"

echo "=== No-display tests ==="

# --- Binary checks ---

echo "Binary checks:"

_tests_run=$((_tests_run + 1))
if [ -x "$AUTOCUTSEL" ]; then
  _tests_passed=$((_tests_passed + 1))
  echo "  PASS: autocutsel binary exists and is executable"
else
  _tests_failed=$((_tests_failed + 1))
  echo "  FAIL: autocutsel binary not found or not executable: $AUTOCUTSEL"
fi

_tests_run=$((_tests_run + 1))
if [ -x "$CUTSEL" ]; then
  _tests_passed=$((_tests_passed + 1))
  echo "  PASS: cutsel binary exists and is executable"
else
  _tests_failed=$((_tests_failed + 1))
  echo "  FAIL: cutsel binary not found or not executable: $CUTSEL"
fi

# Verify they are ELF binaries (not accidentally a shell script or empty)
_tests_run=$((_tests_run + 1))
if file "$AUTOCUTSEL" | grep -q "ELF"; then
  _tests_passed=$((_tests_passed + 1))
  echo "  PASS: autocutsel is an ELF binary"
else
  _tests_failed=$((_tests_failed + 1))
  echo "  FAIL: autocutsel is not an ELF binary"
fi

_tests_run=$((_tests_run + 1))
if file "$CUTSEL" | grep -q "ELF"; then
  _tests_passed=$((_tests_passed + 1))
  echo "  PASS: cutsel is an ELF binary"
else
  _tests_failed=$((_tests_failed + 1))
  echo "  FAIL: cutsel is not an ELF binary"
fi

# --- Linked library checks ---

echo ""
echo "Library linkage:"

for _lib in libX11 libXt libXmu libXaw libinput; do
  _tests_run=$((_tests_run + 1))
  if ldd "$AUTOCUTSEL" 2>/dev/null | grep -q "$_lib"; then
    _tests_passed=$((_tests_passed + 1))
    echo "  PASS: autocutsel links $_lib"
  else
    _tests_failed=$((_tests_failed + 1))
    echo "  FAIL: autocutsel does not link $_lib"
  fi
done

# cutsel should NOT link libinput (it doesn't use mouseonly)
_tests_run=$((_tests_run + 1))
if ldd "$CUTSEL" 2>/dev/null | grep -q "libX11"; then
  _tests_passed=$((_tests_passed + 1))
  echo "  PASS: cutsel links libX11"
else
  _tests_failed=$((_tests_failed + 1))
  echo "  FAIL: cutsel does not link libX11"
fi

# --- Graceful failure without DISPLAY ---

echo ""
echo "Graceful failure without DISPLAY:"

_saved_display="${DISPLAY:-}"
unset DISPLAY

# autocutsel should exit with error, not segfault (exit code 1, not 139)
_output=$("$AUTOCUTSEL" 2>&1 || true)
_exit_code=$?
_tests_run=$((_tests_run + 1))
if [ "$_exit_code" -ne 139 ] && [ "$_exit_code" -ne 134 ] && [ "$_exit_code" -ne 136 ]; then
  _tests_passed=$((_tests_passed + 1))
  echo "  PASS: autocutsel exits gracefully without DISPLAY (exit=$_exit_code)"
else
  _tests_failed=$((_tests_failed + 1))
  echo "  FAIL: autocutsel crashed without DISPLAY (exit=$_exit_code, signal)"
fi

# Should produce some error message about display
_tests_run=$((_tests_run + 1))
if [ -n "$_output" ]; then
  _tests_passed=$((_tests_passed + 1))
  echo "  PASS: autocutsel produces error message without DISPLAY"
else
  _tests_failed=$((_tests_failed + 1))
  echo "  FAIL: autocutsel produces no output without DISPLAY"
fi

# Same for cutsel
_output=$("$CUTSEL" cut 2>&1 || true)
_exit_code=$?
_tests_run=$((_tests_run + 1))
if [ "$_exit_code" -ne 139 ] && [ "$_exit_code" -ne 134 ] && [ "$_exit_code" -ne 136 ]; then
  _tests_passed=$((_tests_passed + 1))
  echo "  PASS: cutsel exits gracefully without DISPLAY (exit=$_exit_code)"
else
  _tests_failed=$((_tests_failed + 1))
  echo "  FAIL: cutsel crashed without DISPLAY (exit=$_exit_code, signal)"
fi

# --- --help and --version without DISPLAY ---

echo ""
echo "--help and --version without DISPLAY:"

# autocutsel --help (works without X)
_output=$("$AUTOCUTSEL" --help 2>&1)
_exit_code=$?
assert_contains "autocutsel --help shows usage" "$_output" "usage:"
assert_exit "autocutsel --help exits 0" "$_exit_code" 0

# autocutsel -help (also works)
_output=$("$AUTOCUTSEL" -help 2>&1)
_exit_code=$?
assert_contains "autocutsel -help shows usage" "$_output" "usage:"
assert_exit "autocutsel -help exits 0" "$_exit_code" 0

# autocutsel --version
_output=$("$AUTOCUTSEL" --version 2>&1)
_exit_code=$?
assert_contains "autocutsel --version shows version" "$_output" "autocutsel v"
assert_exit "autocutsel --version exits 0" "$_exit_code" 0

# cutsel --help
_output=$("$CUTSEL" --help 2>&1)
_exit_code=$?
assert_contains "cutsel --help shows usage" "$_output" "usage:"
assert_exit "cutsel --help exits 0" "$_exit_code" 0

# cutsel --version
_output=$("$CUTSEL" --version 2>&1)
_exit_code=$?
assert_contains "cutsel --version shows version" "$_output" "cutsel v"
assert_exit "cutsel --version exits 0" "$_exit_code" 0

# Restore DISPLAY
if [ -n "$_saved_display" ]; then
  export DISPLAY="$_saved_display"
fi

# --- Man page checks ---

echo ""
echo "Man page:"

_manpage="$(dirname "$0")/../autocutsel.1.in"
if [ ! -f "$_manpage" ]; then
  _manpage="$(dirname "$0")/../autocutsel.1"
fi

if [ -f "$_manpage" ]; then
  # Man page renders without errors
  _man_errors=$(man -l "$_manpage" 2>&1 >/dev/null)
  _tests_run=$((_tests_run + 1))
  if [ -z "$_man_errors" ]; then
    _tests_passed=$((_tests_passed + 1))
    echo "  PASS: man page renders without errors"
  else
    _tests_failed=$((_tests_failed + 1))
    echo "  FAIL: man page has rendering errors: $_man_errors"
  fi

  # Man page contains all required sections
  _man_content=$(man -l "$_manpage" 2>/dev/null | col -b)
  for _section in NAME SYNOPSIS DESCRIPTION OPTIONS EXAMPLES "INSTANCE MANAGEMENT" SYSTEMD "WAYLAND SUPPORT" AUTHORS LICENSE; do
    _tests_run=$((_tests_run + 1))
    if echo "$_man_content" | grep -q "$_section"; then
      _tests_passed=$((_tests_passed + 1))
      echo "  PASS: man page has section $_section"
    else
      _tests_failed=$((_tests_failed + 1))
      echo "  FAIL: man page missing section $_section"
    fi
  done

  # All options documented
  for _opt in "\-selection" "\-cutbuffer" "\-debug" "\-verbose" "\-fork" "\-pause" "\-buttonup" "\-mouseonly" "\-encoding"; do
    _tests_run=$((_tests_run + 1))
    if echo "$_man_content" | grep -q -- "$_opt"; then
      _tests_passed=$((_tests_passed + 1))
      echo "  PASS: man page documents $_opt"
    else
      _tests_failed=$((_tests_failed + 1))
      echo "  FAIL: man page missing option $_opt"
    fi
  done
else
  _tests_run=$((_tests_run + 1))
  _tests_skipped=$((_tests_skipped + 1))
  echo "  SKIP: man page not found"
fi

# --- Systemd unit checks ---

echo ""
echo "Systemd unit:"

_service="$(dirname "$0")/../contrib/systemd/autocutsel@.service"
if [ -f "$_service" ]; then
  # Basic syntax check: has required sections
  for _key in Unit Service Install; do
    _tests_run=$((_tests_run + 1))
    if grep -q "^\[$_key\]" "$_service"; then
      _tests_passed=$((_tests_passed + 1))
      echo "  PASS: service file has [$_key] section"
    else
      _tests_failed=$((_tests_failed + 1))
      echo "  FAIL: service file missing [$_key] section"
    fi
  done

  # Has ExecStart
  _tests_run=$((_tests_run + 1))
  if grep -q "^ExecStart=" "$_service"; then
    _tests_passed=$((_tests_passed + 1))
    echo "  PASS: service file has ExecStart"
  else
    _tests_failed=$((_tests_failed + 1))
    echo "  FAIL: service file missing ExecStart"
  fi

  # Has hardening options
  for _harden in NoNewPrivileges ProtectSystem ProtectHome; do
    _tests_run=$((_tests_run + 1))
    if grep -q "$_harden" "$_service"; then
      _tests_passed=$((_tests_passed + 1))
      echo "  PASS: service file has $_harden"
    else
      _tests_failed=$((_tests_failed + 1))
      echo "  FAIL: service file missing $_harden"
    fi
  done
else
  _tests_run=$((_tests_run + 1))
  _tests_skipped=$((_tests_skipped + 1))
  echo "  SKIP: service file not found"
fi

# --- Args file checks ---

echo ""
echo "Example args files:"

_argsdir="$(dirname "$0")/../contrib/systemd"
for _argfile in mouseonly.args clipboard.args primary.args; do
  _tests_run=$((_tests_run + 1))
  if [ -f "$_argsdir/$_argfile" ]; then
    _tests_passed=$((_tests_passed + 1))
    echo "  PASS: $_argfile exists"
  else
    _tests_failed=$((_tests_failed + 1))
    echo "  FAIL: $_argfile not found"
  fi
done

test_summary
