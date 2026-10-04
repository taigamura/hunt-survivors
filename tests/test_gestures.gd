extends TestCase
## GestureRecognizer against thumb-like strokes: rounded corners, unclosed shapes, overshoot,
## lopsided proportions, rotation, wobble and uneven sampling. The recognizer works in mm;
## these tests use 10 px per mm (about a phone's 720-wide viewport).

const PX_PER_MM := 10.0


func _rec() -> GestureRecognizer:
	var r := GestureRecognizer.new()
	r.setup(PX_PER_MM)
	return r


## Polyline through `corners`, corners rounded by `round_px`, sampled unevenly (thumbs speed
## up mid-stroke), rotated by `rot` around the first corner, with deterministic wobble.
func _stroke(corners: Array, wobble: float = 2.0, seed_value: int = 1, round_px: float = 0.0, rot: float = 0.0) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var pts: Array[Vector2] = []
	for c: Vector2 in corners:
		pts.append(c)
	if round_px > 0.0:
		pts = _round_corners(pts, round_px)
	var out := PackedVector2Array()
	var origin: Vector2 = corners[0]
	for k in range(pts.size() - 1):
		var a := pts[k]
		var b := pts[k + 1]
		var steps := maxi(1, int(a.distance_to(b) / rng.randf_range(4.0, 14.0)))
		for s in steps:
			var p := a.lerp(b, float(s) / steps) + Vector2(rng.randf_range(-wobble, wobble), rng.randf_range(-wobble, wobble))
			out.append(origin + (p - origin).rotated(rot))
	out.append(origin + (pts[pts.size() - 1] - origin).rotated(rot))
	return out


## Replaces each interior corner with a short arc (a thumb never makes a sharp corner).
func _round_corners(pts: Array[Vector2], r: float) -> Array[Vector2]:
	var out: Array[Vector2] = [pts[0]]
	for k in range(1, pts.size() - 1):
		var a := pts[k - 1]
		var c := pts[k]
		var b := pts[k + 1]
		var p0 := c + (a - c).normalized() * minf(r, a.distance_to(c) * 0.45)
		var p1 := c + (b - c).normalized() * minf(r, b.distance_to(c) * 0.45)
		for s in 7:
			var t := s / 6.0
			out.append(p0.lerp(c, t).lerp(c.lerp(p1, t), t))  # quadratic bezier
	out.append(pts[pts.size() - 1])
	return out


