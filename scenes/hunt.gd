class_name Hunt
extends HuntContext
## One hunt (run). Orchestrates every system explicitly each frame, in a fixed order, so
## timing is deterministic and measurable:
##   input -> gestures (moves) -> player -> weapons -> flow field -> swarm -> monster -> outposts
##   -> XP -> spawner -> timeline -> FX -> camera -> HUD
##
## config keys (all optional):
##   mode: "play" | "bench" | "smoke"   weapon: any id in GameState.WEAPONS
##   seed: int   bot: bool   god: bool   arrive_time: float   auto_pick: bool
##   loadout: {"tap": move_id, "swipe": move_id, "hold": move_id}

signal run_ended(won: bool)

var config: Dictionary = {}
var mode: String = "play"
var weapon_id: String = "great_sword"
var rng := RandomNumberGenerator.new()
var map_rect: Rect2
var rocks: Array[Vector3] = []

var field: FlowField
var xp: XPSystem
var particles: Particles
var dmgnums: DamageNumbers
var camera: Camera2D
var monster: Ironhorn
var outposts: Outposts
var spawner: Spawner
var progression: Progression
var pool: UpgradePool
var moves: MoveSet
var main_weapon: Weapon
var bot: BotInput
## Optional scripted input (benchmark): Callable(dt: float) -> Vector2
var input_override: Callable = Callable()

var hud: HUD
var joystick: TouchStick
var gestures: GesturePad
var level_ui: LevelUpUI
var pause_ui: PauseMenu

# timeline
var arrive_time: float = 120.0
var enrage_time: float = 540.0
var time_limit: float = 600.0
var monster_arrived: bool = false
var time_enraged: bool = false

# run stats
var kos: int = 0
var officers_defeated: int = 0
var parts_broken: int = 0
var max_level: int = 1
var ended: bool = false
var won: bool = false
var end_reason: String = ""
var end_timer: float = 0.0
var god: bool = false
var auto_pick: bool = false
var perfects: int = 0

# gestures waiting to run this frame (from the pad, the bot, the keyboard or tests)
var _gesture_queue: Array[Dictionary] = []
var _perfect_window: float = 0.3
var _perfect_mult: float = 1.5

# juice
var shake: float = 0.0
var _time_requests: Array[Vector2] = []  ## (scale, until_msec)
var _frame_kills: int = 0
var _milestones: Array = []
var _next_milestone: int = 0
var _monster_num_clock: float = 0.0
var _cam_look: Vector2 = Vector2.ZERO

# perf telemetry (microseconds, last frame)
var t_weapons_us: int = 0
var t_field_us: int = 0
var t_step_us: int = 0
var t_render_us: int = 0
var frames: int = 0

# cached tuning
var _zoom: float = 0.72
var _cam_smooth: float = 7.0
var _look_ahead: float = 110.0
var _shake_max: float = 26.0
var _shake_decay: float = 2.4
var _dead_zone: float = 0.12
var _full_at: float = 0.6
var _kill_shake: float = 0.04
var _death_particles: int = 3
var _dot_monster_mult: float = 0.3


func _ready() -> void:
	mode = String(config.get("mode", "play"))
	weapon_id = String(config.get("weapon", GameState.selected_weapon))
	rng.seed = int(config.get("seed", randi()))
	god = bool(config.get("god", mode == "bench"))
	auto_pick = bool(config.get("auto_pick", mode != "play"))
	arrive_time = float(config.get("arrive_time", Tuning.f("run.monster_arrive_time", 120.0)))
	enrage_time = Tuning.f("run.enrage_time", 540.0)
	time_limit = float(config.get("time_limit", Tuning.f("run.time_limit", 600.0)))
	_zoom = Tuning.f("camera.zoom", 0.72)
	_cam_smooth = Tuning.f("camera.smoothing", 7.0)
	_look_ahead = Tuning.f("camera.look_ahead", 110.0)
	_shake_max = Tuning.f("camera.shake_max_offset", 26.0)
	_shake_decay = Tuning.f("camera.shake_decay", 2.4)
	_dead_zone = Tuning.f("controls.dead_zone", 0.12)
	_full_at = Tuning.f("controls.full_speed_at", 0.6)
	_kill_shake = Tuning.f("juice.kill_shake", 0.04)
	_death_particles = Tuning.i("juice.death_particles", 3)
	_dot_monster_mult = Tuning.f("monster.dot_damage_mult", 0.3)
	_milestones = Tuning.a("ko_milestones")
	_perfect_window = Tuning.f("gestures.perfect_window", 0.3)
	_perfect_mult = Tuning.f("gestures.perfect_mult", 1.5)
	if bool(config.get("bot", mode != "play")):
		bot = BotInput.new(int(config.get("seed", 1)) + 7, weapon_id)
	_build_world()
	_build_ui()


func _exit_tree() -> void:
	Engine.time_scale = 1.0


