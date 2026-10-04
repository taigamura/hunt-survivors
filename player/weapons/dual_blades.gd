class_name DualBlades
extends Weapon
## "Never stop moving." Full-deflection movement builds momentum (0..1); a whirl of blades
## scales with it. At full momentum you leave damaging afterimages. Whipping the stick
## back (>150 degrees) at high momentum triggers a dash cut.
## Gesture moves: Dash Cut (any direction, spends momentum), Flurry, Shadow Step, Blade Vortex
## (cashes in all momentum), X Slash.

var build_time: float = 2.0
var decay_per_sec: float = 1.6
var high_deflection: float = 0.8
var speed_bonus: float = 0.18
var whirl: Dictionary = {}
var trail_cfg: Dictionary = {}
var dash_cfg: Dictionary = {}

var momentum: float = 0.0
var whirl_timer: float = 0.0
var spin: float = 0.0
var trail_drop_timer: float = 0.0
var trail := GroundPatches.new(24, 0.15)
var burn := GroundPatches.new(40, 0.3)
var anchor_dir: Vector2 = Vector2.ZERO
var anchor_valid: bool = false
var stop_time: float = 0.0
var dash_cd: float = 0.0

# observable for tests / telemetry
var dash_cuts: int = 0
var whirl_ticks: int = 0
var last_whirl_radius: float = 0.0


func _init() -> void:
	id = "dual_blades"


func setup(p_hunt: HuntContext, p_player: Player) -> void:
	super.setup(p_hunt, p_player)
	var cfg := Tuning.d("weapons.dual_blades")
	display_name = String(cfg.get("name", "Dual Blades"))
	build_time = float(cfg["build_time"])
	decay_per_sec = float(cfg["decay_per_sec"])
	high_deflection = float(cfg["high_deflection"])
	speed_bonus = float(cfg["speed_bonus"])
	whirl = cfg["whirl"]
	trail_cfg = cfg["trail"]
	dash_cfg = cfg["dash"]
	upgrade_defs = cfg["upgrades"]
	trail.tick = float(trail_cfg["tick"])


func effective_build_time() -> float:
	return build_time * clampf(1.0 - up_value("db_build"), 0.3, 1.0)


func effective_decay() -> float:
	return decay_per_sec * clampf(1.0 - up_value("db_decay"), 0.15, 1.0)


func trail_threshold() -> float:
	return float(trail_cfg["min_momentum"]) - (0.2 if up("db_trail") > 0 else 0.0)


func whirl_radius() -> float:
	return lerpf(float(whirl["radius_min"]), float(whirl["radius_max"]), momentum) * (1.0 + up_value("db_radius")) * player.area_mult


func update(dt: float, move: Vector2) -> void:
	var mag := move.length()
	var moving := mag > 0.0001
	# --- momentum
	if mag >= high_deflection:
		momentum = minf(1.0, momentum + dt / effective_build_time())
	else:
		var rate := effective_decay() * (0.6 if moving else 1.0)
		momentum = maxf(0.0, momentum - rate * dt)
	player.weapon_speed_mult = 1.0 + speed_bonus * momentum

	# --- dash cut on sharp reversal
	if dash_cd > 0.0:
		dash_cd -= dt
	if moving:
		var dir := move / mag
		if anchor_valid and momentum >= float(dash_cfg["min_momentum"]) and dash_cd <= 0.0 and not player.is_dashing():
			if dir.dot(anchor_dir) <= cos(deg_to_rad(float(dash_cfg["reverse_deg"]))):
				dash_cut(dir)
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
		if stop_time > float(dash_cfg["grace"]):
			anchor_valid = false

	# --- whirl
	spin += dt * lerpf(7.0, 20.0, momentum)
	whirl_timer -= dt * player.haste_mult
	if whirl_timer <= 0.0:
		whirl_timer = lerpf(float(whirl["interval_max"]), float(whirl["interval_min"]), momentum)
		var r := whirl_radius()
		last_whirl_radius = r
		var damage := dmg(lerpf(float(whirl["damage_min"]), float(whirl["damage_max"]), momentum))
		hunt.hit_circle(player.position, r, damage, float(whirl["knock"]))
		whirl_ticks += 1

	# --- afterimage trail
	if momentum >= trail_threshold() - 0.0001:
		trail_drop_timer -= dt
		if trail_drop_timer <= 0.0:
			trail_drop_timer = float(trail_cfg["drop_interval"])
			var life := float(trail_cfg["life"]) * (1.0 + up_value("db_trail"))
			trail.add(player.position, float(trail_cfg["radius"]) * player.area_mult, life, dmg(float(trail_cfg["damage"])))
	trail.update(dt, hunt)
	burn.update(dt, hunt)


func dash_cut(dir: Vector2, power: float = 1.0) -> void:
	var dist := float(dash_cfg["distance"])
	var a := player.position
	var b := a + dir * dist
	var ignite := up("db_ignite")
	var damage := dmg(float(dash_cfg["damage"])) * (1.0 + up_value("db_ignite")) * power
	player.start_dash(dir, dist, float(dash_cfg["duration"]))
	hunt.hit_line(a, b, float(dash_cfg["width"]) * player.area_mult, damage, float(dash_cfg["knock"]), HuntContext.HIT_BIG)
	hunt.fx_over.line(a, b, 26.0, "fx.dash", 0.22)
	hunt.fx_over.line(a, b, 8.0, "fx.slash_gs3", 0.3)
	hunt.add_shake(0.35)
	hunt.haptic("dash_cut")
	if ignite > 0:
		var steps := 7
		for k in steps + 1:
			burn.add(a.lerp(b, k / float(steps)), 30.0 * player.area_mult, 2.2, dmg(5.0 + 3.0 * ignite))
	dash_cd = float(dash_cfg["cooldown"])
	dash_cuts += 1


