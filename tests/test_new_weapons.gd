extends TestCase
## Bulwark, Hand Cannon, Twin Fangs, Assault Rifle (movement mechanics + gesture moves) and the
## Great Sword / Dual Blades gesture moves, against a recording FakeHunt.

const DT := 1.0 / 60.0


func _make(w: Weapon) -> FakeHunt:
	var h := FakeHunt.make(root)
	w.setup(h, h.player)
	h.player.weapons = [w]
	return h


func _run(w: Weapon, seconds: float, move: Vector2) -> void:
	for k in int(round(seconds / DT)):
		w.update(DT, move)


func _ctx(dir: Vector2 = Vector2.RIGHT, aimed: bool = true, hold_time: float = 0.0) -> Dictionary:
	return {"kind": "swipe", "dir": dir, "aimed": aimed, "target": Vector2(150, 0), "hold_time": hold_time, "power": 1.0, "perfect": false}


func _def(weapon_id: String, move_id: String) -> Dictionary:
	for d in MoveSet.pool_defs(weapon_id):
		if String(d["id"]) == move_id:
			return d
	return {}


# ------------------------------------------------------------------ Great Sword / Dual Blades

func test_gs_aimed_unleash_releases_without_moving() -> void:
	var gs := GreatSword.new()
	var h := _make(gs)
	_run(gs, 1.6, Vector2.ZERO)
	h.hits.clear()
	assert_true(gs.perform_move("gs_aimed", _def("great_sword", "gs_aimed"), _ctx(Vector2.UP)))
	assert_eq(gs.releases, 1)
	assert_eq(gs.last_release_level, 3)
	assert_true(gs.last_release_dir.is_equal_approx(Vector2.UP), "toward the swipe")
	assert_eq(gs.charge_level(), 0, "charge spent")
	_run(gs, 0.5, Vector2.ZERO)
	assert_eq(gs.charge_level(), 1, "still planted: charging again")


func test_gs_tackle_keeps_charge() -> void:
	var gs := GreatSword.new()
	_make(gs)
	_run(gs, 0.6, Vector2.ZERO)
	var before := gs.charge_time
	assert_true(gs.perform_move("gs_tackle", _def("great_sword", "gs_tackle"), _ctx()))
	assert_gt(gs.charge_time, before, "tackle adds charge")
	assert_true(gs.player.is_dashing())


func test_gs_whirl_needs_charge() -> void:
	var gs := GreatSword.new()
	var h := _make(gs)
	var d := _def("great_sword", "gs_whirl")
	assert_false(gs.perform_move("gs_whirl", d, _ctx()), "no charge, no whirlwind")
	_run(gs, 1.0, Vector2.ZERO)
	h.hits.clear()
	assert_true(gs.perform_move("gs_whirl", d, _ctx()))
	assert_eq(h.hits_of("circle").size(), 1, "a full circle")


func test_db_aimed_dash_spends_momentum() -> void:
	var db := DualBlades.new()
	var h := _make(db)
	_run(db, 2.2, Vector2.RIGHT)
	h.hits.clear()
	assert_true(db.perform_move("db_aimed_dash", _def("dual_blades", "db_aimed_dash"), _ctx(Vector2.DOWN)))
	assert_lt(db.momentum, 1.0, "momentum spent")
	var lines := h.hits_of("line")
	assert_eq(lines.size(), 1)
	assert_gt(((lines[0]["b"] as Vector2) - (lines[0]["a"] as Vector2)).y, 0.0, "cut goes down the swipe")


func test_db_vortex_cashes_in_momentum() -> void:
	var db := DualBlades.new()
	var h := _make(db)
	var d := _def("dual_blades", "db_vortex")
	assert_true(db.perform_move("db_vortex", d, _ctx()))
	var weak := float(h.hits_of("circle")[0]["dmg"])
	_run(db, 2.2, Vector2.RIGHT)
	h.hits.clear()
	assert_true(db.perform_move("db_vortex", d, _ctx()))
	var big := h.hits_of("circle")
	assert_gt(float(big[big.size() - 1]["dmg"]), weak * 2.0, "full momentum hits much harder")
	assert_eq(db.momentum, 0.0)


# ------------------------------------------------------------------ Bulwark