# =============================================================== construction

func _build_world() -> void:
	var size := Tuning.f("map.size", 6000.0)
	map_rect = Rect2(-size * 0.5, -size * 0.5, size, size)

	var ground := Sprite2D.new()
	var gt := ArtRegistry.tex("ground.tile")
	ground.texture = gt
	ground.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	ground.region_enabled = true
	var gscale := ArtRegistry.size("ground.tile").x / float(gt.get_width())
	ground.region_rect = Rect2(0, 0, size / gscale, size / gscale)
	ground.scale = Vector2(gscale, gscale)
	ground.z_index = -10
	add_child(ground)
	# map border
	var border := Line2D.new()
	border.points = PackedVector2Array([map_rect.position, Vector2(map_rect.end.x, map_rect.position.y), map_rect.end, Vector2(map_rect.position.x, map_rect.end.y), map_rect.position])
	border.width = 24.0
	border.default_color = Color(0.0, 0.0, 0.0, 0.6)
	border.z_index = -9
	add_child(border)

	field = FlowField.new(map_rect, Tuning.f("flow_field.cell", 40.0), Tuning.i("flow_field.window_cells", 84))

	outposts = Outposts.new()
	outposts.setup()
	_generate_rocks()

	fx_under = FX.new()
	fx_under.z_index = -3
	add_child(fx_under)
	fx_under.add_drawer(_draw_under)

	xp = XPSystem.new()
	xp.z_index = -2
	add_child(xp)
	xp.setup()

	enemies = EnemySystem.new()
	enemies.z_index = 0
	add_child(enemies)
	enemies.setup(field)
	enemies.on_kill = _on_enemy_killed
	enemies.render_enabled = false  # rendered explicitly so it can be timed separately

	for k in outposts.positions.size():
		var flag := Sprite2D.new()
		ArtRegistry.apply_to_sprite(flag, "outpost.flag")
		flag.position = outposts.positions[k] + Vector2(10, -30)
		flag.modulate = ArtRegistry.color("outpost.neutral")
		flag.z_index = 1
		flag.name = "OutpostFlag%d" % k
		add_child(flag)

	player = Player.new()
	player.z_index = 3
	player.map_rect = map_rect
	player.rocks = rocks
	add_child(player)
	player.setup()
	player.position = Vector2.ZERO

	particles = Particles.new()
	particles.z_index = 4
	add_child(particles)
	particles.setup(Tuning.i("juice.particle_cap", 350))

	fx_over = FX.new()
	fx_over.z_index = 5
	add_child(fx_over)

	dmgnums = DamageNumbers.new()
	dmgnums.z_index = 6
	add_child(dmgnums)
	dmgnums.setup(Tuning.i("juice.damage_number_cap", 60), Tuning.f("juice.damage_number_life", 0.6))

	main_weapon = WeaponFactory.make(weapon_id)
	main_weapon.setup(self, player)
	player.weapons = [main_weapon]
	# guns kill far away, so their XP lands far away: they get a bigger pickup magnet
	player.magnet_radius *= Tuning.f("weapons.%s.magnet_mult" % weapon_id, 1.0)
	moves = MoveSet.new()
	moves.setup(main_weapon, player, config.get("loadout", Save.loadout_for(weapon_id)))

	progression = Progression.new()
	progression.setup()
	pool = UpgradePool.new()
	pool.setup(self, player, main_weapon, moves)

	spawner = Spawner.new()
	spawner.setup(enemies, field, outposts, rng, map_rect)
	spawner.enabled = mode != "bench"

	camera = Camera2D.new()
	camera.zoom = Vector2(_zoom, _zoom)
	camera.position = player.position
	add_child(camera)
	camera.make_current()

	field.update(player.position, true)
	enemies.target = player.position
	enemies.rebuild_hash()


func _generate_rocks() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = Tuning.i("map.seed", 1337)
	var count := Tuning.i("map.rock_count", 70)
	var rmin := Tuning.f("map.rock_radius_min", 50.0)
	var rmax := Tuning.f("map.rock_radius_max", 150.0)
	var clear := Tuning.f("map.rock_clear_radius", 420.0)
	var tries := 0
	while rocks.size() < count and tries < count * 40:
		tries += 1
		var rad := r.randf_range(rmin, rmax)
		var p := Vector2(r.randf_range(map_rect.position.x + 200, map_rect.end.x - 200), r.randf_range(map_rect.position.y + 200, map_rect.end.y - 200))
		if p.length() < clear + rad:
			continue
		var ok := true
		for op in outposts.positions:
			if p.distance_to(op) < outposts.radius + rad + 90.0:
				ok = false
				break
		if ok:
			for rk in rocks:
				if p.distance_to(Vector2(rk.x, rk.y)) < rk.z + rad + 70.0:
					ok = false
					break
		if not ok:
			continue
		rocks.append(Vector3(p.x, p.y, rad))
		field.block_circle(p, rad + 6.0)
		var s := Sprite2D.new()
		ArtRegistry.apply_to_sprite(s, "obstacle.rock")
		var base := ArtRegistry.size("obstacle.rock").x
		s.scale *= (rad * 2.25) / base
		s.position = p
		s.rotation = r.randf() * TAU
		s.z_index = -4
		add_child(s)


