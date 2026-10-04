extends Node
## Loads data/tuning.json — the single source of every balance number.
## Gameplay scripts read values once (in setup) via the typed helpers below.

const PATH := "res://data/tuning.json"

var data: Dictionary = {}


func _init() -> void:
	reload()


func reload(path: String = PATH) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Tuning: cannot open %s" % path)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		data = parsed
	else:
		push_error("Tuning: %s is not a JSON object" % path)


## Dot-path lookup, e.g. g("player.speed").
func g(key: String, default: Variant = null) -> Variant:
	var node: Variant = data
	for part in key.split("."):
		if node is Dictionary and (node as Dictionary).has(part):
			node = (node as Dictionary)[part]
		else:
			if default == null:
				push_error("Tuning: missing key '%s'" % key)
			return default
	return node


func f(key: String, default: float = 0.0) -> float:
	return float(g(key, default))


func i(key: String, default: int = 0) -> int:
	return int(g(key, default))


func d(key: String) -> Dictionary:
	var v: Variant = g(key, {})
	return v if v is Dictionary else {}


func a(key: String) -> Array:
	var v: Variant = g(key, [])
	return v if v is Array else []


## Piecewise-linear curve sampled at t. Curve format: [[t0, v0], [t1, v1], ...].
func curve(key: String, t: float) -> float:
	return sample_curve(a(key), t)


static func sample_curve(points: Array, t: float) -> float:
	if points.is_empty():
		return 0.0
	var first: Array = points[0]
	if t <= float(first[0]):
		return float(first[1])
	for idx in range(1, points.size()):
		var p1: Array = points[idx]
		if t <= float(p1[0]):
			var p0: Array = points[idx - 1]
			var t0 := float(p0[0])
			var t1 := float(p1[0])
			var w := 0.0 if t1 <= t0 else (t - t0) / (t1 - t0)
			return lerpf(float(p0[1]), float(p1[1]), w)
	var last: Array = points[points.size() - 1]
	return float(last[1])
