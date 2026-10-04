class_name GestureRecognizer
extends RefCounted
## Classifies one finished finger stroke (screen-space points) into a gesture:
##   tap, swipe, circle, v, zigzag, triangle   ("" = not recognized)
## "hold" is detected live by the GesturePad (finger down, not moving), not here.
## Pure logic so it can be unit-tested with synthetic strokes. Thresholds come from tuning
## `gestures.*` in base-resolution px; `px_scale` adapts them to the real viewport.

const TAP := "tap"
const SWIPE := "swipe"
const HOLD := "hold"
const CIRCLE := "circle"
const V := "v"
const ZIGZAG := "zigzag"
const TRIANGLE := "triangle"
const SHAPES: Array[String] = [CIRCLE, V, ZIGZAG, TRIANGLE]

var tap_max_dist: float = 26.0
var swipe_min_len: float = 70.0
var straightness: float = 0.86
var shape_min_size: float = 60.0
var corner_deg: float = 75.0
var circle_turn_deg: float = 270.0
var closed_frac: float = 0.35
var resample_n: int = 40
var px_scale: float = 1.0


func setup(scale: float = 1.0) -> void:
	px_scale = scale
	tap_max_dist = Tuning.f("gestures.tap_max_dist", 26.0)
	swipe_min_len = Tuning.f("gestures.swipe_min_len", 70.0)
	straightness = Tuning.f("gestures.swipe_straightness", 0.86)
	shape_min_size = Tuning.f("gestures.shape_min_size", 60.0)
	corner_deg = Tuning.f("gestures.corner_deg", 75.0)
	circle_turn_deg = Tuning.f("gestures.circle_turn_deg", 270.0)
	closed_frac = Tuning.f("gestures.closed_frac", 0.35)
	resample_n = Tuning.i("gestures.resample", 40)


## Returns {"kind": String, "dir": Vector2 (unit, screen space), "center": Vector2}.
func classify(points: PackedVector2Array) -> Dictionary:
	var out := {"kind": "", "dir": Vector2.ZERO, "center": Vector2.ZERO}
	if points.is_empty():
		return out
	var start := points[0]
	var end := points[points.size() - 1]
	var length := path_length(points)
	out["center"] = _centroid(points)
	if length < tap_max_dist * px_scale:
		out["kind"] = TAP
		return out
	var chord := end - start
	out["dir"] = chord.normalized() if chord.length() > 0.001 else Vector2.ZERO
	var straight := chord.length() / maxf(length, 0.001)
	if straight >= straightness and length >= swipe_min_len * px_scale:
		out["kind"] = SWIPE
		return out
	var bb := _bounds(points)
	var diag := bb.size.length()
	if diag < shape_min_size * px_scale:
		# too small to be a shape: a short flick still reads as a swipe
		if chord.length() >= swipe_min_len * 0.6 * px_scale:
			out["kind"] = SWIPE
		return out
	var pts := resample(points, resample_n)
	var corners := find_corners(pts)
	var turn := absf(total_turn(pts))
	var closed := start.distance_to(end) <= closed_frac * diag
	if closed and corners.size() >= 2 and corners.size() <= 4 and turn >= 200.0:
		out["kind"] = TRIANGLE
	elif turn >= circle_turn_deg and corners.size() <= 1:
		out["kind"] = CIRCLE
		out["dir"] = Vector2.ZERO
	elif not closed and corners.size() == 1:
		out["kind"] = V
		var tip := pts[corners[0]]
		var mid := (pts[0] + pts[pts.size() - 1]) * 0.5
		out["dir"] = (tip - mid).normalized()
	elif not closed and corners.size() >= 2:
		out["kind"] = ZIGZAG
	elif straight >= 0.7 and length >= swipe_min_len * px_scale:
		out["kind"] = SWIPE
	return out


static func path_length(points: PackedVector2Array) -> float:
	var l := 0.0
	for k in range(1, points.size()):
		l += points[k].distance_to(points[k - 1])
	return l


## Equally spaced points along the path (the $1-recognizer resampling step).
static func resample(points: PackedVector2Array, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	if points.size() < 2:
		out.append(points[0] if points.size() == 1 else Vector2.ZERO)
		return out
	var interval := path_length(points) / float(n - 1)
	var acc := 0.0
	var prev := points[0]
	out.append(prev)
	var k := 1
	while k < points.size():
		var cur := points[k]
		var d := prev.distance_to(cur)
		if d > 0.0 and acc + d >= interval:
			var q := prev + (cur - prev) * ((interval - acc) / d)
			out.append(q)
			prev = q
			acc = 0.0
		else:
			acc += d
			prev = cur
			k += 1
	while out.size() < n:
		out.append(points[points.size() - 1])
	if out.size() > n:
		out.resize(n)
	return out


## Sum of signed turning angles in degrees (positive = clockwise in screen space).
static func total_turn(pts: PackedVector2Array) -> float:
	var t := 0.0
	for k in range(1, pts.size() - 1):
		var a := pts[k] - pts[k - 1]
		var b := pts[k + 1] - pts[k]
		if a.length_squared() < 0.0001 or b.length_squared() < 0.0001:
			continue
		t += rad_to_deg(a.angle_to(b))
	return t


## Indices of sharp corners: local maxima of the turn between the incoming and outgoing
## chords spanning 2 samples each side.
func find_corners(pts: PackedVector2Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	var n := pts.size()
	var w := 2
	var turns := PackedFloat32Array()
	turns.resize(n)
	for k in n:
		if k < w or k >= n - w:
			turns[k] = 0.0
			continue
		var a := pts[k] - pts[k - w]
		var b := pts[k + w] - pts[k]
		if a.length_squared() < 0.0001 or b.length_squared() < 0.0001:
			turns[k] = 0.0
			continue
		turns[k] = absf(rad_to_deg(a.angle_to(b)))
	var k2 := w
	while k2 < n - w:
		if turns[k2] >= corner_deg:
			# take the peak of this run of above-threshold samples
			var best := k2
			while k2 < n - w and turns[k2] >= corner_deg:
				if turns[k2] > turns[best]:
					best = k2
				k2 += 1
			out.append(best)
		else:
			k2 += 1
	return out


static func _centroid(points: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in points:
		c += p
	return c / float(maxi(1, points.size()))


static func _bounds(points: PackedVector2Array) -> Rect2:
	var r := Rect2(points[0], Vector2.ZERO)
	for p in points:
		r = r.expand(p)
	return r