func _build_ui() -> void:
	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 10
	add_child(hud_layer)
	joystick = TouchStick.new()
	joystick.stick_left = GameState.stick_left
	hud_layer.add_child(joystick)
	gestures = GesturePad.new()
	gestures.stick_left = GameState.stick_left
	hud_layer.add_child(gestures)
	gestures.gestured.connect(func(ev: Dictionary) -> void: _gesture_queue.append(ev))
	gestures.hold_started.connect(_on_hold_started)
	hud = HUD.new()
	hud.hunt = self
	hud_layer.add_child(hud)
	hud.layout()
	joystick.blocked_rects = hud.blocked_rects()
	gestures.blocked_rects = hud.blocked_rects()

	level_ui = LevelUpUI.new()
	add_child(level_ui)
	level_ui.picked.connect(_on_upgrade_picked)

	pause_ui = PauseMenu.new()
	add_child(pause_ui)
	pause_ui.resumed.connect(toggle_pause)
	pause_ui.quit_requested.connect(_quit_to_title)
	pause_ui.side_changed.connect(func() -> void:
		joystick.stick_left = GameState.stick_left
		gestures.stick_left = GameState.stick_left)


# =============================================================== frame

func _process(delta: float) -> void:
	_update_time_scale()
	var dt := minf(delta, 1.0 / 30.0)
	frames += 1
	if ended:
		end_timer -= dt
		fx_under.step(dt)
		fx_over.step(dt)
		particles.step(dt)
		dmgnums.step(dt)
		_update_camera(dt)
		hud.step(dt)
		if end_timer <= 0.0 and mode == "play" and is_inside_tree():
			set_process(false)
			get_tree().change_scene_to_file("res://ui/results.tscn")
		return

	run_time += dt
	_frame_kills = 0
	var input := _gather_input(dt)
	if bot != null:
		for ev in bot.next_gestures(dt, self):
			_gesture_queue.append(ev)
	moves.tick(dt)
	_process_gestures()
	player.move_step(dt, input)

	var t0 := Time.get_ticks_usec()
	for w in player.weapons:
		w.update(dt, input)
	var t1 := Time.get_ticks_usec()
	field.update(player.position)
	enemies.target = player.position
	enemies.target_vel = player.velocity
	var t2 := Time.get_ticks_usec()
	enemies.step(dt)
	var t3 := Time.get_ticks_usec()
	enemies.update_render()
	var t4 := Time.get_ticks_usec()
	t_weapons_us = t1 - t0
	t_field_us = t2 - t1
	t_step_us = t3 - t2
	t_render_us = t4 - t3

	if not god:
		var cd := enemies.contact_damage(player.position, player.radius)
		if cd > 0.0:
			damage_player(cd, enemies.last_contact_pos)

	if monster != null:
		monster.update(dt)

	var cap := outposts.update(dt, player.position)
	if cap >= 0:
		_on_outpost_captured(cap)
	var heal := outposts.heal_rate_at(player.position)
	if heal > 0.0:
		player.heal(heal * dt)

	var got := xp.step(dt, player.position, player.magnet_radius * player.magnet_mult, player.pickup_radius)
	if got > 0:
		progression.add_xp(got)
		max_level = progression.level


	for ev in spawner.update(dt, run_time, player.position, player.move_dir if player.is_moving() else Vector2.ZERO):
		match ev:
			"officer":
				hud.banner("ENEMY OFFICER APPEARS", "ui.accent", 1.3)
			"surge":
				hud.banner("SURGE!", "ui.danger", 1.4)
				add_shake(0.3)

	_update_timeline()

	if _frame_kills > 0:
		add_shake(minf(0.12, _kill_shake * sqrt(float(_frame_kills))))

	fx_under.step(dt)
	fx_over.step(dt)
	particles.step(dt)
	dmgnums.step(dt)
	_monster_num_clock += dt
	_update_camera(dt)
	joystick.blocked_rects = hud.blocked_rects()
	gestures.blocked_rects = joystick.blocked_rects
	hud.step(dt)

	if progression.pending > 0 and not ended and not level_ui.is_open():
		_open_level_up()


func _gather_input(dt: float) -> Vector2:
	if input_override.is_valid():
		return input_override.call(dt)
	if bot != null:
		return bot.next(dt, self)
	var kb := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		kb.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		kb.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		kb.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		kb.y += 1.0
	if kb != Vector2.ZERO:
		return kb.normalized()
	return shape_input(joystick.raw_vector(), _dead_zone, _full_at)


