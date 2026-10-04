class_name GestureRecognizer
extends RefCounted
## Classifies one finished finger stroke (screen-space points) into a gesture:
##   tap, swipe, circle, v, zigzag, triangle   ("" = not recognized)
## "hold" is detected live by the GesturePad (finger down, not moving), not here.
##
## Distances are physical millimetres (tuning `gestures.*_mm`), converted with `px_per_mm`, so
## a thumb's wobble is tolerated the same on every screen. Shapes are classified in two steps:
##  1. Net turning splits closed shapes (circle, triangle: 200+ degrees, with the ends close
##     together unless it's nearly a full turn) from open ones (V, zigzag). Open shapes must
##     turn at corners (a C, which turns evenly, is rejected).
##  2. Within that group, a $1-recognizer-style template match (resample, rotate to the
##     indicative angle, scale to a square, best-angle distance) picks the shape. It tolerates
##     rounded corners, any start corner, rotation and lopsided proportions, which corner
##     counting did not (real thumbs never draw sharp corners).
## Pure logic so it can be unit-tested with synthetic strokes.

const TAP := "tap"
const SWIPE := "swipe"
const HOLD := "hold"
const CIRCLE := "circle"
const V := "v"
const ZIGZAG := "zigzag"
const TRIANGLE := "triangle"
const SHAPES: Array[String] = [CIRCLE, V, ZIGZAG, TRIANGLE]
const CLOSED: Array[String] = [CIRCLE, TRIANGLE]
const OPEN: Array[String] = [V, ZIGZAG]

const N := 64
const SQUARE := 250.0
const ANGLE_RANGE := deg_to_rad(45.0)
const ANGLE_STEP := deg_to_rad(2.0)
const PHI := 0.6180339887

var px_per_mm: float = 10.0
var tap_max_mm: float = 6.0
var swipe_min_mm: float = 7.0
var straightness: float = 0.86
var shape_min_mm: float = 9.0
var closed_turn_deg: float = 200.0
var closed_gap_frac: float = 0.6
var min_turn_deg: float = 100.0
var open_concentration: float = 0.45
var min_score: float = 0.6

## kind -> Array of normalized templates (PackedVector2Array), shared by all instances
static var _templates: Dictionary = {}


func setup(p_px_per_mm: float = 10.0) -> void:
	px_per_mm = p_px_per_mm
	tap_max_mm = Tuning.f("gestures.tap_max_mm", 6.0)
	swipe_min_mm = Tuning.f("gestures.swipe_min_mm", 7.0)
	straightness = Tuning.f("gestures.swipe_straightness", 0.86)
	shape_min_mm = Tuning.f("gestures.shape_min_mm", 9.0)
	closed_turn_deg = Tuning.f("gestures.closed_turn_deg", 200.0)
	closed_gap_frac = Tuning.f("gestures.closed_gap_frac", 0.6)
	min_turn_deg = Tuning.f("gestures.min_turn_deg", 100.0)
	open_concentration = Tuning.f("gestures.open_concentration", 0.45)
	min_score = Tuning.f("gestures.min_score", 0.6)
	if _templates.is_empty():
		_build_templates()


