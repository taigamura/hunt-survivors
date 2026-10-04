extends TestCase
## Ironhorn: part breaks change its moveset/damage, death, telegraph -> attack flow.

const DT := 1.0 / 60.0


func _setup() -> Array:
	var h := FakeHunt.make(root)
	var m := Ironhorn.new()
	h.add_child(m)
	m.setup(h, 1)
	m.position = Vector2(1000, 0)
	m.facing = Vector2.RIGHT
	m.rotation = 0.0
	h.player.position = Vector2(-2000, 0)
	return [h, m]


func _hit_part(m: Ironhorn, part: String, dmg: float) -> float:
	var at := m.part_world(part)
	return m.take_hit(Ironhorn.SHAPE_CIRCLE, at, at, 8.0, Vector2.ZERO, 0.0, dmg)


func test_horn_break_weakens_charge() -> void:
	var pair := _setup()
	var h: FakeHunt = pair[0]
	var m: Ironhorn = pair[1]
	var full_len := float(m.cfg["attacks"]["charge"]["distance"])
	var guard := 0
	while not m.is_broken("horns") and guard < 100:
		_hit_part(m, "horns", 100.0)
		guard += 1
	assert_true(m.is_broken("horns"))
	assert_eq(h.parts_broken, ["horns"] as Array[String])
	assert_eq(m.state, Ironhorn.State.STAGGER, "a break staggers it")
	assert_false(m.is_broken("tail"), "other parts untouched")
	m._begin_telegraph("charge", Vector2.LEFT)
	assert_lt(m.charge_len, full_len, "broken horns shorten the charge")


func test_tail_break_removes_sweep() -> void:
	var m: Ironhorn = _setup()[1]
	assert_true("sweep" in m.available_attacks(100.0))
	m.break_part("tail")
	assert_false("sweep" in m.available_attacks(100.0))
	assert_true("roar" in m.available_attacks(100.0))


func test_back_break_increases_damage_taken() -> void:
	var m: Ironhorn = _setup()[1]
	var before := m.hp
	m.apply_damage(100.0)
	assert_near(before - m.hp, 100.0)
	m.break_part("back")
	before = m.hp
	m.apply_damage(100.0)
	assert_near(before - m.hp, 125.0, 0.01, "+25% after the back breaks")


func test_hits_must_overlap() -> void:
	var m: Ironhorn = _setup()[1]
	var far := m.position + Vector2(0, 600)
	assert_eq(m.take_hit(Ironhorn.SHAPE_CIRCLE, far, far, 50.0, Vector2.ZERO, 0.0, 100.0), 0.0)
	assert_gt(m.take_hit(Ironhorn.SHAPE_CIRCLE, m.position, m.position, 10.0, Vector2.ZERO, 0.0, 100.0), 0.0)
	# an arc pointing away from it misses, pointing at it hits
	var c := m.position + Vector2(-400, 0)
	assert_eq(m.take_hit(Ironhorn.SHAPE_ARC, c, c, 250.0, Vector2.LEFT, 0.6, 50.0), 0.0)
	assert_gt(m.take_hit(Ironhorn.SHAPE_ARC, c, c, 250.0, Vector2.RIGHT, 0.6, 50.0), 0.0)


func test_death() -> void:
	var pair := _setup()
	var h: FakeHunt = pair[0]
	var m: Ironhorn = pair[1]
	m.apply_damage(m.max_hp + 1.0)
	assert_true(m.dead)
	assert_true(h.died)
	assert_eq(m.take_hit(Ironhorn.SHAPE_CIRCLE, m.position, m.position, 10.0, Vector2.ZERO, 0.0, 100.0), 0.0, "no damage after death")


func test_telegraph_then_attack_hits_player() -> void:
	var pair := _setup()
	var h: FakeHunt = pair[0]
	var m: Ironhorn = pair[1]
	h.player.position = m.position + Vector2(-160, 0)  # behind it: in the sweep / roar zone
	m.state = Ironhorn.State.PURSUE
	m.attack_cd = 0.0
	var saw_telegraph := false
	var saw_attack := false
	for k in 240:
		m.update(DT)
		if m.state == Ironhorn.State.TELEGRAPH:
			saw_telegraph = true
		if m.state == Ironhorn.State.ATTACK:
			saw_attack = true
			break
	assert_true(saw_telegraph, "telegraphs before attacking")
	assert_true(saw_attack, "then attacks")


func test_enrage() -> void:
	var m: Ironhorn = _setup()[1]
	m.apply_damage(m.max_hp * 0.75)
	m.update(DT)
	assert_true(m.enraged, "enrages below 30% HP")
	var pair := _setup()
	var m2: Ironhorn = pair[1]
	m2.set_time_enraged()
	m2.update(DT)
	assert_true(m2.enraged, "enrages on the timeline")
