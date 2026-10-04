class_name Spawner
extends RefCounted
## Keeps the swarm topped up along tuning curves, spawning just outside the visible rect
## (biased toward where the hunter is heading). Also spawns officer squads and surge rings.

var enemies: EnemySystem
var field: FlowField
var outposts: Outposts
var rng: RandomNumberGenerator
var map_rect: Rect2

var enabled: bool = true
var view_half: Vector2 = Vector2(500, 890)
var ring_margin: float = 90.0
var max_per_frame: int = 30
var bias_chance: float = 0.6
var bias_spread: float = 0.9
var squad_min: int = 20
var squad_max: int = 40
var surge_interval: float = 90.0
var hp_growth: float = 0.35
var speed_growth: float = 0.03

var _accum: float = 0.0
var next_officer: float = 18.0
var next_surge: float = 90.0
var squad_counter: int = 0
var officers_spawned: int = 0
var surges: int = 0


func setup(p_enemies: EnemySystem, p_field: FlowField, p_outposts: Outposts, p_rng: RandomNumberGenerator, p_map: Rect2) -> void:
	enemies = p_enemies
	field = p_field
	outposts = p_outposts
	rng = p_rng
	map_rect = p_map
	ring_margin = Tuning.f("spawner.ring_margin", 90.0)
	max_per_frame = Tuning.i("spawner.max_per_frame", 30)
	bias_chance = Tuning.f("spawner.move_bias_chance", 0.6)
	bias_spread = Tuning.f("spawner.move_bias_spread", 0.9)
	squad_min = Tuning.i("spawner.squad_size_min", 20)
	squad_max = Tuning.i("spawner.squad_size_max", 40)
	surge_interval = Tuning.f("run.surge_interval", 90.0)
	next_officer = Tuning.f("spawner.officer_first_time", 18.0)
	next_surge = surge_interval
	hp_growth = Tuning.f("enemies.hp_growth_per_min", 0.35)
	speed_growth = Tuning.f("enemies.speed_growth_per_min", 0.03)


## Distance from the hunter to just outside the visible rect along angle a.
func edge_distance(a: float) -> float:
	var c := absf(cos(a))
	var s := absf(sin(a))
	var tx := view_half.x / c if c > 0.0001 else INF
	var ty := view_half.y / s if s > 0.0001 else INF
	return minf(tx, ty) + ring_margin


func spawn_point(center: Vector2, move_dir: Vector2) -> Vector2:
	for attempt in 5:
		var a: float
		if move_dir != Vector2.ZERO and rng.randf() < bias_chance:
			a = move_dir.angle() + rng.randfn(0.0, bias_spread)
		else:
			a = rng.randf() * TAU
		var p := center + Vector2.from_angle(a) * (edge_distance(a) + rng.randf() * 140.0)
		if map_rect.grow(-30.0).has_point(p) and not field.is_blocked(p):
			return p
	return Vector2.INF


var _wg: float = 1.0
var _wr: float = 0.0
var _wb: float = 0.0


func _refresh_weights(t: float) -> void:
	_wg = Tuning.curve("spawner.type_weights.grunt", t)
	_wr = Tuning.curve("spawner.type_weights.runner", t)
	_wb = Tuning.curve("spawner.type_weights.brute", t)


func pick_type(t: float) -> int:
	var wg := _wg
	var wr := _wr
	var wb := _wb
	var r := rng.randf() * (wg + wr + wb)
	if r < wg:
		return EnemySystem.T_GRUNT
	if r < wg + wr:
		return EnemySystem.T_RUNNER
	return EnemySystem.T_BRUTE


## Returns a list of event names ("officer", "surge") for HUD banners.
func update(dt: float, t: float, center: Vector2, move_dir: Vector2) -> Array[String]:
	var events: Array[String] = []
	if not enabled:
		return events
	enemies.hp_mult = 1.0 + hp_growth * t / 60.0
	enemies.speed_mult = 1.0 + speed_growth * t / 60.0
	var target := int(Tuning.curve("spawner.target_alive", t))
	var rate := Tuning.curve("spawner.spawn_rate", t)
	if enemies.n_active < target:
		_refresh_weights(t)
		_accum += rate * dt
		var n := mini(mini(int(_accum), max_per_frame), target - enemies.n_active)
		_accum -= n
		for k in n:
			var p := spawn_point(center, move_dir)
			if p == Vector2.INF:
				continue
			if outposts != null and rng.randf() > outposts.spawn_mult_at(p):
				continue
			enemies.spawn(pick_type(t), p)
	else:
		_accum = 0.0
	if t >= next_officer:
		next_officer = t + Tuning.curve("spawner.officer_interval", t)
		if spawn_squad(center, move_dir) >= 0:
			events.append("officer")
	if t >= next_surge:
		next_surge += surge_interval
		spawn_surge(center, int(Tuning.curve("spawner.surge_count", t)))
		events.append("surge")
	return events


## Officer + 20-40 grunts sharing a squad id. Returns squad id or -1.
func spawn_squad(center: Vector2, move_dir: Vector2) -> int:
	var c := spawn_point(center, move_dir)
	if c == Vector2.INF:
		return -1
	squad_counter += 1
	var sq := squad_counter
	if enemies.spawn(EnemySystem.T_OFFICER, c, sq) < 0:
		return -1
	officers_spawned += 1
	var n := rng.randi_range(squad_min, squad_max)
	for k in n:
		var p := c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(34.0, 150.0)
		if field.is_blocked(p):
			continue
		var t := EnemySystem.T_GRUNT if rng.randf() < 0.8 else EnemySystem.T_RUNNER
		enemies.spawn(t, p, sq)
	return sq


func spawn_surge(center: Vector2, count: int) -> void:
	surges += 1
	for k in count:
		var a := TAU * k / count + rng.randf_range(-0.02, 0.02)
		var p := center + Vector2.from_angle(a) * (edge_distance(a) + rng.randf_range(-20.0, 60.0))
		if map_rect.grow(-30.0).has_point(p) and not field.is_blocked(p):
			enemies.spawn(EnemySystem.T_GRUNT if rng.randf() < 0.85 else EnemySystem.T_RUNNER, p)