func perform_move(move_id: String, def: Dictionary, ctx: Dictionary) -> bool:
	var dir: Vector2 = ctx["dir"]
	var power := float(ctx["power"])
	match move_id:
		"db_aimed_dash":
			if player.is_dashing():
				return false
			var strong := momentum >= float(def["min_momentum"])
			dash_cut(dir, power * (1.0 if strong else float(def["weak_mult"])))
			dash_cd = 0.0
			momentum = maxf(0.0, momentum - float(def["momentum_cost"]))
			return true
		"db_flurry":
			var r := float(def["radius"]) * player.area_mult * (1.0 + up_value("db_radius"))
			var half := deg_to_rad(float(def["half_angle_deg"]))
			for h in int(def["hits"]):
				var d := dir.rotated((h - 1) * 0.35)
				hunt.hit_arc(player.position, d, r, half, move_dmg(def, "damage", ctx), float(def["knock"]))
				hunt.fx_over.arc(player.position, d, r, half * 0.7, "fx.whirl", 0.1 + 0.04 * h)
			momentum = minf(1.0, momentum + float(def["momentum_gain"]))
			return true
		"db_shadow":
			if player.is_dashing():
				return false
			var a := player.position
			var b := target_point(ctx, float(def["distance"]))
			if a.distance_to(b) > float(def["distance"]):
				b = a + (b - a).normalized() * float(def["distance"])
			if a.distance_to(b) < 1.0:
				b = a + dir * float(def["distance"])
			player.start_dash((b - a).normalized(), a.distance_to(b), float(def["duration"]))
			player.iframes = maxf(player.iframes, float(def["duration"]) + 0.2)
			hunt.hit_line(a, b, float(def["width"]) * player.area_mult, move_dmg(def, "damage", ctx), 260.0, HuntContext.HIT_BIG)
			hunt.fx_over.line(a, b, 22.0, "fx.dash", 0.25)
			var n := int(def["afterimages"])
			for k in n:
				trail.add(a.lerp(b, float(k) / maxf(1.0, n - 1)), float(trail_cfg["radius"]) * player.area_mult, float(trail_cfg["life"]) * 2.0, dmg(float(trail_cfg["damage"])) * power)
			hunt.haptic("dash_cut")
			return true
		"db_vortex":
			var r := (float(def["radius"]) + float(def["radius_per_momentum"]) * momentum) * player.area_mult
			var d := dmg(float(def["damage"]) + float(def["damage_per_momentum"]) * momentum) * power
			hunt.hit_circle(player.position, r, d, float(def["knock"]), HuntContext.HIT_BIG)
			hunt.fx_over.ring(player.position, r, "fx.whirl", 0.35, 18.0, 0.6)
			hunt.fx_over.arc(player.position, Vector2.from_angle(spin), r, PI, "fx.whirl", 0.25)
			hunt.add_shake(0.3 + 0.4 * momentum)
			momentum = 0.0
			return true
		"db_xslash":
			var c := target_point(ctx, float(def["length"]) * 0.5)
			var half_len := float(def["length"]) * 0.5
			var w := float(def["width"]) * player.area_mult
			for sgn in [-1.0, 1.0]:
				var d := dir.rotated(sgn * PI * 0.25)
				hunt.hit_line(c - d * half_len, c + d * half_len, w, move_dmg(def, "damage", ctx), float(def["knock"]), HuntContext.HIT_BIG)
				hunt.fx_over.line(c - d * half_len, c + d * half_len, 18.0, "fx.dash", 0.25)
			hunt.add_shake(0.25)
			return true
	return super.perform_move(move_id, def, ctx)


func draw_local(ci: CanvasItem) -> void:
	var r := player.radius + 13.0
	ci.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(0, 0, 0, 0.35), 5.0)
	var col := ArtRegistry.color("fx.momentum")
	if momentum > 0.0:
		ci.draw_arc(Vector2.ZERO, r, -PI * 0.5, -PI * 0.5 + TAU * momentum, 40, col, 5.0)
	# whirling blades
	var wr := whirl_radius()
	var wc := ArtRegistry.color("fx.whirl")
	wc.a = 0.25 + 0.55 * momentum
	var blades := 2 if momentum < 0.5 else 3
	for k in blades:
		var a := spin + TAU * k / blades
		var p := Vector2.from_angle(a) * wr
		var tangent := Vector2.from_angle(a + PI * 0.5)
		ci.draw_line(p - tangent * 14.0, p + tangent * 14.0, wc, 5.0)
	if momentum > 0.5:
		var ring := wc
		ring.a *= 0.35
		ci.draw_arc(Vector2.ZERO, wr, spin, spin + PI * 1.2, 24, ring, 3.0)
	if momentum >= 1.0:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.03)
		ci.draw_arc(Vector2.ZERO, r + 6.0 + 2.0 * pulse, 0.0, TAU, 40, Color(col.r, col.g, col.b, 0.7), 2.0)


func draw_world_under(ci: CanvasItem) -> void:
	trail.draw_afterimages(ci, player.radius + 4.0)
	burn.draw_flames(ci)
