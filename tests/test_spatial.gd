extends TestCase
## Spatial hash + EnemySystem queries (circle / arc / line) vs brute force.


func _make(n: int, seed_value: int) -> EnemySystem:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var field := FlowField.new(Rect2(-3000, -3000, 6000, 6000), 40.0, 84)
	var es := EnemySystem.new()
	root.add_child(es)
	es.setup(field, 2000)
	es.render_enabled = false
	for k in n:
		es.spawn(rng.randi_range(0, 2), Vector2(rng.randf_range(-900, 900), rng.randf_range(-900, 900)))
	es.target = Vector2.ZERO
	es.rebuild_hash()
	return es


func _ids(es: EnemySystem) -> PackedInt32Array:
	var out := PackedInt32Array()
	for k in es.n_active:
		out.append(es.active[k])
	return out


func test_hash_candidates_cover_everything_once() -> void:
	var es := _make(800, 1)
	var c := es.hash.candidates(Rect2(-2000, -2000, 4000, 4000))
	assert_eq(c.size(), 800, "every enemy appears exactly once")
	assert_same_set(c, _ids(es))


func test_query_circle_matches_brute_force() -> void:
	var es := _make(1000, 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for trial in 25:
		var c := Vector2(rng.randf_range(-700, 700), rng.randf_range(-700, 700))
		var r := rng.randf_range(20, 300)
		var expect := PackedInt32Array()
		for i in _ids(es):
			var rr := r + es.t_radius[es.etype[i]]
			if es.pos[i].distance_squared_to(c) <= rr * rr:
				expect.append(i)
		assert_same_set(es.query_circle(c, r), expect, "trial %d" % trial)


func test_query_arc_includes_inside_excludes_outside() -> void:
	var es := _make(1000, 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for trial in 20:
		var c := Vector2(rng.randf_range(-500, 500), rng.randf_range(-500, 500))
		var dir := Vector2.from_angle(rng.randf() * TAU)
		var r := rng.randf_range(80, 260)
		var half := rng.randf_range(0.3, 1.6)
		var got := es.query_arc(c, r, dir, half)
		for i in _ids(es):
			var d := es.pos[i] - c
			var rad := es.t_radius[es.etype[i]]
			var inside := d.length() <= r and d.length() > 1.0 and absf(dir.angle_to(d)) <= half
			var far := d.length() > r + rad + 0.5
			if inside:
				assert_true(i in got, "trial %d: enemy inside the arc was missed" % trial)
			if far:
				assert_false(i in got, "trial %d: enemy beyond reach was hit" % trial)
		# behind the swing must not be hit (unless overlapping the hunter)
		for i in got:
			var d := es.pos[i] - c
			if d.length() > es.t_radius[es.etype[i]] + 6.0:
				assert_lt(absf(dir.angle_to(d)), half + 0.6, "hit something well outside the arc")


func test_query_line_matches_capsule() -> void:
	var es := _make(1000, 4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for trial in 20:
		var a := Vector2(rng.randf_range(-600, 600), rng.randf_range(-600, 600))
		var b := a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(50, 500)
		var w := rng.randf_range(10, 60)
		var expect := PackedInt32Array()
		for i in _ids(es):
			if Geom.seg_dist(es.pos[i], a, b) <= w + es.t_radius[es.etype[i]]:
				expect.append(i)
		assert_same_set(es.query_line(a, b, w), expect, "trial %d" % trial)


func test_count_and_contact() -> void:
	var field := FlowField.new(Rect2(-3000, -3000, 6000, 6000), 40.0, 84)
	var es := EnemySystem.new()
	root.add_child(es)
	es.setup(field, 100)
	es.render_enabled = false
	es.spawn(EnemySystem.T_GRUNT, Vector2(10, 0))
	es.spawn(EnemySystem.T_BRUTE, Vector2(-20, 0))
	es.spawn(EnemySystem.T_GRUNT, Vector2(500, 0))
	es.rebuild_hash()
	assert_eq(es.count_in_circle(Vector2.ZERO, 50), 2)
	assert_eq(es.contact_damage(Vector2.ZERO, 15.0), es.t_contact[EnemySystem.T_BRUTE], "contact uses the strongest touching enemy")