func test_shield_blocks_frontal_hits() -> void:
	var sh := SwordShield.new()
	var h := _make(sh)
	h.player.facing = Vector2.RIGHT
	sh.update(DT, Vector2.ZERO)
	h.target = Vector2.INF  # keep the shield from turning
	assert_true(sh.guarding, "standing still raises the shield")
	var front := sh.modify_incoming(10.0, h.player.position + Vector2(50, 0))
	assert_near(front, 10.0 * sh.guard_mult, 0.001, "frontal hit blocked")
	assert_gt(sh.energy, 0.0, "block charges the bash")
	assert_eq(sh.modify_incoming(10.0, h.player.position + Vector2(-50, 0)), 10.0, "hit from behind gets through")
	sh.update(DT, Vector2.RIGHT)
	assert_false(sh.guarding, "running lowers the shield")
	assert_eq(sh.modify_incoming(10.0, h.player.position + Vector2(50, 0)), 10.0)
	sh.update(DT, Vector2.RIGHT * 0.5)
	assert_true(sh.guarding, "walking keeps it up")


func test_shield_bash_fires_when_full() -> void:
	var sh := SwordShield.new()
	var h := _make(sh)
	h.target = Vector2.INF
	h.player.facing = Vector2.RIGHT
	sh.update(DT, Vector2.ZERO)
	var guard := 0
	while sh.energy < sh.energy_max() and guard < 200:
		sh.modify_incoming(10.0, h.player.position + Vector2(40, 0))
		guard += 1
	sh.update(DT, Vector2.ZERO)
	assert_eq(sh.bashes, 1, "counter-bash")
	assert_eq(sh.energy, 0.0)


func test_shield_guard_counter() -> void:
	var sh := SwordShield.new()
	var h := _make(sh)
	h.target = Vector2.INF
	assert_true(sh.perform_move("sh_counter", _def("sword_shield", "sh_counter"), _ctx()))
	assert_eq(sh.modify_incoming(30.0, h.player.position + Vector2(0, -60)), 0.0, "countered hits deal nothing")
	h.hits.clear()
	sh.update(DT, Vector2.ZERO)
	assert_eq(sh.counters, 1)
	var arcs := h.hits_of("arc")
	var big := false
	for a in arcs:
		if (a["dir"] as Vector2).dot(Vector2.UP) > 0.9 and (int(a["flags"]) & HuntContext.HIT_BIG) != 0:
			big = true
	assert_true(big, "counter strikes back toward the attacker")
	_run(sh, 0.5, Vector2.ZERO)
	assert_gt(sh.modify_incoming(30.0, h.player.position + Vector2(0, -60)), 0.0, "window over")


func test_shield_wall_hold() -> void:
	var sh := SwordShield.new()
	var h := _make(sh)
	var d := _def("sword_shield", "sh_wall")
	sh.begin_hold("sh_wall", d, _ctx())
	assert_lt(sh.modify_incoming(10.0, h.player.position + Vector2(-50, 0)), 10.0, "wall blocks from behind")
	h.hits.clear()
	assert_true(sh.perform_move("sh_wall", d, _ctx(Vector2.RIGHT, true, 1.0)))
	assert_false(sh.wall_holding, "released")
	var c := h.hits_of("circle")
	assert_gt(float(c[0]["r"]), float(d["radius"]), "longer hold, bigger blast")


# ------------------------------------------------------------------ Hand Cannon

func test_pistol_steady_aim() -> void:
	var ps := Pistol.new()
	var h := _make(ps)
	_run(ps, 0.6, Vector2.RIGHT)
	var hip := h.hits_of("shot")
	assert_gt(hip.size(), 0.0, "hip-fires while moving")
	assert_eq(ps.steady, 0.0)
	var hip_pierce := int(hip[0]["pierce"])
	h.hits.clear()
	_run(ps, 1.5, Vector2.ZERO)
	assert_near(ps.steady, 1.0, 0.001, "standing still steadies")
	var st := h.hits_of("shot")
	var last: Dictionary = st[st.size() - 1]
	assert_gt(int(last["pierce"]), hip_pierce, "steady shots pierce more")
	assert_gt(float(last["dmg"]), float(hip[0]["dmg"]), "and hit harder")
	assert_true(((last["dir"] as Vector2) - Vector2.RIGHT).length() < 0.01, "aimed at the target with no spread")


func test_pistol_no_target_no_fire() -> void:
	var ps := Pistol.new()
	var h := _make(ps)
	h.target = Vector2.INF
	_run(ps, 1.0, Vector2.ZERO)
	assert_eq(ps.shots, 0)


func test_pistol_moves() -> void:
	var ps := Pistol.new()
	var h := _make(ps)
	assert_true(ps.perform_move("ps_fan", _def("pistol", "ps_fan"), _ctx()))
	assert_eq(h.hits_of("shot").size(), int(_def("pistol", "ps_fan")["shots"]))
	h.hits.clear()
	assert_true(ps.perform_move("ps_ricochet", _def("pistol", "ps_ricochet"), _ctx()))
	assert_eq(h.hits_of("line").size(), int(_def("pistol", "ps_ricochet")["bounces"]), "one segment per bounce")
	assert_true(ps.perform_move("ps_deadeye", _def("pistol", "ps_deadeye"), _ctx()))
	assert_eq(ps.steady, 1.0)
	h.hits.clear()
	ps.update(DT, Vector2.ZERO)
	assert_gt(float(h.hits_of("shot")[0]["dmg"]), float(Tuning.f("weapons.pistol.steady.damage")) * 1.5, "dead eye doubles damage")


