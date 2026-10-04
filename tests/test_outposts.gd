extends TestCase
## Outposts capture/decay/effects, Musou gauge, and a full Musou blast inside a real Hunt.


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


func test_musou_gauge() -> void:
	var g := MusouGauge.new()
	g.setup()
	assert_false(g.trigger(), "can't fire empty")
	g.add(g.max_value * 0.5)
	assert_near(g.fraction(), 0.5)
	g.add(g.max_value, 2.0)
	assert_true(g.is_full())
	assert_true(g.trigger())
	assert_eq(g.value, 0.0)
	assert_true(g.is_locked(), "recharge lock after firing")
	g.add(50.0)
	assert_eq(g.value, 0.0, "can't refill while locked")
	g.tick(g.recharge_lock + 0.1)
	g.add(50.0)
	assert_eq(g.value, 50.0)


func test_musou_blast_clears_the_screen() -> void:
	var hunt := Hunt.new()
	hunt.config = {"mode": "smoke", "weapon": "great_sword", "bot": false, "god": true, "seed": 5, "arrive_time": 1e9}
	root.add_child(hunt)
	hunt.spawner.enabled = false
	hunt.fill_enemies(500)
	hunt._process(1.0 / 60.0)
	var vr := hunt.view_rect_world()
	var in_view := 0
	for k in hunt.enemies.n_active:
		if vr.has_point(hunt.enemies.pos[hunt.enemies.active[k]]):
			in_view += 1
	assert_gt(in_view, 50.0, "plenty of enemies on screen")
	var kos_before := hunt.kos
	hunt.musou.value = hunt.musou.max_value
	hunt.request_musou()
	assert_gt(hunt.musou_timer, 0.0, "musou started")
	assert_true(hunt.player.invuln, "invulnerable during musou")
	var frames := 0
	while hunt.musou_blasts == 0 and frames < 300:
		hunt._process(1.0 / 60.0)
		frames += 1
	assert_eq(hunt.musou_blasts, 1, "blast fired")
	assert_true(hunt.kos - kos_before >= in_view - 10, "on-screen enemies were KO'd (%d vs %d)" % [hunt.kos - kos_before, in_view])
	var vr2 := hunt.view_rect_world()
	var left := 0
	for k in hunt.enemies.n_active:
		if vr2.grow(-120).has_point(hunt.enemies.pos[hunt.enemies.active[k]]):
			left += 1
	assert_lt(left, 5.0, "screen is clear")
	assert_false(hunt.player.invuln, "vulnerable again")
	assert_lt(hunt.musou.value, 1.0, "a blast doesn't refill its own gauge")
	Engine.time_scale = 1.0
