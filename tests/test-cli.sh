#!/bin/sh
# Test command-line interface parsing for autocutsel and cutsel
set -u
. "$(dirname "$0")/helpers.sh"

ensure_display || skip_all "No X display available"
cleanup_instances

echo "=== CLI parsing tests ==="

# --- autocutsel ---

echo "autocutsel:"

# Invalid option → usage + exit 1
run_capture 3 "$AUTOCUTSEL" -invalid
assert_contains "invalid option shows usage" "$_output" "usage:"
assert_exit "invalid option exits 1" "$_exit_code" 1

# All short options recognized (should NOT show usage)
run_capture_unbuffered 2 "$AUTOCUTSEL" -s CLIPBOARD -c 0 -d -v -p 500
assert_not_contains "-s -c -d -v -p recognized" "$_output" "usage:"

# -buttonup recognized
run_capture_unbuffered 2 "$AUTOCUTSEL" -buttonup -debug
assert_not_contains "-buttonup recognized" "$_output" "usage:"

# -mouseonly recognized
run_capture_unbuffered 2 "$AUTOCUTSEL" -selection PRIMARY -mouseonly -debug
assert_not_contains "-mouseonly recognized" "$_output" "usage:"

# -encoding recognized
run_capture_unbuffered 2 "$AUTOCUTSEL" -encoding ISO-8859-1 -debug
assert_not_contains "-encoding recognized" "$_output" "usage:"
assert_contains "-encoding shows encoding info" "$_output" "Encoding conversion: ISO-8859-1"

# -e short form recognized
run_capture_unbuffered 2 "$AUTOCUTSEL" -e WINDOWS-1252 -debug
assert_contains "-e short form works" "$_output" "Encoding conversion: WINDOWS-1252"

# Version output with -verbose
run_capture_unbuffered 2 "$AUTOCUTSEL" -verbose
assert_contains "-verbose shows version" "$_output" "autocutsel v"

# Version output with -debug
run_capture_unbuffered 2 "$AUTOCUTSEL" -debug
assert_contains "-debug shows version" "$_output" "autocutsel v"

# --- cutsel ---

echo ""
echo "cutsel:"

# No arguments → usage + exit 1
run_capture 3 "$CUTSEL"
assert_contains "cutsel no args shows usage" "$_output" "usage:"
assert_exit "cutsel no args exits 1" "$_exit_code" 1

# Invalid subcommand → usage
run_capture 3 "$CUTSEL" invalid
assert_contains "cutsel invalid subcommand shows usage" "$_output" "usage:"

# cutsel cut (read cutbuffer)
run_capture 3 "$CUTSEL" cut
# Should not show usage (might be empty output if cutbuffer is empty)
assert_not_contains "cutsel cut recognized" "$_output" "usage:"

# cutsel targets
run_capture 3 "$CUTSEL" targets
assert_not_contains "cutsel targets recognized" "$_output" "usage:"

test_summary