## Dead zone + response curve: past `full_at` deflection = full speed.
static func shape_input(raw: Vector2, dead_zone: float, full_at: float) -> Vector2:
	var m := raw.length()
	if m < dead_zone:
		return Vector2.ZERO
	var mag := clampf((m - dead_zone) / maxf(full_at - dead_zone, 0.001), 0.0, 1.0)
	return raw / m * mag


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k := (event as InputEventKey).physical_keycode
		match k:
			KEY_ESCAPE:
				toggle_pause()
			# desktop stand-ins for the gesture thumb
			KEY_J:
				_gesture_queue.append({"kind": "tap"})
			KEY_K:
				_gesture_queue.append({"kind": "swipe", "dir": player.facing})
			KEY_L:
				_gesture_queue.append({"kind": "hold", "dir": player.facing, "hold_time": 0.8})
			KEY_1:
				_gesture_queue.append({"kind": "circle"})
			KEY_2:
				_gesture_queue.append({"kind": "v", "dir": player.facing})
			KEY_3:
				_gesture_queue.append({"kind": "zigzag", "dir": player.facing})
			KEY_4:
				_gesture_queue.append({"kind": "triangle"})


func _update_camera(dt: float) -> void:
	var want_look := Vector2.ZERO
	if player.velocity.length_squared() > 1.0:
		want_look = player.velocity.normalized() * _look_ahead
	_cam_look = _cam_look.lerp(want_look, minf(1.0, dt * 2.5))
	var target := player.position + _cam_look
	camera.position = camera.position.lerp(target, minf(1.0, dt * _cam_smooth))
	shake = maxf(0.0, shake - _shake_decay * dt)
	var amt := shake * shake * _shake_max * GameState.shake_mult()
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * amt
	# spawner needs the visible half-size in world units
	var vis := get_viewport_rect().size / _zoom
	spawner.view_half = vis * 0.5


func view_rect_world() -> Rect2:
	var vis := get_viewport_rect().size / _zoom
	return Rect2(camera.position - vis * 0.5, vis)


# =============================================================== timeline

func _update_timeline() -> void:
	if not monster_arrived and run_time >= arrive_time:
		spawn_monster()
	if monster_arrived and not time_enraged and run_time >= enrage_time:
		time_enraged = true
		if monster != null and monster.is_alive():
			monster.set_time_enraged()
			hud.banner("IRONHORN IS ENRAGED!", "ui.danger", 2.0)
	if run_time >= time_limit and not ended:
		if monster != null:
			monster.flee()
		hud.banner("THE MONSTER ESCAPED", "ui.danger", 2.5)
		end_run(false, "time")


func spawn_monster() -> void:
	monster_arrived = true
	monster = Ironhorn.new()
	monster.z_index = 2
	add_child(monster)
	monster.setup(self, rng.randi())
	var dir := player.move_dir if player.move_dir != Vector2.ZERO else Vector2.RIGHT
	var p := player.position + dir.rotated(rng.randf_range(-0.6, 0.6)) * Tuning.f("monster.arrive_distance", 1250.0)
	p.x = clampf(p.x, map_rect.position.x + 300, map_rect.end.x - 300)
	p.y = clampf(p.y, map_rect.position.y + 300, map_rect.end.y - 300)
	monster.position = p
	monster.facing = (player.position - p).normalized()
	monster.rotation = monster.facing.angle()
	hud.banner("IRONHORN APPROACHES", "ui.danger", 2.4)
	add_shake(0.5)


func end_run(p_won: bool, reason: String) -> void:
	if ended:
		return
	ended = true
	won = p_won
	end_reason = reason
	end_timer = Tuning.f("run.end_delay", 2.0)
	player.invuln = true
	Engine.time_scale = 1.0
	_time_requests.clear()
	if level_ui.is_open():
		level_ui.visible = false
		get_tree().paused = false
	hud.banner("HUNT COMPLETE!" if won else "HUNT FAILED", "ui.accent" if won else "ui.danger", 3.0)
	var result := {
		"won": won,
		"reason": reason,
		"weapon": weapon_id,
		"time": run_time,
		"kos": kos,
		"officers": officers_defeated,
		"outposts": outposts.captured_count(),
		"outposts_total": outposts.positions.size(),
		"parts": parts_broken,
		"level": progression.level,
		"moves": moves.performed,
		"perfects": perfects,
		"new_kos": false,
		"new_time": false,
	}
	if mode == "play":
		var rec := Save.record(weapon_id, kos, won, run_time)
		result["new_kos"] = rec["new_kos"]
		result["new_time"] = rec["new_time"]
	GameState.last_result = result
	run_ended.emit(won)


# =============================================================== combat API

func damage_mult() -> float:
	return player.dmg_mult * (1.0 + outposts.damage_bonus())