## Returns {"kind": String, "dir": Vector2 (unit, screen space), "center": Vector2, "score": float}.
func classify(points: PackedVector2Array) -> Dictionary:
	var out := {"kind": "", "dir": Vector2.ZERO, "center": Vector2.ZERO, "score": 0.0}
	if points.is_empty():
		return out
	var start := points[0]
	var end := points[points.size() - 1]
	out["center"] = _centroid(points)
	var reach := 0.0
	for p in points:
		reach = maxf(reach, p.distance_to(start))
	if reach < tap_max_mm * px_per_mm:
		out["kind"] = TAP
		return out
	var length := path_length(points)
	var chord := end - start
	out["dir"] = chord.normalized() if chord.length() > 0.001 else Vector2.ZERO
	var straight := chord.length() / maxf(length, 0.001)
	if straight >= straightness and length >= swipe_min_mm * px_per_mm:
		out["kind"] = SWIPE
		return out
	var pts := resample(points, N)
	var turns := turn_angles(_smooth(_smooth(pts)))
	var net := 0.0
	var total := 0.0
	var pos := 0.0
	var neg := 0.0
	for k in turns.size():
		var t := turns[k]
		net += t
		if absf(t) < 3.0:
			turns[k] = 0.0  # wobble, not intent
			continue
		total += absf(t)
		if t > 0.0:
			pos += t
		else:
			neg -= t
	net = absf(net)
	var diag := _bounds(points).size.length()
	if diag < shape_min_mm * px_per_mm or total < min_turn_deg:
		# not a shape: a curved or short flick still reads as a swipe
		if straight >= 0.65 and chord.length() >= swipe_min_mm * 0.6 * px_per_mm:
			out["kind"] = SWIPE
		return out
	var closed := net >= closed_turn_deg and (start.distance_to(end) <= closed_gap_frac * diag or net >= 300.0)
	var group := CLOSED if closed else OPEN
	var reverses := minf(pos, neg) >= 60.0  # turns both ways: zigzag evidence
	if not closed and not reverses and concentration(turns) < open_concentration:
		return out  # turns one way, evenly, like a C: not a V
	var cand := normalize(pts)
	var best := ""
	var best_d := INF
	for kind in group:
		for t: PackedVector2Array in _templates[kind]:
			var d := distance_at_best_angle(cand, t)
			if d < best_d:
				best_d = d
				best = kind
	var score := 1.0 - best_d / (0.5 * sqrt(2.0 * SQUARE * SQUARE))
	out["score"] = score
	if score < min_score:
		if group == OPEN and straight >= 0.7:
			out["kind"] = SWIPE
		return out
	out["kind"] = best
	match best:
		CIRCLE, TRIANGLE:
			out["dir"] = Vector2.ZERO
		V:
			# a V points from the middle of its open end toward its tip
			var tip := _farthest_from_line(pts, pts[0], pts[pts.size() - 1])
			out["dir"] = (tip - (pts[0] + pts[pts.size() - 1]) * 0.5).normalized()
	return out


# ------------------------------------------------------------------ $1 machinery

## Resample -> rotate so centroid->first point is at angle 0 -> scale to a square -> center.
static func normalize(pts: PackedVector2Array) -> PackedVector2Array:
	var c := _centroid(pts)
	var theta := (pts[0] - c).angle()
	var out := PackedVector2Array()
	for p in pts:
		out.append((p - c).rotated(-theta))
	var b := _bounds(out)
	var sx := SQUARE / maxf(b.size.x, 1.0)
	var sy := SQUARE / maxf(b.size.y, 1.0)
	# don't blow a thin stroke up into a square (the $1 1-D gesture problem): cap the stretch
	var ratio := 4.0
	if sx > sy * ratio:
		sx = sy * ratio
	elif sy > sx * ratio:
		sy = sx * ratio
	for k in out.size():
		out[k] = Vector2(out[k].x * sx, out[k].y * sy)
	var c2 := _centroid(out)
	for k in out.size():
		out[k] -= c2
	return out


## Golden-section search over +-45 degrees for the best alignment.
static func distance_at_best_angle(pts: PackedVector2Array, tmpl: PackedVector2Array) -> float:
	var a := -ANGLE_RANGE
	var b := ANGLE_RANGE
	var x1 := PHI * a + (1.0 - PHI) * b
	var f1 := _distance_at_angle(pts, tmpl, x1)
	var x2 := (1.0 - PHI) * a + PHI * b
	var f2 := _distance_at_angle(pts, tmpl, x2)
	while absf(b - a) > ANGLE_STEP:
		if f1 < f2:
			b = x2
			x2 = x1
			f2 = f1
			x1 = PHI * a + (1.0 - PHI) * b
			f1 = _distance_at_angle(pts, tmpl, x1)
		else:
			a = x1
			x1 = x2
			f1 = f2
			x2 = (1.0 - PHI) * a + PHI * b
			f2 = _distance_at_angle(pts, tmpl, x2)
	return minf(f1, f2)


static func _distance_at_angle(pts: PackedVector2Array, tmpl: PackedVector2Array, angle: float) -> float:
	var d := 0.0
	var n := mini(pts.size(), tmpl.size())
	var cs := cos(angle)
	var sn := sin(angle)
	for k in n:
		var p := pts[k]
		d += Vector2(p.x * cs - p.y * sn, p.x * sn + p.y * cs).distance_to(tmpl[k])
	return d / n


