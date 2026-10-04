class_name Ironhorn
extends Node2D
## The hunt target. A real node (unlike the swarm) with a readable state machine:
##   ROAM -> PURSUE -> TELEGRAPH -> ATTACK -> RECOVER -> PURSUE  (+ STAGGER, FLEE, DEAD)
## Three breakable parts change its moveset: horns (weaker charge), tail (no sweep),
## back (+25% damage taken).

enum State { ROAM, PURSUE, TELEGRAPH, ATTACK, RECOVER, STAGGER, FLEE, DEAD }
const STATE_NAMES := ["ROAM", "PURSUE", "TELEGRAPH", "ATTACK", "RECOVER", "STAGGER", "FLEE", "DEAD"]
const PART_NAMES: Array[String] = ["horns", "back", "tail"]

const SHAPE_CIRCLE := 0
const SHAPE_ARC := 1
const SHAPE_LINE := 2

var hunt: HuntContext
var rng := RandomNumberGenerator.new()
var cfg: Dictionary = {}

var state: int = State.ROAM
var state_time: float = 0.0
var max_hp: float = 7200.0
var hp: float = 7200.0
var body_radius: float = 86.0
var speed: float = 150.0
var turn_rate: float = 2.6
var facing: Vector2 = Vector2.RIGHT
var enraged: bool = false
var time_enraged: bool = false
var dead: bool = false
var fled: bool = false

var parts: Dictionary = {}  ## name -> {offset, radius, break_hp, hp, broken}
var sprites: Dictionary = {}  ## name -> Sprite2D (+ "body")

var attack: String = ""
var attack_dir: Vector2 = Vector2.RIGHT
var attack_origin: Vector2 = Vector2.ZERO
var charge_len: float = 0.0
var charge_travel: float = 0.0
var charge_hit_player: bool = false
var telegraph_time: float = 0.0
var attack_cd: float = 1.0
var hit_flash: float = 0.0
var roam_target: Vector2 = Vector2.ZERO
var contact_cd: float = 0.0
var direct_timer: float = 0.0
var ghost_timer: float = 0.0  ## last resort when wedged: ignore rocks briefly
var rock_radius: float = 30.0  ## collision radius against rocks (smaller than the body)
var _stuck_time: float = 0.0
var _stuck_anchor: Vector2 = Vector2.INF

# telemetry
var attacks_done: Dictionary = {"charge": 0, "sweep": 0, "roar": 0}
var parts_broken: int = 0
var damage_taken: float = 0.0


func setup(p_hunt: HuntContext, seed_value: int = 0) -> void:
	hunt = p_hunt
	rng.seed = seed_value
	cfg = Tuning.d("monster")
	max_hp = float(cfg["max_hp"])
	hp = max_hp
	body_radius = float(cfg["body_radius"])
	rock_radius = float(cfg.get("rock_collision_radius", body_radius * 0.8))
	speed = float(cfg["speed"])
	turn_rate = float(cfg["turn_rate"])
	parts.clear()
	var pc: Dictionary = cfg["parts"]
	for pn in PART_NAMES:
		var p: Dictionary = pc[pn]
		var off: Array = p["offset"]
		var soff: Array = p.get("sprite_offset", off)
		parts[pn] = {
			"offset": Vector2(float(off[0]), float(off[1])),
			"sprite_offset": Vector2(float(soff[0]), float(soff[1])),
			"radius": float(p["radius"]),
			"break_hp": float(p["break_hp"]),
			"hp": float(p["break_hp"]),
			"broken": false,
		}
	_build_sprites()


func _build_sprites() -> void:
	for s: Sprite2D in sprites.values():
		s.queue_free()
	sprites.clear()
	for pn: String in ["tail", "body", "back", "horns"]:
		var s := Sprite2D.new()
		var art: String = "monster.ironhorn." + pn
		ArtRegistry.apply_to_sprite(s, art)
		if pn != "body":
			s.position = parts[pn]["sprite_offset"]
		add_child(s)
		sprites[pn] = s


func state_name() -> String:
	return STATE_NAMES[state]


func is_broken(pn: String) -> bool:
	return bool(parts[pn]["broken"])


func is_alive() -> bool:
	return not dead and not fled


func part_world(pn: String) -> Vector2:
	return position + (parts[pn]["offset"] as Vector2).rotated(rotation)


func _set_state(s: int) -> void:
	state = s
	state_time = 0.0


