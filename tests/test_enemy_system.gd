extends TestCase
## EnemySystem lifecycle: spawn/despawn free-list integrity at cap, kill callback, squad rout.


func _system(cap: int) -> EnemySystem:
	var field := FlowField.new(Rect2(-3000, -3000, 6000, 6000), 40.0, 84)
	field.update(Vector2.ZERO, true)
	var es := EnemySystem.new()
	root.add_child(es)
	es.setup(field, cap)
	es.render_enabled = false
	es.target = Vector2.ZERO
	return es


func _check_integrity(es: EnemySystem) -> void:
	assert_eq(es.n_active + es.n_free, es.cap, "active + free == cap")
	var seen := {}
	for k in es.n_active:
		var i := es.active[k]
		assert_eq(es.slot[i], k, "slot maps back to active index")
		assert_false(seen.has(i), "no duplicate in active list")
		seen[i] = true
	for k in es.n_free:
		var i := es.free_stack[k]
		assert_eq(es.slot[i], -1, "free ids have no slot")
		assert_false(seen.has(i), "id is not both free and active")


func test_spawn_to_cap_and_recycle() -> void:
	var es := _system(50)
	for k in 50:
		assert_true(es.spawn(EnemySystem.T_GRUNT, Vector2(k * 10.0, 300)) >= 0)
	assert_eq(es.spawn(EnemySystem.T_GRUNT, Vector2.ZERO), -1, "spawn fails at cap")
	assert_eq(es.n_active, 50)
	_check_integrity(es)
	var ids := PackedInt32Array()
	for k in es.n_active:
		ids.append(es.active[k])
	for k in range(0, ids.size(), 2):
		es.despawn(ids[k])
	assert_eq(es.n_active, 25)
	_check_integrity(es)
	for k in 25:
		assert_true(es.spawn(EnemySystem.T_RUNNER, Vector2(0, k * 10.0 + 400)) >= 0, "freed slots are reused")
	assert_eq(es.n_active, 50)
	_check_integrity(es)
	es.clear_all()
	assert_eq(es.n_active, 0)
	_check_integrity(es)


func test_damage_kill_invokes_callback_once() -> void:
	var es := _system(10)
	var killed: Array[int] = []
	es.on_kill = func(i: int, p: Vector2, t: int, cause: int) -> void: killed.append(i)
	var i := es.spawn(EnemySystem.T_GRUNT, Vector2(400, 0))
	assert_false(es.damage(i, 1.0), "chip damage doesn't kill")
	assert_true(es.flash[i] > 0.0, "hit flash set")
	assert_true(es.damage(i, 1000.0), "lethal damage kills")
	assert_false(es.damage(i, 1000.0), "already dead")
	assert_eq(killed.size(), 1)
	assert_false(es.is_alive(i))
	_check_integrity(es)


func test_officer_down_routs_squad() -> void:
	var es := _system(100)
	var off := es.spawn(EnemySystem.T_OFFICER, Vector2(500, 0), 7)
	var members := PackedInt32Array()
	for k in 12:
		members.append(es.spawn(EnemySystem.T_GRUNT, Vector2(520, k * 12.0), 7))
	var others := PackedInt32Array()
	for k in 5:
		others.append(es.spawn(EnemySystem.T_GRUNT, Vector2(-500, k * 12.0), -1))
	es.kill(off)
	var routed := es.rout_squad(7)
	assert_same_set(routed, members, "exactly the squad routs")
	for i in members:
		assert_gt(es.flee[i], 0.0, "member is fleeing")
	for i in others:
		assert_eq(es.flee[i], 0.0, "non-members unaffected")
	# fleeing members run away and despawn after rout_time
	var start_d := es.pos[members[0]].length()
	es.step(0.5)
	assert_gt(es.pos[members[0]].length(), start_d, "routed soldiers flee away from the hunter")
	var t := 0.5
	while t < es.rout_time + 0.3:
		es.step(1.0 / 30.0)
		t += 1.0 / 30.0
	for i in members:
		assert_false(es.is_alive(i), "routed soldier despawned")
	for i in others:
		assert_true(es.is_alive(i), "others still alive")
	_check_integrity(es)


func test_far_enemies_despawn() -> void:
	var es := _system(10)
	var far := es.spawn(EnemySystem.T_GRUNT, Vector2(2500, 0))
	var near := es.spawn(EnemySystem.T_GRUNT, Vector2(300, 0))
	es.step(1.0 / 60.0)
	assert_false(es.is_alive(far))
	assert_true(es.is_alive(near))