## Templates: each shape traced from every start corner, both directions, a few proportions.
static func _build_templates() -> void:
	var raw: Dictionary = {CIRCLE: [], TRIANGLE: [], V: [], ZIGZAG: []}
	for cw in [true, false]:
		for sweep in [330.0, 360.0, 400.0]:
			var pts: Array[Vector2] = []
			for k in 33:
				var a := deg_to_rad(sweep) * k / 32.0 * (1.0 if cw else -1.0)
				pts.append(Vector2(cos(a), sin(a)))
			raw[CIRCLE].append(pts)
	var tris := [
		[Vector2(0, -1), Vector2(0.9, 0.6), Vector2(-0.9, 0.6)],   # equilateral-ish
		[Vector2(0, -1), Vector2(0, 1), Vector2(1, 1)],            # right triangle
		[Vector2(0, -0.6), Vector2(1, 0.4), Vector2(-1, 0.4)],     # squat
	]
	for tri: Array in tris:
		for s in 3:
			for dir in [1, -1]:
				var pts: Array[Vector2] = []
				for k in 4:
					pts.append(tri[posmod(s + k * dir, 3)])
				raw[TRIANGLE].append(pts)
				var open: Array[Vector2] = pts.duplicate()
				open[3] = pts[2].lerp(pts[3], 0.75)  # left a little open
				raw[TRIANGLE].append(open)
	for v: Array in [
			[Vector2(-1, -1), Vector2(0, 1), Vector2(1, -1)],
			[Vector2(-0.5, -1), Vector2(0, 1), Vector2(0.5, -1)],
			[Vector2(-0.6, 0.2), Vector2(-0.2, 0.7), Vector2(1, -1)]]:   # check mark
		var pts: Array[Vector2] = []
		for p: Vector2 in v:
			pts.append(p)
		raw[V].append(pts)
		var rev := pts.duplicate()
		rev.reverse()
		raw[V].append(rev)
	for z: Array in [
			[Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)],
			[Vector2(1, -1), Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1)],
			[Vector2(0.4, -1), Vector2(-0.4, 0), Vector2(0.4, 0.1), Vector2(-0.4, 1)],
			[Vector2(-0.4, -1), Vector2(0.4, 0), Vector2(-0.4, 0.1), Vector2(0.4, 1)],
			[Vector2(-1, 0.5), Vector2(-0.5, -0.5), Vector2(0, 0.5), Vector2(0.5, -0.5), Vector2(1, 0.5)]]:
		var pts: Array[Vector2] = []
		for p: Vector2 in z:
			pts.append(p)
		raw[ZIGZAG].append(pts)
		var rev := pts.duplicate()
		rev.reverse()
		raw[ZIGZAG].append(rev)
	_templates.clear()
	for kind: String in raw:
		var list: Array[PackedVector2Array] = []
		for corners: Array in raw[kind]:
			var poly := PackedVector2Array()
			for p: Vector2 in corners:
				poly.append(p * 100.0)
			list.append(normalize(resample(poly, N)))
		_templates[kind] = list


# ------------------------------------------------------------------ geometry helpers

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
		while out.size() < n:
			out.append(out[0])
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


## Signed turning angle at each interior point, degrees (positive = clockwise on screen).
static func turn_angles(pts: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in range(1, pts.size() - 1):
		var a := pts[k] - pts[k - 1]
		var b := pts[k + 1] - pts[k]
		if a.length_squared() < 0.0001 or b.length_squared() < 0.0001:
			out.append(0.0)
			continue
		out.append(rad_to_deg(a.angle_to(b)))
	return out


## Sum of signed turning angles in degrees (positive = clockwise in screen space).
static func total_turn(pts: PackedVector2Array) -> float:
	var t := 0.0
	for a in turn_angles(pts):
		t += a
	return t


## Largest share of all turning that happens inside any window of a quarter of the stroke:
## about 1 for a V (all at the tip), 0.5 per corner of a zigzag, 0.25 for an even arc.
static func concentration(turns: PackedFloat32Array) -> float:
	var total := 0.0
	for t in turns:
		total += absf(t)
	if total <= 0.0:
		return 0.0
	var w := maxi(1, turns.size() / 4)
	var best := 0.0
	for k in range(0, turns.size() - w + 1):
		var sum := 0.0
		for j in range(k, k + w):
			sum += absf(turns[j])
		best = maxf(best, sum)
	return best / total


## 3-point moving average: wobble adds turning back and forth; smoothing removes it.
static func _smooth(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	for k in range(1, pts.size() - 1):
		out[k] = (pts[k - 1] + pts[k] + pts[k + 1]) / 3.0
	return out


static func _farthest_from_line(pts: PackedVector2Array, a: Vector2, b: Vector2) -> Vector2:
	var best := pts[0]
	var best_d := -1.0
	for p in pts:
		var d := Geom.seg_dist(p, a, b)
		if d > best_d:
			best_d = d
			best = p
	return best


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