func _tel_mult() -> float:
	return float(cfg["enrage_telegraph_mult"]) if enraged else 1.0


func _speed() -> float:
	return speed * (float(cfg["enrage_speed_mult"]) if enraged else 1.0)


func set_time_enraged() -> void:
	time_enraged = true


# ----------------------------------------------------------------- update

func update(dt: float) -> void:
	if dead:
		return
	state_time += dt
	if hit_flash > 0.0:
		hit_flash -= dt
	if contact_cd > 0.0:
		contact_cd -= dt
	if ghost_timer > 0.0:
		ghost_timer -= dt
	if attack_cd > 0.0:
		attack_cd -= dt
	if not enraged and (time_enraged or hp <= max_hp * float(cfg["enrage_hp_frac"])):
		enraged = true
	var player := hunt.player
	var to_player := player.position - position
	var dist := to_player.length()

	match state:
		State.ROAM:
			if roam_target == Vector2.ZERO or position.distance_to(roam_target) < 60.0:
				roam_target = player.position + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(100.0, 400.0)
			_move_toward(roam_target, _speed() * 0.6, dt)
			if dist < float(cfg["aggro_range"]) or state_time > 6.0:
				_set_state(State.PURSUE)
		State.PURSUE:
			# The flow field is built for small swarm enemies; its path can squeeze past a rock
			# Ironhorn's body can't. Slide along rocks, and if that still makes no progress,
			# chase directly for a moment.
			var sd := to_player.normalized() if direct_timer > 0.0 else hunt.steer_dir(position, player.position)
			_turn_toward(sd, dt)
			position += _slide(facing * _speed() * dt, to_player)
			_track_stuck(dt)
			if attack_cd <= 0.0:
				var choice := _choose_attack(dist)
				if choice != "":
					_begin_telegraph(choice, to_player.normalized() if dist > 0.1 else facing)
		State.TELEGRAPH:
			if attack == "charge":
				# keep tracking a little during the windup
				var want := (player.position - position).normalized()
				attack_dir = attack_dir.slerp(want, minf(1.0, dt * 1.5)).normalized()
				_turn_toward(attack_dir, dt * 3.0)
			if state_time >= telegraph_time:
				_execute_attack()
		State.ATTACK:
			if attack == "charge":
				_charge_step(dt)
			elif state_time >= 0.35:
				_set_state(State.RECOVER)
			else:
				rotation += dt * 14.0 if attack == "sweep" else 0.0
		State.RECOVER:
			if state_time >= float(cfg["recover_time"]) * (0.7 if enraged else 1.0):
				attack_cd = rng.randf_range(0.3, 1.0) * (0.6 if enraged else 1.0)
				_set_state(State.PURSUE)
		State.STAGGER:
			rotation += sin(state_time * 30.0) * 0.01
			if state_time >= float(cfg["stagger_time"]):
				_set_state(State.PURSUE)
		State.FLEE:
			var away := -to_player.normalized() if dist > 0.1 else Vector2.RIGHT
			_turn_toward(away, dt * 4.0)
			position += facing * float(cfg["flee_speed"]) * dt
			modulate.a = maxf(0.0, modulate.a - dt * 0.5)
			if dist > 2400.0 or modulate.a <= 0.0:
				fled = true
				visible = false

	# body contact (not while charging, which has its own hit)
	if state != State.FLEE and not (state == State.ATTACK and attack == "charge"):
		if dist < body_radius + player.radius and contact_cd <= 0.0:
			if hunt.damage_player(float(cfg["contact_damage"]), position):
				contact_cd = 0.6
	_resolve_collisions()
	_update_visuals()


func _move_toward(p: Vector2, spd: float, dt: float) -> void:
	var d := p - position
	if d.length() < 1.0:
		return
	_turn_toward(d.normalized(), dt)
	position += facing * spd * dt


## Removes the part of a step that pushes into a rock (slide along it); a head-on step slides
## toward the side facing `toward`.
func _slide(step: Vector2, toward: Vector2) -> Vector2:
	var p := hunt.player
	if p == null:
		return step
	var np := position + step
	for rk in p.rocks:
		var c := Vector2(rk.x, rk.y)
		var rr := rk.z + rock_radius
		var d := np - c
		if d.length_squared() >= rr * rr:
			continue
		var n := (position - c).normalized()
		var into := step.dot(n)
		if into < 0.0:
			var spd := step.length()
			step -= n * into
			if step.length() < spd * 0.35:
				var t := n.orthogonal()
				if t.dot(toward) < 0.0:
					t = -t
				step = t * spd
	return step


