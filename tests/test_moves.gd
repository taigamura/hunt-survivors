extends TestCase
## MoveSet bindings/cooldowns/levels, loadout sanitizing, gesture level-up cards, the perfect
## counter and hitscan rounds inside a real Hunt.

const DT := 1.0 / 60.0


func _with(weapon: Weapon, loadout: Dictionary = {}) -> Array:
	var h := FakeHunt.make(root)
	weapon.setup(h, h.player)
	h.player.weapons = [weapon]
	var ms := MoveSet.new()
	ms.setup(weapon, h.player, loadout)
	return [h, weapon, ms]


func _ctx(kind: String, dir: Vector2 = Vector2.RIGHT, aimed: bool = true) -> Dictionary:
	return {"kind": kind, "dir": dir, "aimed": aimed, "target": Vector2(150, 0), "hold_time": 0.0, "power": 1.0, "perfect": false}


func test_sanitize_loadout() -> void:
	var d := MoveSet.default_loadout("great_sword")
	assert_eq(MoveSet.sanitize_loadout("great_sword", {}), d, "empty -> defaults")
	var junk := MoveSet.sanitize_loadout("great_sword", {"tap": "nope", "swipe": "gs_tackle", "hold": "gs_tackle", "circle": "gs_whirl"})
	assert_eq(String(junk["swipe"]), "gs_tackle", "valid choice kept")
	assert_false(junk.has("circle"), "shapes are not part of the loadout")
	var seen := {}
	for k: String in junk:
		assert_false(seen.has(junk[k]), "no move bound twice (%s)" % junk[k])
		seen[junk[k]] = true
	assert_eq(junk.size(), 3, "every start gesture bound")
	for w in GameState.WEAPONS:
		var dl := MoveSet.default_loadout(w)
		assert_eq(MoveSet.sanitize_loadout(w, dl), dl, "%s default loadout is valid" % w)


func test_trigger_cooldown_and_unbound() -> void:
	var trio := _with(GreatSword.new())
	var ms: MoveSet = trio[2]
	assert_eq(ms.trigger(_ctx("tap")), "ok", "tackle fires")
	assert_eq(ms.trigger(_ctx("tap")), "cooldown", "then cools down")
	assert_gt(ms.cooldown_left("gs_tackle"), 0.0)
	ms.tick(5.0)
	assert_eq(ms.trigger(_ctx("tap")), "ok", "ready again")
	assert_eq(ms.trigger(_ctx("circle")), "unbound", "shapes start locked")
	assert_eq(ms.performed, 2)


func test_failed_move_spends_no_cooldown() -> void:
	var trio := _with(GreatSword.new(), {"tap": "gs_whirl"})
	var ms: MoveSet = trio[2]
	assert_eq(ms.trigger(_ctx("tap")), "failed", "whirlwind needs charge")
	assert_eq(ms.cooldown_left("gs_whirl"), 0.0)


func test_levels_scale_power_and_cooldown() -> void:
	var trio := _with(GreatSword.new())
	var ms: MoveSet = trio[2]
	var cd1 := ms.cooldown_for("gs_tackle")
	var p1 := ms.power("gs_tackle")
	ms.upgrade("gs_tackle")
	assert_eq(ms.level_of("gs_tackle"), 2)
	assert_lt(ms.cooldown_for("gs_tackle"), cd1, "shorter cooldown")
	assert_gt(ms.power("gs_tackle"), p1, "more damage")
	ms.upgrade("gs_tackle")
	ms.upgrade("gs_tackle")
	assert_eq(ms.level_of("gs_tackle"), ms.max_level, "capped")
	assert_false("gs_tackle" in ms.upgradable_moves())


func test_shared_moves() -> void:
	var trio := _with(Pistol.new(), {"tap": "roll", "swipe": "lightning"})
	var h: FakeHunt = trio[0]
	var ms: MoveSet = trio[2]
	assert_eq(ms.trigger(_ctx("tap", Vector2.UP)), "ok")
	assert_true(h.player.is_dashing(), "roll dashes")
	assert_gt(h.player.iframes, 0.0, "roll is invulnerable")
	h.hits.clear()
	h.subs["thunder_call"] = 3
	assert_eq(ms.trigger(_ctx("swipe")), "ok")
	var c := h.hits_of("circle")
	assert_eq(c.size(), 1, "one lightning strike")
	var base := float(ms.def_of("lightning")["damage"])
	assert_gt(float(c[0]["dmg"]), base, "Thunder Call levels boost it")


