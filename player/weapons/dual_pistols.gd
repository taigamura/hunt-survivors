class_name DualPistols
extends Weapon
## Twin Fangs: "Gun kata." While moving, both guns fire out to your sides (perpendicular to
## your heading), each tracking the nearest foe within a cone on its side: you aim by choosing
## which way to run. Standing still, they alternate at the nearest target. A sharp snap-turn at
## speed fires a ring of bullets (detected like the Dual Blades reversal).
## Gesture moves: Bullet Spin, Slide Shot, Barrage, Gun Kata, Point Blank.

var shot_range: float = 460.0
var width: float = 6.0
var cfg: Dictionary = {}
var spin_cfg: Dictionary = {}

var fire_timer: float = 0.0
var spin_cd: float = 0.0
var anchor_dir: Vector2 = Vector2.ZERO
var anchor_valid: bool = false
var stop_time: float = 0.0
var alt: bool = false
var kata_timer: float = 0.0
var kata_tick: float = 0.0
var kata_def: Dictionary = {}
var kata_power: float = 1.0
var kata_angle: float = 0.0
var rng := RandomNumberGenerator.new()

# observable for tests / telemetry
var shots: int = 0
var spins: int = 0


func _init() -> void:
	id = "dual_pistols"
	rng.seed = 23


func setup(p_hunt: HuntContext, p_player: Player) -> void:
	super.setup(p_hunt, p_player)
	cfg = Tuning.d("weapons.dual_pistols")
	display_name = String(cfg.get("name", "Twin Fangs"))
	shot_range = float(cfg["range"])
	width = float(cfg["width"])
	spin_cfg = cfg["spin"]
	upgrade_defs = cfg["upgrades"]


func shot_damage() -> float:
	return dmg(float(cfg["damage"])) * (1.0 + up_value("dp_damage"))


func pierce() -> int:
	return int(cfg["pierce"]) + int(up_value("dp_pierce"))


func _fire(dir: Vector2, damage: float, p_pierce: int, flags: int = 0) -> void:
	var end := hunt.shoot(player.position, dir, shot_range, width, damage, float(cfg["knock"]), p_pierce, flags)
	hunt.fx_over.line(player.position + dir * player.radius, end, 3.5, "fx.tracer", 0.07)
	shots += 1


func _ring(n: int, damage: float, p_pierce: int, offset: float = 0.0) -> void:
	for k in n:
		_fire(Vector2.from_angle(offset + TAU * k / n), damage, p_pierce)


func update(dt: float, move: Vector2) -> void:
	var mag := move.length()
	var moving := mag > 0.0001
	# --- snap-turn spin
	if spin_cd > 0.0:
		spin_cd -= dt
	if moving:
		var dir := move / mag
		if anchor_valid and mag >= float(spin_cfg["min_deflection"]) and spin_cd <= 0.0:
			if dir.dot(anchor_dir) <= cos(deg_to_rad(float(spin_cfg["turn_deg"]))):
				_ring(int(spin_cfg["shots"]) + int(up_value("dp_spin")), dmg(float(spin_cfg["damage"])) * (1.0 + up_value("dp_damage")), pierce(), rng.randf() * TAU)
				spin_cd = float(spin_cfg["cooldown"])
				spins += 1
				hunt.add_shake(0.15)
				anchor_dir = dir
		if anchor_valid:
			anchor_dir = (anchor_dir + (dir - anchor_dir) * minf(1.0, dt / 0.15)).normalized()
			if anchor_dir == Vector2.ZERO:
				anchor_dir = dir
		else:
			anchor_dir = dir
			anchor_valid = true
		stop_time = 0.0
	else:
		stop_time += dt
		if stop_time > float(spin_cfg["grace"]):
			anchor_valid = false

	# --- Gun Kata
	if kata_timer > 0.0:
		kata_timer -= dt
		kata_tick -= dt
		if kata_tick <= 0.0:
			kata_tick = float(kata_def["interval"])
			kata_angle += 0.4
			_ring(int(kata_def["shots"]), dmg(float(kata_def["damage"])) * kata_power, int(kata_def["pierce"]), kata_angle)

	# --- the guns
	fire_timer -= dt * player.haste_mult * (1.0 + up_value("dp_rate"))
	if fire_timer > 0.0:
		return
	var jitter := deg_to_rad(float(cfg["jitter_deg"]))
	if moving:
		fire_timer = float(cfg["side_interval"])
		var seek := deg_to_rad(float(cfg["side_seek_deg"]) + up_value("dp_seek"))
		var side := player.move_dir.orthogonal()
		var fired := false
		for sgn in [1.0, -1.0]:
			var base: Vector2 = side * sgn
			var t := hunt.nearest_in_arc(player.position, shot_range, base, seek)
			if t == Vector2.INF:
				continue
			_fire((t - player.position).normalized().rotated(rng.randf_range(-jitter, jitter)), shot_damage(), pierce())
			fired = true
		if not fired:
			fire_timer = 0.05
	else:
		var t := hunt.auto_target(player.position, shot_range)
		if t == Vector2.INF:
			fire_timer = 0.05
			return
		fire_timer = float(cfg["still_interval"])
		alt = not alt
		var d := (t - player.position).normalized()
		_fire(d.rotated((0.06 if alt else -0.06) + rng.randf_range(-jitter, jitter) * 0.5), shot_damage(), pierce())