func _track_stuck(dt: float) -> void:
	if direct_timer > 0.0:
		direct_timer -= dt
	if _stuck_anchor == Vector2.INF:
		_stuck_anchor = position
	_stuck_time += dt
	if _stuck_time >= 1.0:
		if position.distance_to(_stuck_anchor) < _speed() * 0.2:
			if direct_timer > 0.0:
				ghost_timer = 1.2  # direct chase didn't free it either: crash through
			direct_timer = 2.0
		_stuck_time = 0.0
		_stuck_anchor = position


func _turn_toward(dir: Vector2, dt: float) -> void:
	var a := facing.angle()
	var target_a := dir.angle()
	var diff := wrapf(target_a - a, -PI, PI)
	var stepv := clampf(diff, -turn_rate * dt, turn_rate * dt)
	facing = Vector2.from_angle(a + stepv)
	rotation = facing.angle()


func _resolve_collisions() -> void:
	var p := hunt.player
	if p == null:
		return
	var mr := p.map_rect
	var hit_rock := false
	for rk in (p.rocks if ghost_timer <= 0.0 else [] as Array[Vector3]):
		var c := Vector2(rk.x, rk.y)
		var rr := rk.z + rock_radius
		var d := position - c
		var l2 := d.length_squared()
		if l2 < rr * rr:
			var l := sqrt(l2)
			position = c + (d / l if l > 0.001 else Vector2.RIGHT) * rr
			hit_rock = true
	position.x = clampf(position.x, mr.position.x + body_radius, mr.end.x - body_radius)
	position.y = clampf(position.y, mr.position.y + body_radius, mr.end.y - body_radius)
	if hit_rock and state == State.ATTACK and attack == "charge":
		# slammed into a rock: the charge ends and it's briefly dazed
		hunt.add_shake(0.4)
		_set_state(State.STAGGER)
		state_time = float(cfg["stagger_time"]) * 0.4


func _update_visuals() -> void:
	var base := ArtRegistry.color("fx.enrage") if enraged else Color(1, 1, 1)
	if hit_flash > 0.0:
		base = ArtRegistry.color("fx.monster_hit")
	if state == State.TELEGRAPH:
		var pulse := 0.5 + 0.5 * sin(state_time * 30.0)
		base = base.lerp(Color(1.6, 0.6, 0.5), 0.35 * pulse)
	for pn: String in sprites:
		var s: Sprite2D = sprites[pn]
		s.self_modulate = base


# ----------------------------------------------------------------- attacks

func available_attacks(dist: float) -> Array[String]:
	var out: Array[String] = []
	var ar := float(cfg["attack_range"])
	if dist <= ar:
		if not is_broken("tail"):
			out.append("sweep")
		out.append("roar")
		out.append("charge")
	elif dist <= float(cfg["charge_range"]):
		out.append("charge")
	return out


func _choose_attack(dist: float) -> String:
	var opts := available_attacks(dist)
	if opts.is_empty():
		return ""
	var atk: Dictionary = cfg["attacks"]
	var total := 0.0
	for o in opts:
		total += float(atk[o]["weight"])
	var r := rng.randf() * total
	for o in opts:
		r -= float(atk[o]["weight"])
		if r <= 0.0:
			return o
	return opts[opts.size() - 1]


func _begin_telegraph(which: String, dir: Vector2) -> void:
	attack = which
	attack_dir = dir
	attack_origin = position
	var a: Dictionary = cfg["attacks"][which]
	telegraph_time = float(a["telegraph"]) * _tel_mult()
	if which == "charge":
		charge_len = float(a["distance"]) * (float(a["broken_mult"]) if is_broken("horns") else 1.0)
	_set_state(State.TELEGRAPH)