func test_gesture_cards_unlock_shapes() -> void:
	var trio := _with(GreatSword.new())
	var h: FakeHunt = trio[0]
	var gs: GreatSword = trio[1]
	var ms: MoveSet = trio[2]
	var pool := UpgradePool.new()
	pool.setup(h, h.player, gs, ms)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var early := pool.all_options(rng, 1)
	for o in early:
		assert_false(String(o["kind"]) == "gesture", "no shape cards before shape_unlock_min_level")
	var card := {}
	for o in pool.all_options(rng, 10):
		if String(o["kind"]) == "gesture":
			card = o
	assert_false(card.is_empty(), "a shape card is offered")
	pool.apply(card)
	assert_eq(ms.move_for(String(card["gesture"])), String(card["move"]), "shape bound to the move")
	assert_eq(ms.trigger(_ctx(String(card["gesture"]))) != "unbound", true, "and usable")
	var mv := {}
	for o in pool.all_options(rng, 10):
		if String(o["kind"]) == "move" and String(o["id"]) == "gs_tackle":
			mv = o
	assert_false(mv.is_empty(), "bound moves can be levelled")
	pool.apply(mv)
	assert_eq(ms.level_of("gs_tackle"), 2)


func _hunt(weapon: String) -> Hunt:
	var hunt := Hunt.new()
	hunt.config = {"mode": "smoke", "weapon": weapon, "bot": false, "god": false, "seed": 5, "arrive_time": 1e9, "loadout": MoveSet.default_loadout(weapon)}
	root.add_child(hunt)
	hunt.spawner.enabled = false
	return hunt


func test_perfect_counter() -> void:
	var hunt := _hunt("great_sword")
	hunt.spawn_monster()
	var m := hunt.monster
	m.position = hunt.player.position + Vector2(260, 0)
	m.facing = Vector2.LEFT
	m.rotation = PI
	m._begin_telegraph("charge", Vector2.LEFT)
	# too early: not a perfect
	assert_false(m.counter_window(hunt.player.position, hunt.player.radius + 40.0, 0.3), "window not open yet")
	m.state_time = m.telegraph_time - 0.1
	assert_true(m.counter_window(hunt.player.position, hunt.player.radius + 40.0, 0.3), "window open near the end")
	assert_eq(hunt.perform_gesture({"kind": "tap"}), "ok")
	assert_eq(hunt.perfects, 1, "perfect counter")
	assert_eq(m.state, Ironhorn.State.RECOVER, "attack cancelled into recovery")
	assert_gt(hunt.player.iframes, 0.5, "invulnerable through the hit")
	# out of the danger zone it's just a normal move
	m._begin_telegraph("charge", Vector2.UP)
	m.state_time = m.telegraph_time - 0.1
	hunt.moves.tick(10.0)
	hunt.player.position = m.position + Vector2(0, 900)
	assert_eq(hunt.perform_gesture({"kind": "tap"}), "ok")
	assert_eq(hunt.perfects, 1, "not threatened -> no perfect")
	Engine.time_scale = 1.0


func test_hunt_gestures_and_loadout() -> void:
	var hunt := _hunt("dual_blades")
	assert_eq(hunt.moves.move_for("swipe"), "db_aimed_dash", "loadout applied")
	var before := hunt.player.position
	assert_eq(hunt.perform_gesture({"kind": "swipe", "dir": Vector2.UP}), "ok")
	for k in 12:
		hunt._process(DT)
	assert_lt(hunt.player.position.y, before.y - 100.0, "dash cut went up the swipe")
	assert_eq(hunt.perform_gesture({"kind": "triangle"}), "unbound")
	assert_eq(hunt.perform_gesture({"kind": ""}), "unknown")
	Engine.time_scale = 1.0


func test_shoot_pierce_and_monster_blocks() -> void:
	var hunt := _hunt("pistol")
	hunt.enemies.clear_all()
	var a := hunt.player.position
	var ids: Array[int] = []
	for k in 5:
		ids.append(hunt.enemies.spawn(EnemySystem.T_BRUTE, a + Vector2(100.0 + 60.0 * k, 0)))
	hunt.enemies.rebuild_hash()
	var end := hunt.shoot(a, Vector2.RIGHT, 600.0, 6.0, 1.0, 0.0, 2)
	var hit := 0
	for i in ids:
		if hunt.enemies.hp[i] < hunt.enemies.t_hp[EnemySystem.T_BRUTE] * hunt.enemies.hp_mult:
			hit += 1
	assert_eq(hit, 2, "pierce 2 hits exactly the two nearest")
	assert_lt(end.x, a.x + 200.0, "round stops at the last enemy it pierced")
	assert_true(hunt.enemies.hp[ids[0]] < hunt.enemies.hp[ids[4]], "nearest first")
	# the monster stops rounds
	hunt.enemies.clear_all()
	hunt.enemies.rebuild_hash()
	hunt.spawn_monster()
	hunt.monster.position = a + Vector2(400, 0)
	var hp0 := hunt.monster.hp
	var end2 := hunt.shoot(a, Vector2.RIGHT, 900.0, 6.0, 50.0, 0.0, 5)
	assert_lt(hunt.monster.hp, hp0, "monster hit")
	assert_lt(end2.x, a.x + 400.0, "stopped at the monster's edge")
	Engine.time_scale = 1.0
