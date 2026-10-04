class_name TestCase
extends RefCounted
## Minimal assertion base for the headless test runner (tests/test_runner.tscn).

var failures: PackedStringArray = []
var root: Node  ## a node in the tree tests can parent things to
var _current: String = ""


func assert_true(cond: bool, msg: String = "") -> void:
	if not cond:
		failures.append("%s: expected true. %s" % [_current, msg])


func assert_false(cond: bool, msg: String = "") -> void:
	if cond:
		failures.append("%s: expected false. %s" % [_current, msg])


func assert_eq(a: Variant, b: Variant, msg: String = "") -> void:
	if a != b:
		failures.append("%s: expected %s == %s. %s" % [_current, str(a), str(b), msg])


func assert_near(a: float, b: float, eps: float = 0.001, msg: String = "") -> void:
	if absf(a - b) > eps:
		failures.append("%s: expected %f ≈ %f (±%f). %s" % [_current, a, b, eps, msg])


func assert_gt(a: float, b: float, msg: String = "") -> void:
	if not (a > b):
		failures.append("%s: expected %s > %s. %s" % [_current, str(a), str(b), msg])


func assert_lt(a: float, b: float, msg: String = "") -> void:
	if not (a < b):
		failures.append("%s: expected %s < %s. %s" % [_current, str(a), str(b), msg])


## Helper: same set of ints regardless of order.
func assert_same_set(a: PackedInt32Array, b: PackedInt32Array, msg: String = "") -> void:
	var sa := a.duplicate()
	var sb := b.duplicate()
	sa.sort()
	sb.sort()
	if sa != sb:
		failures.append("%s: sets differ (%d vs %d items). %s" % [_current, sa.size(), sb.size(), msg])
