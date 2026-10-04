extends TestCase
## GestureRecognizer: synthetic finger strokes (with a little wobble) classify correctly.


func _rec() -> GestureRecognizer:
	var r := GestureRecognizer.new()
	r.setup(1.0)
	return r


## Polyline through `corners`, sampled every ~6 px, with deterministic wobble.
func _stroke(corners: Array, wobble: float = 2.0, seed_value: int = 1) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := PackedVector2Array()
	for k in range(corners.size() - 1):
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[k + 1]
		var steps := maxi(2, int(a.distance_to(b) / 6.0))
		for s in steps:
			out.append(a.lerp(b, float(s) / steps) + Vector2(rng.randf_range(-wobble, wobble), rng.randf_range(-wobble, wobble)))
	out.append(corners[corners.size() - 1])
	return out


func _circle(c: Vector2, r: float, sweep_deg: float, cw: bool, squash: float = 1.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := 60
	var a0 := -PI * 0.5
	for k in n + 1:
		var a := a0 + deg_to_rad(sweep_deg) * float(k) / n * (1.0 if cw else -1.0)
		out.append(c + Vector2(cos(a) * r, sin(a) * r * squash))
	return out


func test_tap() -> void:
	var g := _rec().classify(_stroke([Vector2(300, 600), Vector2(305, 604)]))
	assert_eq(g["kind"], "tap")


func test_swipe_direction() -> void:
	var r := _rec()
	var g := r.classify(_stroke([Vector2(300, 600), Vector2(480, 600)]))
	assert_eq(g["kind"], "swipe")
	assert_true((g["dir"] as Vector2).dot(Vector2.RIGHT) > 0.98, "rightward")
	var up := r.classify(_stroke([Vector2(400, 900), Vector2(390, 700)], 3.0, 7))
	assert_eq(up["kind"], "swipe")
	assert_true((up["dir"] as Vector2).dot(Vector2.UP) > 0.95, "upward")
	var short := r.classify(_stroke([Vector2(300, 600), Vector2(345, 600)]))
	assert_eq(short["kind"], "swipe", "a short flick still swipes")


func test_circle_both_directions_and_squashed() -> void:
	var r := _rec()
	assert_eq(r.classify(_circle(Vector2(400, 700), 90.0, 350.0, true))["kind"], "circle", "clockwise")
	assert_eq(r.classify(_circle(Vector2(400, 700), 90.0, 330.0, false))["kind"], "circle", "counter-clockwise")
	assert_eq(r.classify(_circle(Vector2(400, 700), 100.0, 360.0, true, 0.7))["kind"], "circle", "an oval counts")


func test_triangle() -> void:
	var r := _rec()
	var tri := _stroke([Vector2(400, 560), Vector2(500, 740), Vector2(300, 740), Vector2(400, 565)])
	assert_eq(r.classify(tri)["kind"], "triangle")
	var tri2 := _stroke([Vector2(300, 740), Vector2(400, 560), Vector2(500, 740), Vector2(310, 735)], 2.5, 3)
	assert_eq(r.classify(tri2)["kind"], "triangle", "started from another corner")


func test_v_points_at_its_tip() -> void:
	var r := _rec()
	var g := r.classify(_stroke([Vector2(320, 600), Vector2(400, 760), Vector2(480, 600)]))
	assert_eq(g["kind"], "v")
	assert_true((g["dir"] as Vector2).dot(Vector2.DOWN) > 0.9, "a V points down at its tip")
	var side := r.classify(_stroke([Vector2(500, 560), Vector2(340, 640), Vector2(500, 720)], 2.0, 4))
	assert_eq(side["kind"], "v", "a sideways V (<)")
	assert_true((side["dir"] as Vector2).dot(Vector2.LEFT) > 0.9)


func test_zigzag() -> void:
	var r := _rec()
	var z := _stroke([Vector2(300, 600), Vector2(480, 600), Vector2(300, 740), Vector2(480, 740)])
	assert_eq(r.classify(z)["kind"], "zigzag", "a Z")
	var bolt := _stroke([Vector2(420, 540), Vector2(340, 660), Vector2(440, 680), Vector2(360, 820)], 2.0, 9)
	assert_eq(r.classify(bolt)["kind"], "zigzag", "a lightning bolt")


func test_curved_thumb_swipe_and_c_shape() -> void:
	var r := _rec()
	# thumbs swipe in arcs: a gentle one is still a swipe
	assert_eq(r.classify(_circle(Vector2(400, 700), 120.0, 110.0, true))["kind"], "swipe", "gentle arc")
	# a "C" is too curved to swipe, too open to circle, and has no corners: unrecognized
	assert_eq(r.classify(_circle(Vector2(400, 700), 100.0, 200.0, true))["kind"], "", "C shape")


func test_scales_with_viewport() -> void:
	var r := GestureRecognizer.new()
	r.setup(2.0)  # a 2x-resolution viewport: the same physical flick is twice as many px
	assert_eq(r.classify(_stroke([Vector2(300, 600), Vector2(340, 600)]))["kind"], "tap", "40 px at 2x is a tap")