func perform_move(move_id: String, def: Dictionary, ctx: Dictionary) -> bool:
	var dir: Vector2 = ctx["dir"]
	match move_id:
		"dp_spin":
			_ring(int(def["shots"]), move_dmg(def, "damage", ctx), int(def["pierce"]) + int(up_value("dp_pierce")), rng.randf() * TAU)
			hunt.add_shake(0.2)
			return true
		"dp_slide":
			if player.is_dashing():
				return false
			var dur := float(def["duration"])
			player.start_dash(dir, float(def["distance"]), dur)
			player.iframes = maxf(player.iframes, dur + 0.1)
			var n := int(def["shots"])
			var spread := deg_to_rad(float(def["spread_deg"]))
			for k in n:
				_fire(dir.rotated(lerpf(-spread * 0.5, spread * 0.5, float(k) / maxf(1.0, n - 1))), move_dmg(def, "damage", ctx), int(def["pierce"]))
			return true
		"dp_barrage":
			var q := target_point(ctx, float(def["reach"]))
			var r := float(def["radius"]) * player.area_mult
			var br := float(def["blast_radius"]) * player.area_mult
			var n := int(def["hits"])
			for k in n:
				var spot := q if k == 0 else q + Vector2.from_angle(TAU * k / (n - 1) + rng.randf() * 0.5) * r * rng.randf_range(0.4, 0.9)
				hunt.hit_circle(spot, br, move_dmg(def, "damage", ctx), 120.0)
				hunt.fx_over.line(player.position, spot, 3.0, "fx.tracer", 0.12)
				hunt.fx_under.circle(spot, br, "fx.explosion", 0.2)
			hunt.add_shake(0.25)
			return true
		"dp_kata":
			kata_timer = float(def["duration"])
			kata_tick = 0.0
			kata_def = def
			kata_power = float(ctx["power"])
			return true
		"dp_point":
			var t := hunt.auto_target(player.position, float(def["range"]))
			if t == Vector2.INF:
				return false
			var d := (t - player.position).normalized()
			for sgn in [-1.0, 1.0]:
				var end := hunt.shoot(player.position, d.rotated(sgn * 0.04), float(def["range"]), width * 1.5, move_dmg(def, "damage", ctx), 260.0, int(def["pierce"]), HuntContext.HIT_BIG)
				hunt.fx_over.line(player.position, end, 8.0, "fx.tracer_heavy", 0.15)
			hunt.add_shake(0.25)
			return true
	return super.perform_move(move_id, def, ctx)


func draw_local(ci: CanvasItem) -> void:
	# two gun barrels at your sides
	var side := player.move_dir.orthogonal()
	var c := ArtRegistry.color("fx.tracer")
	for sgn in [1.0, -1.0]:
		var base: Vector2 = side * sgn * (player.radius + 6.0)
		ci.draw_line(base, base + side * sgn * 12.0, c, 5.0)
	if kata_timer > 0.0:
		ci.draw_arc(Vector2.ZERO, player.radius + 20.0, kata_angle, kata_angle + PI * 1.5, 24, ArtRegistry.color("fx.gold"), 3.0)
	if spin_cd <= 0.0:
		ci.draw_arc(Vector2.ZERO, player.radius + 13.0, 0.0, TAU, 40, Color(c.r, c.g, c.b, 0.35), 2.0)