# ------------------------------------------------------------------ Twin Fangs

func test_dual_pistols_fire_to_the_sides() -> void:
	var dp := DualPistols.new()
	var h := _make(dp)
	h.target = Vector2(0, -150)  # a foe off the left flank while running right
	_run(dp, 0.5, Vector2.RIGHT)
	var shots := h.hits_of("shot")
	assert_gt(shots.size(), 0.0)
	for s in shots:
		assert_lt(absf((s["dir"] as Vector2).dot(Vector2.RIGHT)), 0.5, "fired sideways, not ahead")
	h.target = Vector2(150, 0)  # dead ahead: outside both side cones
	h.hits.clear()
	_run(dp, 0.5, Vector2.RIGHT)
	assert_eq(h.hits_of("shot").size(), 0, "nothing on the flanks, no side fire")


func test_dual_pistols_snap_turn_spin() -> void:
	var dp := DualPistols.new()
	var h := _make(dp)
	_run(dp, 0.5, Vector2.RIGHT)
	dp.update(DT, Vector2.LEFT)
	assert_eq(dp.spins, 1, "snap-turn fires a ring")
	assert_gt(h.hits_of("shot").size(), int(Tuning.f("weapons.dual_pistols.spin.shots")) - 1.0)
	var dp2 := DualPistols.new()
	_make(dp2)
	var a := 0.0
	for k in 120:
		a += 0.05
		dp2.update(DT, Vector2.from_angle(a))
	assert_eq(dp2.spins, 0, "circling never spins")


func test_dual_pistols_kata() -> void:
	var dp := DualPistols.new()
	var h := _make(dp)
	h.target = Vector2.INF
	assert_true(dp.perform_move("dp_kata", _def("dual_pistols", "dp_kata"), _ctx()))
	_run(dp, 1.0, Vector2.ZERO)
	assert_gt(h.hits_of("shot").size(), 40.0, "spinning fire for the duration")
	assert_false(dp.perform_move("dp_point", _def("dual_pistols", "dp_point"), _ctx()), "point blank needs a target")


# ------------------------------------------------------------------ Assault Rifle

func test_rifle_spins_up() -> void:
	var ar := AssaultRifle.new()
	var h := _make(ar)
	_run(ar, 1.0, Vector2.ZERO)
	var early := ar.rounds
	assert_gt(early, 3.0)
	_run(ar, 3.0, Vector2.ZERO)
	assert_near(ar.spin, 1.0, 0.001)
	var before := ar.rounds
	_run(ar, 1.0, Vector2.ZERO)
	assert_gt(ar.rounds - before, early * 1.5, "fires much faster once spun up")
	h.target = Vector2.INF
	_run(ar, 2.0, Vector2.ZERO)
	assert_eq(ar.spin, 0.0, "spins down with nothing to shoot")


func test_rifle_grenade_and_airstrike() -> void:
	var ar := AssaultRifle.new()
	var h := _make(ar)
	h.target = Vector2.INF
	assert_true(ar.perform_move("ar_grenade", _def("assault_rifle", "ar_grenade"), _ctx()))
	assert_eq(h.hits_of("circle").size(), 0, "fused")
	_run(ar, 0.6, Vector2.ZERO)
	assert_eq(ar.explosions, 1, "boom")
	var gc: Vector2 = h.hits_of("circle")[0]["c"]
	assert_gt(gc.x, 200.0, "landed along the swipe")
	assert_true(ar.perform_move("ar_airstrike", _def("assault_rifle", "ar_airstrike"), _ctx()))
	_run(ar, 1.5, Vector2.ZERO)
	assert_eq(ar.explosions, 1 + int(_def("assault_rifle", "ar_airstrike")["count"]))


func test_every_weapon_runs_every_move() -> void:
	for w in GameState.WEAPONS:
		for d in MoveSet.pool_defs(w):
			var weapon := WeaponFactory.make(w)
			var h := _make(weapon)
			_run(weapon, 1.6, Vector2.ZERO)  # charge / steady / spin up
			_run(weapon, 0.6, Vector2.RIGHT)  # momentum
			weapon.perform_move(String(d["id"]), d, _ctx())
			_run(weapon, 2.0, Vector2.ZERO)  # timed effects play out
			assert_gt(h.hits.size(), 0.0, "%s/%s did something" % [w, d["id"]])