func _execute_attack() -> void:
	var a: Dictionary = cfg["attacks"][attack]
	attacks_done[attack] = int(attacks_done[attack]) + 1
	var player := hunt.player
	match attack:
		"charge":
			attack_origin = position
			charge_travel = 0.0
			charge_hit_player = false
			facing = attack_dir
			rotation = facing.angle()
		"sweep":
			var r := float(a["radius"])
			var half := deg_to_rad(float(a["arc_deg"])) * 0.5
			if Geom.arc_circle(position, r, -facing, half, player.position, player.radius):
				hunt.damage_player(float(a["damage"]), position)
			hunt.fx_over.arc(position, -facing, r, half, "fx.telegraph_edge", 0.25)
			hunt.add_shake(0.3)
		"roar":
			var r := float(a["radius"])
			if position.distance_to(player.position) <= r + player.radius:
				hunt.damage_player(float(a["damage"]), position)
				hunt.slow_player(float(a["slow_time"]))
			hunt.fx_over.ring(position, r, "fx.telegraph_edge", 0.5, 18.0, 0.8)
			hunt.spawn_grunts_around(position, int(a["spawn_count"]), body_radius + 40.0, r)
			hunt.add_shake(0.5)
	_set_state(State.ATTACK)


func _charge_step(dt: float) -> void:
	var a: Dictionary = cfg["attacks"]["charge"]
	var spd := float(a["speed"]) * (1.15 if enraged else 1.0)
	var stepv := spd * dt
	var prev := position
	position += attack_dir * stepv
	charge_travel += stepv
	# crush the swarm in the path — they count as the hunter's KOs
	hunt.kill_enemies_in_circle(position + attack_dir * 40.0, float(cfg["crush_radius"]), EnemySystem.CAUSE_MONSTER)
	if not charge_hit_player:
		var w := float(a["width"]) * 0.5
		var player := hunt.player
		if Geom.capsule_circle(prev, position, w + body_radius * 0.4, player.position, player.radius):
			var dmgv := float(a["damage"]) * (float(a["broken_mult"]) if is_broken("horns") else 1.0)
			if hunt.damage_player(dmgv, position):
				charge_hit_player = true
	if charge_travel >= charge_len:
		_set_state(State.RECOVER)


# ----------------------------------------------------------------- counters & aiming

## True while the telegraphed attack would hit a circle at p (radius r).
func threatens(p: Vector2, r: float) -> bool:
	if state != State.TELEGRAPH:
		return false
	var a: Dictionary = cfg["attacks"][attack]
	match attack:
		"charge":
			var w := float(a["width"]) * 0.5 + body_radius * 0.4
			return Geom.capsule_circle(position, position + attack_dir * charge_len, w, p, r)
		"sweep":
			return Geom.arc_circle(position, float(a["radius"]), -facing, deg_to_rad(float(a["arc_deg"])) * 0.5, p, r)
		"roar":
			return Geom.circle_circle(position, float(a["radius"]), p, r)
	return false


## Perfect-counter window: the last `window` seconds of a telegraph that threatens p.
func counter_window(p: Vector2, r: float, window: float) -> bool:
	return state == State.TELEGRAPH and telegraph_time - state_time <= window and threatens(p, r)


## A perfect counter cancels the attack: it goes straight to recovery, as if the attack had
## whiffed, plus `seconds` of extra recovery.
func interrupt(seconds: float) -> void:
	if not is_alive():
		return
	_set_state(State.RECOVER)
	state_time = -seconds
	hit_flash = 0.15


## Distance along a ray (a, unit dir) where a round of half-width w first touches the body
## or a part; INF if it misses.
func ray_entry(a: Vector2, dir: Vector2, w: float) -> float:
	if not is_alive() or state == State.FLEE:
		return INF
	var best := _ray_circle(a, dir, position, body_radius + w)
	for pn in PART_NAMES:
		best = minf(best, _ray_circle(a, dir, part_world(pn), float(parts[pn]["radius"]) + w))
	return best


static func _ray_circle(a: Vector2, dir: Vector2, c: Vector2, r: float) -> float:
	var ac := c - a
	var tc := ac.dot(dir)
	var d2 := ac.length_squared() - tc * tc
	if d2 > r * r:
		return INF
	var t := tc - sqrt(r * r - d2)
	if t < 0.0:
		return 0.0 if ac.length_squared() <= r * r else INF
	return t


## Where precision weapons aim: the nearest unbroken part to `from`, else the body.
func aim_point(from: Vector2) -> Vector2:
	var best := position
	var best_d := INF
	for pn in PART_NAMES:
		if is_broken(pn):
			continue
		var p := part_world(pn)
		var d := p.distance_squared_to(from)
		if d < best_d:
			best_d = d
			best = p
	return best


# ----------------------------------------------------------------- damage