func _circle(c: Vector2, r: float, sweep_deg: float, cw: bool, squash: float = 1.0, start_deg: float = -90.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := 60
	for k in n + 1:
		var a := deg_to_rad(start_deg) + deg_to_rad(sweep_deg) * float(k) / n * (1.0 if cw else -1.0)
		out.append(c + Vector2(cos(a) * r, sin(a) * r * squash))
	return out


func _kind(points: PackedVector2Array) -> String:
	return String(_rec().classify(points)["kind"])


func test_tap_tolerates_a_rolling_thumb() -> void:
	assert_eq(_kind(_stroke([Vector2(300, 600), Vector2(305, 604)])), "tap")
	assert_eq(_kind(_stroke([Vector2(300, 600), Vector2(330, 615), Vector2(320, 590)])), "tap", "4 mm of roll is still a tap")


func test_swipe_direction() -> void:
	var r := _rec()
	var g := r.classify(_stroke([Vector2(300, 600), Vector2(480, 600)]))
	assert_eq(g["kind"], "swipe")
	assert_true((g["dir"] as Vector2).dot(Vector2.RIGHT) > 0.98, "rightward")
	var up := r.classify(_stroke([Vector2(400, 900), Vector2(390, 700)], 3.0, 7))
	assert_eq(up["kind"], "swipe")
	assert_true((up["dir"] as Vector2).dot(Vector2.UP) > 0.95, "upward")
	assert_eq(_kind(_circle(Vector2(400, 700), 140.0, 100.0, true)), "swipe", "thumbs swipe in arcs")


func test_circles() -> void:
	assert_eq(_kind(_circle(Vector2(400, 700), 90.0, 350.0, true)), "circle", "clockwise")
	assert_eq(_kind(_circle(Vector2(400, 700), 90.0, 330.0, false, 1.0, 40.0)), "circle", "counter-clockwise, other start")
	assert_eq(_kind(_circle(Vector2(400, 700), 100.0, 360.0, true, 0.6)), "circle", "an oval")
	assert_eq(_kind(_circle(Vector2(400, 700), 80.0, 300.0, true)), "circle", "left open")
	assert_eq(_kind(_circle(Vector2(400, 700), 80.0, 420.0, false)), "circle", "overshot")


func test_triangles_the_way_thumbs_draw_them() -> void:
	var A := Vector2(400, 560)
	var B := Vector2(510, 750)
	var C := Vector2(290, 750)
	var cases := {
		"sharp": _stroke([A, B, C, A]),
		"rounded": _stroke([A, B, C, A], 2.0, 2, 35.0),
		"very rounded": _stroke([A, B, C, A], 2.0, 3, 55.0),
		"not closed": _stroke([A, B, C, A.lerp(C, 0.3)], 2.0, 4, 30.0),
		"overshot": _stroke([A, B, C, A, A.lerp(B, 0.25)], 2.0, 5, 25.0),
		"from a base corner, counter-clockwise": _stroke([C, B, A, C], 2.5, 6, 30.0),
		"tilted": _stroke([A, B, C, A], 2.0, 7, 30.0, 0.5),
		"right triangle": _stroke([Vector2(300, 560), Vector2(300, 760), Vector2(500, 760), Vector2(305, 565)], 2.0, 8, 30.0),
		"squat": _stroke([Vector2(400, 640), Vector2(540, 740), Vector2(260, 740), Vector2(400, 645)], 2.0, 9, 25.0),
		"small": _stroke([Vector2(400, 640), Vector2(450, 725), Vector2(350, 725), Vector2(400, 645)], 1.5, 10, 12.0),
	}
	for name: String in cases:
		assert_eq(_kind(cases[name]), "triangle", name)


func test_v_points_at_its_tip() -> void:
	var r := _rec()
	var g := r.classify(_stroke([Vector2(320, 600), Vector2(400, 760), Vector2(480, 600)]))
	assert_eq(g["kind"], "v")
	assert_true((g["dir"] as Vector2).dot(Vector2.DOWN) > 0.9, "a V points down at its tip")
	var side := r.classify(_stroke([Vector2(500, 560), Vector2(340, 640), Vector2(500, 720)], 2.0, 4, 25.0))
	assert_eq(side["kind"], "v", "a rounded sideways V (<)")
	assert_true((side["dir"] as Vector2).dot(Vector2.LEFT) > 0.85)
	assert_eq(_kind(_stroke([Vector2(330, 680), Vector2(380, 740), Vector2(500, 560)], 2.0, 5, 15.0)), "v", "a check mark")
	assert_eq(_kind(_stroke([Vector2(340, 560), Vector2(400, 760), Vector2(460, 570)], 2.0, 6, 20.0)), "v", "a narrow V")


func test_zigzags() -> void:
	assert_eq(_kind(_stroke([Vector2(300, 600), Vector2(480, 600), Vector2(300, 740), Vector2(480, 740)])), "zigzag", "a Z")
	assert_eq(_kind(_stroke([Vector2(300, 600), Vector2(480, 600), Vector2(300, 740), Vector2(480, 740)], 2.0, 2, 30.0)), "zigzag", "a rounded Z")
	assert_eq(_kind(_stroke([Vector2(480, 600), Vector2(300, 600), Vector2(480, 740), Vector2(300, 740)], 2.0, 3, 25.0)), "zigzag", "a mirrored Z")
	assert_eq(_kind(_stroke([Vector2(420, 540), Vector2(340, 660), Vector2(440, 680), Vector2(360, 820)], 2.0, 9, 15.0)), "zigzag", "a lightning bolt")
	assert_eq(_kind(_stroke([Vector2(280, 700), Vector2(340, 600), Vector2(400, 700), Vector2(460, 600), Vector2(520, 700)], 2.0, 11, 15.0)), "zigzag", "a W-ish zigzag")


func test_c_shape_is_unrecognized() -> void:
	assert_eq(_kind(_circle(Vector2(400, 700), 100.0, 200.0, true)), "", "too curved to swipe, too open to circle")


func test_physical_scale() -> void:
	var r := GestureRecognizer.new()
	r.setup(PX_PER_MM * 2.0)  # a denser screen: the same 4 mm flick is twice as many px
	assert_eq(String(r.classify(_stroke([Vector2(300, 600), Vector2(380, 600)]))["kind"]), "tap", "80 px at 20 px/mm is a tap")


## Random sloppy variant of a shape: rotation, proportions, rounding, wobble, closure gap,
## overshoot, start corner and direction all vary.
func _variant(kind: String, rng: RandomNumberGenerator) -> PackedVector2Array:
	var c := Vector2(400, 700)
	var size := rng.randf_range(70.0, 130.0)
	var aspect := rng.randf_range(0.65, 1.4)
	var rot := rng.randf_range(-0.45, 0.45)
	var corners: Array[Vector2] = []
	match kind:
		"circle":
			var sweep := rng.randf_range(300.0, 410.0)
			return _circle(c, size, sweep, rng.randf() < 0.5, aspect, rng.randf_range(0.0, 360.0))
		"triangle":
			var tri: Array[Vector2] = [Vector2(0, -1), Vector2(0.95, 0.65), Vector2(-0.95, 0.65)]
			var s := rng.randi() % 3
			var d := 1 if rng.randf() < 0.5 else -1
			for k in 3:
				corners.append(tri[posmod(s + k * d, 3)])
			var gap := rng.randf_range(0.0, 0.35)
			corners.append(corners[0].lerp(corners[2], gap))
		"v":
			var w := rng.randf_range(0.45, 1.1)
			corners = [Vector2(-w, -1), Vector2(rng.randf_range(-0.2, 0.2), 1), Vector2(w, -1)]
			if rng.randf() < 0.5:
				corners.reverse()
		"zigzag":
			corners = [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
			if rng.randf() < 0.5:
				for k in corners.size():
					corners[k].x = -corners[k].x
			if rng.randf() < 0.5:
				corners.reverse()
	var pts: Array = []
	for p in corners:
		pts.append(c + Vector2(p.x * size, p.y * size * aspect))
	return _stroke(pts, rng.randf_range(1.0, 3.5), rng.randi(), rng.randf_range(0.0, size * 0.4), rot)


func test_sloppy_shape_sweep() -> void:
	var r := _rec()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var report: PackedStringArray = []
	for kind in ["circle", "triangle", "v", "zigzag"]:
		var hits := 0
		var confused := {}
		var n := 60
		for k in n:
			var got := String(r.classify(_variant(kind, rng))["kind"])
			if got == kind:
				hits += 1
			else:
				confused[got if got != "" else "?"] = int(confused.get(got if got != "" else "?", 0)) + 1
		report.append("%s %d/%d %s" % [kind, hits, n, str(confused)])
		assert_gt(float(hits) / n, 0.9, "%s recognized >90%% of sloppy variants (%d/%d, misses %s)" % [kind, hits, n, str(confused)])
	print("  sweep: ", " | ".join(report))


func _touch(pad: GesturePad, p: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = p
	e.pressed = pressed
	pad._input(e)


func _drag(pad: GesturePad, p: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.position = p
	pad._input(e)


func test_pad_hold_survives_a_rolling_thumb() -> void:
	var pad := GesturePad.new()
	root.add_child(pad)
	var got: Array[Dictionary] = []
	pad.gestured.connect(func(ev: Dictionary) -> void: got.append(ev))
	var vs := pad.get_viewport_rect().size
	var p := Vector2(vs.x * 0.75, vs.y * 0.7)
	_touch(pad, p, true)
	assert_true(pad.is_active(), "the right half is the gesture pad")
	# a thumb pressing into glass rolls ~4 mm while it holds
	for k in 6:
		_drag(pad, p + Vector2(4.0 * pad.px_per_mm * (k % 2), 2.0 * pad.px_per_mm))
	pad.down_msec -= 400  # 0.4 s have passed
	pad._process(0.016)
	assert_true(pad.holding, "still a hold after 4 mm of roll")
	_drag(pad, p + Vector2(0, -20.0 * pad.px_per_mm))  # drag up to aim
	_touch(pad, p + Vector2(0, -20.0 * pad.px_per_mm), false)
	assert_eq(got.size(), 1)
	assert_eq(String(got[0]["kind"]), "hold")
	assert_true((got[0]["dir"] as Vector2).dot(Vector2.UP) > 0.9, "aimed up")
	# a quick rolling tap is a tap
	got.clear()
	_touch(pad, p, true)
	_drag(pad, p + Vector2(3.0 * pad.px_per_mm, 0))
	_touch(pad, p + Vector2(3.0 * pad.px_per_mm, 0), false)
	assert_eq(String(got[0]["kind"]), "tap")
	# the stick half is not the pad's
	got.clear()
	_touch(pad, Vector2(vs.x * 0.2, vs.y * 0.7), true)
	assert_false(pad.is_active(), "left half belongs to the move stick")
