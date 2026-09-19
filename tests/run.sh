#!/usr/bin/env bash
# Runs the headless test suite.
#
# The harness cannot see engine stderr, so a test that asserts once and then
# errors leaves it reporting a clean pass. Godot still prints SCRIPT ERROR with
# a backtrace, so treating any SCRIPT ERROR as a failure closes that gap in the
# exit code, which is what automation keys on.
set -uo pipefail

GODOT="${GODOT:?set GODOT to the Godot 4 _console executable}"

output=$("$GODOT" --headless --path . --script res://tests/run_tests.gd 2>&1)
status=$?
printf '%s\n' "$output"

if printf '%s' "$output" | grep -q 'SCRIPT ERROR'; then
	echo "FAIL: SCRIPT ERROR in output - a test errored mid-run and may have reported a false pass"
	status=1
fi

exit $status
