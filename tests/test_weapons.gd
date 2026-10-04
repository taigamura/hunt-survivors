extends TestCase
## Great Sword charge/release and Dual Blades momentum/dash-cut, against a recording FakeHunt.

const DT := 1.0 / 60.0


func _run(w: Weapon, seconds: float, move: Vector2) -> void:
	var frames := int(round(seconds / DT))
	for k in frames:
		w.update(DT, move)


func _gs() -> Array:
	var h := FakeHunt.make(root)
	var gs := GreatSword.new()
	gs.setup(h, h.player)
	h.player.weapons = [gs]
	return [h, gs]


func test_great_sword_charge_levels() -> void:
	var gs: GreatSword = _gs()[1]
	_run(gs, 0.2, Vector2.ZERO)
	assert_eq(gs.charge_level(), 0)
	_run(gs, 0.3, Vector2.ZERO)  # 0.5s
	assert_eq(gs.charge_level(), 1)
	_run(gs, 0.5, Vector2.ZERO)  # 1.0s
	assert_eq(gs.charge_level(), 2)
	_run(gs, 0.6, Vector2.ZERO)  # 1.6s
	assert_eq(gs.charge_level(), 3)


func test_great_sword_releases_on_move() -> void:
	var pair := _gs()
	var h: FakeHunt = pair[0]
	var gs: GreatSword = pair[1]
	_run(gs, 1.6, Vector2.ZERO)
	h.hits.clear()
	gs.update(DT, Vector2.UP)
	assert_eq(gs.releases, 1)
	assert_eq(gs.last_release_level, 3)
	assert_true(gs.last_release_dir.is_equal_approx(Vector2.UP), "released toward movement")
	var arcs := h.hits_of("arc")
	assert_gt(arcs.size(), 0.0, "an arc was swung")
	var big: Dictionary = arcs[0]
	assert_near(float(big["r"]), float(gs.levels[2]["radius"]), 0.01, "level-3 reach")
	assert_true((big["dir"] as Vector2).is_equal_approx(Vector2.UP))
	assert_eq(gs.charge_level(), 0, "charge spent")
	assert_gt(h.player.iframes, 0.0, "release grants brief invulnerability")


func test_great_sword_no_release_without_charge() -> void:
	var gs: GreatSword = _gs()[1]
	_run(gs, 0.2, Vector2.ZERO)
	gs.update(DT, Vector2.RIGHT)
	assert_eq(gs.releases, 0)


func test_great_sword_swipes_while_moving_and_braces_when_planted() -> void:
	var pair := _gs()
	var h: FakeHunt = pair[0]
	var gs: GreatSword = pair[1]
	_run(gs, 2.6, Vector2.RIGHT)
	assert_true(gs.swipes >= 2, "weak swipe ticks while moving (%d)" % gs.swipes)
	assert_eq(gs.damage_taken_mult(), 1.0, "no guard while moving")
	h.hits.clear()
	_run(gs, 0.5, Vector2.ZERO)
	assert_lt(gs.damage_taken_mult(), 1.0, "planted stance reduces damage")
	assert_gt(h.hits_of("circle").size(), 0.0, "reaching a charge level shoves the crowd back")


func test_great_sword_retain_upgrade() -> void:
	var gs: GreatSword = _gs()[1]
	gs.apply_upgrade("gs_retain")
	_run(gs, 1.0, Vector2.ZERO)
	var before := gs.charge_time
	gs.update(DT, Vector2.RIGHT)
	assert_near(gs.charge_time, before * 0.5, 0.02, "keeps 50% of the charge")


func _db() -> Array:
	var h := FakeHunt.make(root)
	var db := DualBlades.new()
	db.setup(h, h.player)
	h.player.weapons = [db]
	return [h, db]


func test_dual_blades_momentum_builds_and_decays() -> void:
	var db: DualBlades = _db()[1]
	_run(db, db.build_time + 0.1, Vector2.RIGHT)
	assert_near(db.momentum, 1.0, 0.001, "full momentum after build_time")
	assert_gt(db.player.weapon_speed_mult, 1.0, "momentum speeds you up")
	_run(db, 1.0, Vector2.ZERO)
	assert_lt(db.momentum, 0.05, "stopping bleeds momentum fast")


func test_dual_blades_low_deflection_does_not_build() -> void:
	var db: DualBlades = _db()[1]
	_run(db, 3.0, Vector2.RIGHT * 0.5)
	assert_eq(db.momentum, 0.0)


func test_dual_blades_whirl_scales_with_momentum() -> void:
	var db: DualBlades = _db()[1]
	_run(db, 0.5, Vector2.ZERO)
	var r0 := db.whirl_radius()
	_run(db, 2.2, Vector2.RIGHT)
	assert_gt(db.whirl_radius(), r0 + 20.0, "bigger whirl at speed")
	assert_gt(db.whirl_ticks, 3.0)


func test_dual_blades_dash_cut_on_reversal() -> void:
	var pair := _db()
	var h: FakeHunt = pair[0]
	var db: DualBlades = pair[1]
	_run(db, 2.2, Vector2.RIGHT)
	h.hits.clear()
	db.update(DT, Vector2.LEFT)
	assert_eq(db.dash_cuts, 1)
	var lines := h.hits_of("line")
	assert_eq(lines.size(), 1)
	var seg: Dictionary = lines[0]
	assert_lt(((seg["b"] as Vector2) - (seg["a"] as Vector2)).x, 0.0, "cut goes the new direction")
	assert_true(db.player.is_dashing())


func test_dual_blades_reversal_through_center_counts() -> void:
	var db: DualBlades = _db()[1]
	_run(db, 2.2, Vector2.RIGHT)
	_run(db, 0.08, Vector2.ZERO)  # thumb passes through the dead zone
	db.update(DT, Vector2.LEFT)
	assert_eq(db.dash_cuts, 1)


func test_dual_blades_no_dash_at_low_momentum_or_gentle_turns() -> void:
	var db: DualBlades = _db()[1]
	_run(db, 0.4, Vector2.RIGHT)
	db.update(DT, Vector2.LEFT)
	assert_eq(db.dash_cuts, 0, "not enough momentum")
	var db2: DualBlades = _db()[1]
	_run(db2, 2.2, Vector2.RIGHT)
	# sweep the stick around a circle (no sharp reversal)
	var a := 0.0
	for k in 120:
		a += 0.05
		db2.update(DT, Vector2.from_angle(a))
	assert_eq(db2.dash_cuts, 0, "circling never dash-cuts")


func test_dual_blades_afterimages_at_full_momentum() -> void:
	var db: DualBlades = _db()[1]
	_run(db, 1.0, Vector2.RIGHT)
	assert_eq(db.trail.size(), 0, "no afterimages yet")
	_run(db, 1.5, Vector2.RIGHT)
	assert_gt(db.trail.size(), 0.0, "afterimages at full momentum")


func test_input_curve() -> void:
	assert_eq(Hunt.shape_input(Vector2(0.05, 0), 0.12, 0.6), Vector2.ZERO, "inside dead zone")
	assert_near(Hunt.shape_input(Vector2(0.6, 0), 0.12, 0.6).length(), 1.0, 0.001, "full speed at 60%")
	assert_near(Hunt.shape_input(Vector2(1.0, 0), 0.12, 0.6).length(), 1.0, 0.001, "clamped")
	var mid := Hunt.shape_input(Vector2(0, 0.36), 0.12, 0.6)
	assert_near(mid.length(), 0.5, 0.001, "linear in between")
	assert_true(mid.normalized().is_equal_approx(Vector2.DOWN), "direction preserved")