func _show_number(p: Vector2, dmg: float, big: bool) -> void:
	if big:
		dmgnums.add(p, str(int(round(dmg))), ArtRegistry.color("ui.damage_num_big"), 28, true)
	else:
		dmgnums.add(p, str(int(round(dmg))), ArtRegistry.color("ui.damage_num"), 18, false)


func _hit_monster(shape: int, a: Vector2, b: Vector2, r: float, dir: Vector2, half: float, dmg: float, flags: int) -> void:
	if monster == null or (flags & HIT_NO_MONSTER) != 0 or not monster.is_alive():
		return
	if (flags & HIT_DOT) != 0:
		dmg *= _dot_monster_mult
	var dealt := monster.take_hit(shape, a, b, r, dir, half, dmg)
	if dealt > 0.0 and (dmg >= 20.0 or _monster_num_clock > 0.1):
		_monster_num_clock = 0.0
		dmgnums.add(monster.position + Vector2(randf_range(-50, 50), randf_range(-60, 0)), str(int(round(dealt))), ArtRegistry.color("ui.damage_num_monster"), 30 if dmg >= 20.0 else 22, true)


func _apply_hits(ids: PackedInt32Array, origin: Vector2, dmg: float, knock: float, flags: int, along: Vector2 = Vector2.ZERO) -> void:
	var big := (flags & HIT_BIG) != 0
	var shown := 0
	for i in ids:
		var p := enemies.pos[i]
		var kdir := (p - origin).normalized() if along == Vector2.ZERO else along
		if big and shown < 5:
			_show_number(p, dmg, true)
			shown += 1
		elif shown < 1:
			_show_number(p, dmg, false)
			shown += 1
		enemies.damage(i, dmg, kdir * knock, EnemySystem.CAUSE_WEAPON)


func hit_circle(c: Vector2, r: float, dmg: float, knock: float, flags: int = 0) -> int:
	var ids := enemies.query_circle(c, r)
	_apply_hits(ids, c, dmg, knock, flags)
	_hit_monster(Ironhorn.SHAPE_CIRCLE, c, c, r, Vector2.ZERO, 0.0, dmg, flags)
	return ids.size()


func hit_arc(c: Vector2, dir: Vector2, r: float, half: float, dmg: float, knock: float, flags: int = 0) -> int:
	var ids := enemies.query_arc(c, r, dir, half)
	_apply_hits(ids, c, dmg, knock, flags)
	_hit_monster(Ironhorn.SHAPE_ARC, c, c, r, dir, half, dmg, flags)
	return ids.size()


func hit_line(a: Vector2, b: Vector2, w: float, dmg: float, knock: float, flags: int = 0) -> int:
	var ids := enemies.query_line(a, b, w)
	var dir := (b - a).normalized()
	_apply_hits(ids, a, dmg, knock, flags, dir)
	_hit_monster(Ironhorn.SHAPE_LINE, a, b, w, dir, 0.0, dmg, flags)
	return ids.size()


func shoot(a: Vector2, dir: Vector2, reach: float, width: float, dmg: float, knock: float, pierce: int, flags: int = 0) -> Vector2:
	var t_mon := INF
	if monster != null and (flags & HIT_NO_MONSTER) == 0:
		t_mon = monster.ray_entry(a, dir, width)
	var stop := minf(reach, t_mon)
	var cands := enemies.query_line(a, a + dir * stop, width)
	var ts := PackedFloat32Array()
	ts.resize(cands.size())
	for k in cands.size():
		ts[k] = (enemies.pos[cands[k]] - a).dot(dir)
	# nearest `pierce` along the ray (selection: pierce is small)
	var hit := PackedInt32Array()
	var end_t := stop
	for h in mini(pierce, cands.size()):
		var best := -1
		for k in cands.size():
			if ts[k] < INF and (best < 0 or ts[k] < ts[best]):
				best = k
		hit.append(cands[best])
		if hit.size() == pierce:
			end_t = maxf(0.0, ts[best])
		ts[best] = INF
	_apply_hits(hit, a, dmg, knock, flags, dir)
	if hit.size() < pierce and t_mon <= reach:
		_hit_monster(Ironhorn.SHAPE_LINE, a, a + dir * (t_mon + width * 2.0), width, dir, 0.0, dmg, flags)
	return a + dir * end_t


func auto_target(from: Vector2, max_range: float) -> Vector2:
	if monster != null and monster.is_alive() and monster.position.distance_to(from) <= max_range + monster.body_radius:
		return monster.aim_point(from)
	var best := Vector2.INF
	var best_d := INF
	for i in enemies.query_circle(from, max_range, false):
		var d := enemies.pos[i].distance_squared_to(from)
		if d < best_d:
			best_d = d
			best = enemies.pos[i]
	return best


