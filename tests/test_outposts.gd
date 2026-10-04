extends TestCase
## Outposts: capture, decay and effects.


func test_outpost_capture_and_decay() -> void:
	var o := Outposts.new()
	o.setup([Vector2.ZERO, Vector2(2000, 0)] as Array[Vector2])
	var dt := 1.0 / 60.0
	var t := 0.0
	var captured := -1
	while t < o.capture_time - 0.1:
		captured = o.update(dt, Vector2(10, 0))
		t += dt
	assert_eq(captured, -1, "not yet")
	assert_false(o.is_captured(0))
	# leave for a second: progress drains
	var before := o.progress[0]
	for k in 60:
		o.update(dt, Vector2(900, 0))
	assert_near(o.progress[0], maxf(0.0, before - o.decay_rate), 0.05, "progress drains when you leave")
	# come back and finish
	var got := -1
	for k in int((o.capture_time + 0.5) * 60.0):
		var r := o.update(dt, Vector2.ZERO)
		if r >= 0:
			got = r
	assert_eq(got, 0, "captured")
	assert_true(o.is_captured(0))
	assert_false(o.is_captured(1))


func test_outpost_effects() -> void:
	var o := Outposts.new()
	o.setup([Vector2.ZERO, Vector2(3000, 0)] as Array[Vector2])
	assert_eq(o.damage_bonus(), 0.0)
	assert_eq(o.spawn_mult_at(Vector2(100, 0)), 1.0)
	assert_eq(o.heal_rate_at(Vector2.ZERO), 0.0)
	o.captured[0] = 1
	assert_near(o.damage_bonus(), o.bonus_each)
	assert_near(o.spawn_mult_at(Vector2(500, 0)), o.suppress_mult, 0.0001, "suppresses spawns nearby")
	assert_eq(o.spawn_mult_at(Vector2(-2500, 0)), 1.0, "not far away")
	assert_gt(o.heal_rate_at(Vector2(20, 0)), 0.0, "heals inside")
