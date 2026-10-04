#!/usr/bin/env bash
# Runs every headless verification step and fails on any test failure or script error.
#   tools/run_checks.sh            # tests + 60 s smoke runs + benchmark + flow check
#   GODOT=/path/to/godot tools/run_checks.sh
set -u
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
LOGDIR="${LOGDIR:-$(mktemp -d)}"
mkdir -p "$LOGDIR"
FAILED=0

echo "Godot: $("$GODOT" --version)"
echo "Logs:  $LOGDIR"
# Refresh the class cache (class_name registry) so scripts resolve their types.
"$GODOT" --headless --path . --import >/dev/null 2>&1

run_step() {
	local name="$1"; shift
	local log="$LOGDIR/$name.log"
	timeout 1200 "$GODOT" --headless --path . "$@" >"$log" 2>&1
	local code=$?
	if grep -qE "SCRIPT ERROR|Parse Error|Compile Error" "$log"; then
		echo "FAIL  $name (script errors — see $log)"
		grep -E -A3 "SCRIPT ERROR|Parse Error|Compile Error" "$log" | head -20
		FAILED=1
	elif [ $code -ne 0 ]; then
		echo "FAIL  $name (exit $code — see $log)"
		tail -20 "$log"
		FAILED=1
	else
		echo "ok    $name"
	fi
	grep -E "^(BENCH|SMOKE|TESTS|FLOW|  \[END|  peak|  nodes)" "$log" | sed 's/^/      /'
}

run_step scripts      res://tools/check_scripts.tscn
run_step tests        --fixed-fps 60 res://tests/test_runner.tscn
run_step smoke        --fixed-fps 60 res://tests/smoke.tscn -- seconds=60
run_step benchmark    --fixed-fps 60 res://scenes/benchmark.tscn
run_step flow         --fixed-fps 60 res://tools/flow_check.tscn

if [ $FAILED -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "SOME CHECKS FAILED"; fi
exit $FAILED