func nearest_in_arc(from: Vector2, max_range: float, dir: Vector2, half: float) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	if monster != null and monster.is_alive():
		var mp := monster.aim_point(from)
		var md := mp.distance_squared_to(from)
		if md <= max_range * max_range and absf(dir.angle_to(mp - from)) <= half:
			best = mp
			best_d = md
	for i in enemies.query_arc(from, max_range, dir, half):
		if enemies.flee[i] > 0.0:
			continue
		var d := enemies.pos[i].distance_squared_to(from)
		if d < best_d:
			best_d = d
			best = enemies.pos[i]
	return best


func chain_targets(from: Vector2, n: int, first_range: float, hop: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var used := {}
	var cur := from
	var reach := first_range
	for k in n:
		var best := -1
		var best_d := INF
		for i in enemies.query_circle(cur, reach, false):
			if used.has(i):
				continue
			var d := enemies.pos[i].distance_squared_to(cur)
			if d < best_d:
				best_d = d
				best = i
		if best < 0:
			break
		used[best] = true
		cur = enemies.pos[best]
		out.append(cur)
		reach = hop
	return out


func sub_level(sub_id: String) -> int:
	var s := pool.sub_by_id(sub_id)
	return s.level if s != null else 0


func densest_point(center: Vector2, max_range: float, samples: int, radius: float) -> Vector2:
	var cands := enemies.query_circle(center, max_range, false)
	var best := Vector2.INF
	var best_n := 0
	if monster != null and monster.is_alive() and monster.position.distance_to(center) <= max_range and rng.randf() < 0.4:
		return monster.position
	if cands.is_empty():
		return Vector2.INF
	for s in samples:
		var i := cands[rng.randi() % cands.size()]
		var p := enemies.pos[i]
		var n := enemies.count_in_circle(p, radius)
		if n > best_n:
			best_n = n
			best = p
	return best


func add_shake(amount: float) -> void:
	shake = minf(1.0, shake + amount)


func hitstop(ms: int) -> void:
	_time_requests.append(Vector2(0.05, Time.get_ticks_msec() + ms))


func _slowmo(scale: float, ms: int) -> void:
	_time_requests.append(Vector2(scale, Time.get_ticks_msec() + ms))


func _update_time_scale() -> void:
	var now := Time.get_ticks_msec()
	var s := 1.0
	var k := 0
	while k < _time_requests.size():
		var r := _time_requests[k]
		if r.y <= now:
			_time_requests.remove_at(k)
		else:
			s = minf(s, r.x)
			k += 1
	Engine.time_scale = s


func haptic(key: String) -> void:
	GameState.haptic(Tuning.i("haptics_ms." + key, 0))


func kill_enemies_in_circle(c: Vector2, r: float, cause: int) -> int:
	var ids := enemies.query_circle(c, r)
	for i in ids:
		enemies.kill(i, cause)
	return ids.size()


func damage_player(amount: float, from: Vector2) -> bool:
	if god or ended:
		return false
	amount = main_weapon.modify_incoming(amount, from)
	if not player.take_damage(amount):
		return false
	hud.hurt()
	add_shake(Tuning.f("juice.hurt_shake", 0.35))
	haptic("hurt")
	dmgnums.add(player.position + Vector2(0, -30), "-%d" % int(round(amount)), ArtRegistry.color("ui.danger"), 26, true)
	if player.hp <= 0.0:
		player.hp = 0.0
		end_run(false, "defeated")
	return true


func slow_player(seconds: float) -> void:
	if not god:
		player.slow_timer = seconds


func spawn_grunts_around(c: Vector2, n: int, min_r: float, max_r: float) -> void:
	for k in n:
		var p := c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(min_r, max_r)
		if map_rect.has_point(p) and not field.is_blocked(p):
			enemies.spawn(EnemySystem.T_GRUNT, p)


func is_blocked(p: Vector2) -> bool:
	return field.is_blocked(p)


func steer_dir(from: Vector2, to: Vector2) -> Vector2:
	if from.distance_squared_to(to) < 250.0 * 250.0:
		return (to - from).normalized()
	return field.sample(from)


# =============================================================== events

func _on_enemy_killed(i: int, p: Vector2, type: int, cause: int) -> void:
	if enemies.flee[i] > 0.0:
		return  # routed soldiers were already counted when their officer fell
	kos += 1
	_frame_kills += 1
	xp.spawn(p, enemies.t_xp[type])
	if particles.alive < particles.cap - 20:
		particles.burst(p, enemies.t_tint[type], _death_particles, 150.0, 6.0)
	if type == EnemySystem.T_OFFICER:
		officers_defeated += 1
		var routed := enemies.rout_squad(enemies.squad[i])
		for r in routed:
			xp.spawn(enemies.pos[r], enemies.t_xp[enemies.etype[r]])
		kos += routed.size()
		hud.banner("OFFICER DEFEATED!", "ui.accent", 1.4)
		particles.burst(p, ArtRegistry.color("ui.accent"), 16, 260.0, 9.0, 0.6)
		fx_over.ring(p, 120.0, "fx.gold", 0.4, 10.0, 0.7)
		add_shake(0.3)
		haptic("dash_cut")
	_check_milestone()


func _check_milestone() -> void:
	while _next_milestone < _milestones.size() and kos >= int(_milestones[_next_milestone]):
		hud.milestone("%s KOs!" % UIKit.fmt_int(int(_milestones[_next_milestone])))
		_next_milestone += 1


func _on_outpost_captured(k: int) -> void:
	hud.banner("OUTPOST CAPTURED  +%d%% DMG" % int(outposts.damage_bonus() * 100.0 + 0.5), "outpost.captured", 1.8)
	var flag := get_node_or_null("OutpostFlag%d" % k) as Sprite2D
	if flag != null:
		flag.modulate = ArtRegistry.color("outpost.captured")
	fx_over.ring(outposts.positions[k], outposts.radius, "fx.gold", 0.6, 14.0, 0.5)
	particles.burst(outposts.positions[k], ArtRegistry.color("outpost.captured"), 20, 260.0, 8.0, 0.6)
	add_shake(0.25)


func on_monster_part_broken(part: String, at: Vector2) -> void:
	parts_broken += 1
	var xpv := Tuning.i("monster.part_break_xp", 30)
	for k in 6:
		xp.spawn(at + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(10, 90), xpv / 6)
	hud.banner("PART BROKEN!  %s" % part.to_upper(), "ui.accent", 1.8)
	particles.burst(at, ArtRegistry.color("fx.part_break"), 30, 380.0, 10.0, 0.7)
	fx_over.ring(at, 140.0, "fx.part_break", 0.45, 14.0, 0.8)
	add_shake(0.8)
	hitstop(90)
	haptic("part_break")


func on_monster_died(at: Vector2) -> void:
	particles.burst(at, ArtRegistry.color("fx.part_break"), 60, 520.0, 12.0, 0.9)
	fx_over.ring(at, 260.0, "fx.gold", 0.8, 24.0, 0.8)
	add_shake(1.0)
	_slowmo(0.3, 600)
	haptic("part_break")
	hud.flash_screen(0.7)
	xp.attract_all()
	if monster != null:
		var tw := create_tween()
		tw.tween_property(monster, "modulate:a", 0.0, 1.2)
	end_run(true, "slain")


# =============================================================== gestures

## Queue a gesture from outside the pad (bot, keyboard, tests). World-space:
##   {"kind": String, "dir": Vector2 (unit or ZERO = auto-aim), "hold_time": float}
func inject_gesture(ev: Dictionary) -> void:
	_gesture_queue.append(ev)


func _process_gestures() -> void:
	if _gesture_queue.is_empty():
		return
	var queue := _gesture_queue
	_gesture_queue = []
	for ev in queue:
		perform_gesture(ev)


## Move context: the stroke's direction when the gesture has one, else auto-aim.
func gesture_ctx(ev: Dictionary) -> Dictionary:
	var kind := String(ev.get("kind", ""))
	var dir: Vector2 = ev.get("dir", Vector2.ZERO)
	var target := auto_target(player.position, 700.0)
	var aimed := dir != Vector2.ZERO and kind in ["swipe", "hold", "v", "zigzag"]
	if not aimed:
		dir = player.facing
		if target != Vector2.INF and target.distance_to(player.position) > 1.0:
			dir = (target - player.position).normalized()
	return {"kind": kind, "dir": dir.normalized(), "aimed": aimed, "target": target,
		"hold_time": float(ev.get("hold_time", 0.0)), "power": 1.0, "perfect": false}


## Runs the move bound to a gesture. A move fired in the last moments of a monster telegraph
## that would hit you is a PERFECT counter: the attack is cancelled and the move hits harder.
## Returns the MoveSet result ("ok", "cooldown", "unbound", "failed") or "unknown".
func perform_gesture(ev: Dictionary) -> String:
	if ended:
		return "ended"
	var kind := String(ev.get("kind", ""))
	if kind == "":
		_pad_feedback("?", "ui.text_dim")
		return "unknown"
	var ctx := gesture_ctx(ev)
	var move_id := moves.move_for(kind)
	var perfect := false
	if move_id != "" and moves.cooldown_left(move_id) <= 0.0 and monster != null and monster.is_alive():
		perfect = monster.counter_window(player.position, player.radius + 40.0, _perfect_window)
	if perfect:
		ctx["perfect"] = true
		ctx["power"] = _perfect_mult
	var res := moves.trigger(ctx)
	var nm := String(moves.def_of(move_id).get("name", move_id)).to_upper()
	match res:
		"ok":
			if perfect:
				_on_perfect()
				_pad_feedback("PERFECT! " + nm, "ui.accent")
			else:
				_pad_feedback(nm, "ui.text")
		"cooldown":
			if kind == "hold":
				main_weapon.cancel_hold()
			_pad_feedback("%.1fs" % moves.cooldown_left(move_id), "ui.text_dim")
		"unbound":
			_pad_feedback("%s: LOCKED" % MoveSet.gesture_label(kind), "ui.text_dim")
		"failed":
			_pad_feedback(nm + ": NOT READY", "ui.text_dim")
	return res


## "TAP  Tackle  Lv 1" lines for the pause menu.
func gesture_summary() -> String:
	var lines: PackedStringArray = []
	for kind in moves.bound_gestures():
		var id := moves.move_for(kind)
		lines.append("%s   %s   Lv %d" % [MoveSet.gesture_label(kind), String(moves.def_of(id).get("name", id)), moves.level_of(id)])
	return "\n".join(lines)


func _on_hold_started() -> void:
	if ended or get_tree().paused:
		return
	moves.begin_hold(gesture_ctx({"kind": "hold"}))


func _on_perfect() -> void:
	perfects += 1
	moves.perfects += 1
	monster.interrupt(Tuning.f("gestures.perfect_recover", 0.4))
	player.iframes = maxf(player.iframes, Tuning.f("gestures.perfect_iframes", 0.7))
	hud.banner("PERFECT COUNTER!", "ui.accent", 1.2)
	fx_over.ring(player.position, 140.0, "fx.gold", 0.35, 12.0, 0.8)
	particles.burst(player.position, ArtRegistry.color("fx.gold"), 18, 320.0, 8.0, 0.5)
	_slowmo(Tuning.f("gestures.perfect_slowmo", 0.35), Tuning.i("gestures.perfect_slowmo_ms", 260))
	add_shake(0.5)
	haptic("perfect")


func _pad_feedback(text: String, color_id: String) -> void:
	if gestures != null:
		gestures.feedback(text, ArtRegistry.color(color_id))


# =============================================================== level-ups & pause

func _open_level_up() -> void:
	if not progression.take_pending():
		return
	var opts := pool.roll(rng, 3, progression.level - progression.pending)
	if auto_pick:
		pool.apply(opts[rng.randi() % opts.size()])
		return
	joystick.reset()
	gestures.reset()
	main_weapon.cancel_hold()
	get_tree().paused = true
	level_ui.show_options(opts, progression.level - progression.pending)


func _on_upgrade_picked(opt: Dictionary) -> void:
	pool.apply(opt)
	if progression.pending > 0:
		var opts := pool.roll(rng, 3, progression.level - progression.pending + 1)
		progression.take_pending()
		level_ui.show_options(opts, progression.level - progression.pending)
	else:
		get_tree().paused = false
		joystick.reset()
		gestures.reset()


func toggle_pause() -> void:
	if ended or level_ui.is_open():
		return
	if get_tree().paused:
		pause_ui.close()
		get_tree().paused = false
		joystick.reset()
		gestures.reset()
	else:
		get_tree().paused = true
		gestures.reset()
		main_weapon.cancel_hold()
		pause_ui.open(gesture_summary())


func _quit_to_title() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://ui/title.tscn")


# =============================================================== drawing

func _draw_under(ci: CanvasItem) -> void:
	outposts.draw(ci)
	_draw_hold_aim(ci)
	for w in player.weapons:
		w.draw_world_under(ci)
	if monster != null:
		monster.draw_world_under(ci)


## While the gesture thumb is held: an aim arrow from the hunter (or a ring = auto-aim).
func _draw_hold_aim(ci: CanvasItem) -> void:
	if gestures == null or not gestures.holding:
		return
	var col := ArtRegistry.color("fx.aim")
	var aim := gestures.hold_aim()
	var p := player.position
	if aim == Vector2.ZERO:
		ci.draw_arc(p, player.radius + 30.0, 0.0, TAU, 40, col, 3.0)
		return
	var length := 260.0
	var k := 0.0
	while k < length:
		ci.draw_line(p + aim * (player.radius + 12.0 + k), p + aim * (player.radius + 12.0 + minf(k + 18.0, length)), col, 5.0)
		k += 30.0
	var tip := p + aim * (player.radius + 12.0 + length)
	var side := aim.orthogonal() * 14.0
	ci.draw_colored_polygon(PackedVector2Array([tip + aim * 22.0, tip + side, tip - side]), col)


# =============================================================== bench helpers

## Fills the swarm to n enemies in a ring around the hunter (benchmark).
func fill_enemies(n: int) -> void:
	var guard := 0
	while enemies.n_active < n and guard < n * 4:
		guard += 1
		var p := player.position + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(160.0, 1150.0)
		if map_rect.has_point(p) and not field.is_blocked(p):
			enemies.spawn(EnemySystem.T_GRUNT if rng.randf() < 0.8 else EnemySystem.T_RUNNER, p)