## Applies a weapon hit if the shape overlaps the body or any part. Returns damage dealt.
func take_hit(shape: int, a: Vector2, b: Vector2, r: float, dir: Vector2, half: float, dmg: float) -> float:
	if not is_alive() or state == State.FLEE:
		return 0.0
	var any := _overlaps(shape, a, b, r, dir, half, position, body_radius)
	var hit_parts: Array[String] = []
	for pn in PART_NAMES:
		var pd: Dictionary = parts[pn]
		if _overlaps(shape, a, b, r, dir, half, part_world(pn), float(pd["radius"])):
			any = true
			if not bool(pd["broken"]):
				hit_parts.append(pn)
	if not any:
		return 0.0
	return apply_damage(dmg, hit_parts)


func apply_damage(dmg: float, hit_parts: Array[String] = []) -> float:
	if not is_alive():
		return 0.0
	var dealt := dmg * (float(cfg["back_break_damage_mult"]) if is_broken("back") else 1.0)
	hp -= dealt
	damage_taken += dealt
	hit_flash = 0.06
	for pn in hit_parts:
		var pd: Dictionary = parts[pn]
		pd["hp"] = float(pd["hp"]) - dmg
		if float(pd["hp"]) <= 0.0 and not bool(pd["broken"]):
			break_part(pn)
	if hp <= 0.0:
		die()
	return dealt


func break_part(pn: String) -> void:
	var pd: Dictionary = parts[pn]
	pd["broken"] = true
	pd["hp"] = 0.0
	parts_broken += 1
	if sprites.has(pn):
		ArtRegistry.apply_to_sprite(sprites[pn], "monster.ironhorn.%s_broken" % pn)
	var at := part_world(pn)
	if state != State.DEAD:
		_set_state(State.STAGGER)
	hunt.on_monster_part_broken(pn, at)


func die() -> void:
	if dead:
		return
	dead = true
	hp = 0.0
	_set_state(State.DEAD)
	hunt.on_monster_died(position)


func flee() -> void:
	if is_alive():
		_set_state(State.FLEE)


static func _overlaps(shape: int, a: Vector2, b: Vector2, r: float, dir: Vector2, half: float, pc: Vector2, pr: float) -> bool:
	match shape:
		SHAPE_CIRCLE:
			return Geom.circle_circle(a, r, pc, pr)
		SHAPE_ARC:
			return Geom.arc_circle(a, r, dir, half, pc, pr)
		SHAPE_LINE:
			return Geom.capsule_circle(a, b, r, pc, pr)
	return false


# ----------------------------------------------------------------- drawing

## Telegraphs, drawn under the swarm by the hunt's FX layer.
func draw_world_under(ci: CanvasItem) -> void:
	if not is_alive():
		return
	if state != State.TELEGRAPH:
		return
	var a: Dictionary = cfg["attacks"][attack]
	var t := clampf(state_time / maxf(telegraph_time, 0.01), 0.0, 1.0)
	var fill := ArtRegistry.color("fx.telegraph")
	fill.a *= 0.4 + 0.6 * t
	var edge := ArtRegistry.color("fx.telegraph_edge")
	match attack:
		"charge":
			var w := float(a["width"]) * 0.5 + body_radius * 0.4
			var end := position + attack_dir * charge_len
			var perp := attack_dir.orthogonal() * w
			ci.draw_colored_polygon(PackedVector2Array([position + perp, end + perp, end - perp, position - perp]), fill)
			var fill_end := position.lerp(end, t)
			ci.draw_colored_polygon(PackedVector2Array([position + perp, fill_end + perp, fill_end - perp, position - perp]), Color(edge.r, edge.g, edge.b, 0.25))
			ci.draw_polyline(PackedVector2Array([position + perp, end + perp, end - perp, position - perp, position + perp]), edge, 3.0)
		"sweep":
			var r := float(a["radius"])
			var half := deg_to_rad(float(a["arc_deg"])) * 0.5
			ci.draw_colored_polygon(FX.pie(position, -facing, r, half), fill)
			ci.draw_colored_polygon(FX.pie(position, -facing, r * t, half), Color(edge.r, edge.g, edge.b, 0.22))
			ci.draw_arc(position, r, (-facing).angle() - half, (-facing).angle() + half, 48, edge, 3.0)
		"roar":
			var r := float(a["radius"])
			ci.draw_circle(position, r, fill)
			ci.draw_circle(position, r * t, Color(edge.r, edge.g, edge.b, 0.2))
			ci.draw_arc(position, r, 0.0, TAU, 64, edge, 3.0)
