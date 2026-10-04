extends TestCase
## XP curve, level-up queueing, upgrade pool rolls and application.


func test_xp_curve_is_monotonic() -> void:
	var p := Progression.new()
	p.setup()
	for l in range(1, 80):
		assert_true(p.xp_to_next(l + 1) >= p.xp_to_next(l), "level %d" % l)
	assert_gt(p.xp_to_next(1), 0.0)


func test_level_ups_queue() -> void:
	var p := Progression.new()
	p.setup()
	var gained := p.add_xp(p.total_xp_for(5))
	assert_eq(gained, 4)
	assert_eq(p.level, 5)
	assert_eq(p.pending, 4)
	for k in 4:
		assert_true(p.take_pending())
	assert_false(p.take_pending(), "queue drained")
	p.add_xp(1)
	assert_eq(p.level, 5, "1 xp doesn't level")
	assert_gt(p.progress(), 0.0)


func _pool() -> Array:
	var h := FakeHunt.make(root)
	var gs := GreatSword.new()
	gs.setup(h, h.player)
	h.player.weapons = [gs]
	var pool := UpgradePool.new()
	pool.setup(h, h.player, gs)
	return [h, gs, pool]


func test_roll_returns_distinct_options() -> void:
	var pool: UpgradePool = _pool()[2]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for trial in 20:
		var opts := pool.roll(rng)
		assert_eq(opts.size(), 3)
		var ids := {}
		for o in opts:
			ids[String(o["id"])] = true
		assert_eq(ids.size(), 3, "distinct cards")


func test_apply_passive_sub_and_weapon() -> void:
	var trio := _pool()
	var h: FakeHunt = trio[0]
	var gs: GreatSword = trio[1]
	var pool: UpgradePool = trio[2]
	pool.apply({"kind": "passive", "id": "p_damage"})
	assert_near(h.player.dmg_mult, 1.12, 0.0001)
	var hp_before := h.player.max_hp
	pool.apply({"kind": "passive", "id": "p_hp"})
	assert_near(h.player.max_hp, hp_before + 25.0, 0.0001)
	pool.apply({"kind": "sub", "id": "orbit_shards"})
	assert_eq(pool.subs.size(), 1)
	assert_eq(h.player.weapons.size(), 2, "sub-weapon joins the loadout")
	pool.apply({"kind": "sub", "id": "orbit_shards"})
	assert_eq(pool.subs[0].level, 2)
	pool.apply({"kind": "weapon", "id": "gs_retain"})
	assert_eq(gs.up("gs_retain"), 1)
	for o in pool.all_options():
		assert_false(String(o["id"]) == "gs_retain", "maxed upgrade no longer offered")


func test_heal_fallback_when_everything_is_maxed() -> void:
	var trio := _pool()
	var pool: UpgradePool = trio[2]
	var guard := 0
	while not pool.all_options().is_empty() and guard < 500:
		pool.apply(pool.all_options()[0])
		guard += 1
	var rng := RandomNumberGenerator.new()
	var opts := pool.roll(rng)
	assert_eq(opts.size(), 1)
	assert_eq(String(opts[0]["kind"]), "heal")
	assert_eq(pool.subs.size(), 3, "all three sub-weapons acquired")


func test_sub_weapons_fire() -> void:
	var h := FakeHunt.make(root)
	for sid in UpgradePool.SUB_IDS:
		var w := UpgradePool.make_sub(sid)
		w.setup(h, h.player)
		h.hits.clear()
		for k in 240:
			h.player.move_step(1.0 / 60.0, Vector2.RIGHT)
			w.update(1.0 / 60.0, Vector2.RIGHT)
		assert_gt(h.hits.size(), 0.0, "%s dealt hits" % sid)
