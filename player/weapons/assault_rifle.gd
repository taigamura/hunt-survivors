class_name AssaultRifle
extends Weapon
## "Spin up and never let go." Fires a continuous stream whose rate climbs while there is
## something to shoot (spin-up) and falls off when there isn't. Moving, it rakes along your
## heading, snapping to the nearest foe inside a forward cone; walking (part stick) tightens the
## spread, running widens it. Standing still locks onto the nearest target.
## Gesture moves: Grenade, Piercing Burst, Suppressive Fire, Airstrike.

var cfg: Dictionary = {}
var spin: float = 0.0  ## 0..1 spin-up
var has_target: bool = false
var fire_timer: float = 0.0
var rng := RandomNumberGenerator.new()
var burn := GroundPatches.new(40, 0.3)
## pending explosions (grenades, airstrikes): {p, t, r, d, k}
var blasts: Array[Dictionary] = []
var suppress_timer: float = 0.0
var suppress_tick: float = 0.0
var suppress_dir: Vector2 = Vector2.RIGHT
var suppress_def: Dictionary = {}
var suppress_power: float = 1.0

# observable for tests / telemetry
var rounds: int = 0
var explosions: int = 0


func _init() -> void:
	id = "assault_rifle"
	rng.seed = 31


func setup(p_hunt: HuntContext, p_player: Player) -> void:
	super.setup(p_hunt, p_player)
	cfg = Tuning.d("weapons.assault_rifle")
	display_name = String(cfg.get("name", "Assault Rifle"))
	upgrade_defs = cfg["upgrades"]


func shot_range() -> float:
	return float(cfg["range"]) * (1.0 + up_value("ar_range"))


func interval() -> float:
	return lerpf(float(cfg["interval_start"]), float(cfg["interval_min"]), spin) / player.haste_mult


func pierce() -> int:
	return int(cfg["pierce"]) + int(up_value("ar_pierce"))


func round_damage() -> float:
	return dmg(float(cfg["damage"])) * (1.0 + up_value("ar_damage"))


func update(dt: float, move: Vector2) -> void:
	var mag := move.length()
	var p := player.position
	var reach := shot_range()
	if has_target:
		spin = minf(1.0, spin + dt / (float(cfg["spinup_time"]) * clampf(1.0 - up_value("ar_spin"), 0.25, 1.0)))
	else:
		spin = maxf(0.0, spin - dt / float(cfg["spindown_time"]))
	fire_timer -= dt
	if fire_timer <= 0.0:
		# aim only when a round is due (range queries are the expensive part)
		var aim := Vector2.INF
		var spread_deg := float(cfg["spread_still_deg"])
		if mag > 0.0001:
			var t := hunt.nearest_in_arc(p, reach, player.facing, deg_to_rad(float(cfg["seek_deg"])))
			if t != Vector2.INF:
				aim = (t - p).normalized()
			elif hunt.auto_target(p, reach) != Vector2.INF:
				aim = player.facing  # something is in range: rake ahead
			spread_deg = float(cfg["spread_run_deg"]) if mag >= float(cfg["walk_below"]) else float(cfg["spread_walk_deg"])
		else:
			var t := hunt.auto_target(p, reach)
			if t != Vector2.INF and t.distance_to(p) > 1.0:
				aim = (t - p).normalized()
		has_target = aim != Vector2.INF
		if not has_target:
			fire_timer = 0.1
		else:
			fire_timer = interval()
			var spread := deg_to_rad(spread_deg)
			var d := aim.rotated(rng.randf_range(-spread, spread))
			var end := hunt.shoot(p, d, reach, float(cfg["width"]), round_damage(), float(cfg["knock"]), pierce())
			hunt.fx_over.line(p + d * player.radius, end, 3.0, "fx.tracer", 0.06)
			rounds += 1
			if up("ar_fire") > 0 and rounds % 8 == 0:
				burn.add(end, 28.0 * player.area_mult, 2.0, dmg(up_value("ar_fire")))

	# --- Suppressive Fire stream
	if suppress_timer > 0.0:
		suppress_timer -= dt
		suppress_tick -= dt
		while suppress_tick <= 0.0 and suppress_timer > -0.01:
			suppress_tick += float(suppress_def["interval"])
			var s := deg_to_rad(float(suppress_def["spread_deg"]))
			var d := suppress_dir.rotated(rng.randf_range(-s, s))
			var end := hunt.shoot(p, d, reach, float(cfg["width"]), dmg(float(suppress_def["damage"])) * suppress_power, 70.0, int(suppress_def["pierce"]))
			hunt.fx_over.line(p + d * player.radius, end, 4.0, "fx.tracer_heavy", 0.06)

	# --- pending explosions
	var k := 0
	while k < blasts.size():
		var b := blasts[k]
		b["t"] = float(b["t"]) - dt
		if float(b["t"]) <= 0.0:
			_explode(b)
			blasts.remove_at(k)
		else:
			k += 1
	burn.update(dt, hunt)


func _explode(b: Dictionary) -> void:
	var q: Vector2 = b["p"]
	var r := float(b["r"])
	hunt.hit_circle(q, r, float(b["d"]), float(b["k"]), HuntContext.HIT_BIG)
	hunt.fx_over.circle(q, r, "fx.explosion", 0.25)
	hunt.fx_over.ring(q, r, "fx.explosion", 0.3, 12.0, 0.6)
	hunt.add_shake(0.25)
	explosions += 1


func _queue_blast(q: Vector2, delay: float, def: Dictionary, ctx: Dictionary) -> void:
	blasts.append({"p": q, "t": delay, "r": float(def["radius"]) * player.area_mult, "d": move_dmg(def, "damage", ctx), "k": float(def["knock"])})


func perform_move(move_id: String, def: Dictionary, ctx: Dictionary) -> bool:
	var dir: Vector2 = ctx["dir"]
	var p := player.position
	match move_id:
		"ar_grenade":
			var q := target_point(ctx, float(def["reach"]))
			_queue_blast(q, float(def["fuse"]), def, ctx)
			hunt.fx_over.line(p, q, 3.0, "fx.explosion", float(def["fuse"]))
			return true
		"ar_burst":
			var n := int(def["shots"])
			var spread := deg_to_rad(float(def["spread_deg"]))
			for k in n:
				var d := dir.rotated(lerpf(-spread, spread, float(k) / maxf(1.0, n - 1)))
				var end := hunt.shoot(p, d, shot_range(), float(cfg["width"]) * 1.4, move_dmg(def, "damage", ctx), 140.0, int(def["pierce"]), HuntContext.HIT_BIG if k == 0 else HuntContext.HIT_NONE)
				hunt.fx_over.line(p + d * player.radius, end, 6.0, "fx.tracer_heavy", 0.12)
			hunt.add_shake(0.2)
			return true
		"ar_suppress":
			suppress_timer = float(def["duration"])
			suppress_tick = 0.0
			suppress_dir = dir
			suppress_def = def
			suppress_power = float(ctx["power"])
			return true
		"ar_airstrike":
			for k in int(def["count"]):
				_queue_blast(p + dir * float(def["spacing"]) * (k + 1), 0.3 + float(def["delay"]) * k, def, ctx)
			return true
	return super.perform_move(move_id, def, ctx)


func draw_local(ci: CanvasItem) -> void:
	var r := player.radius + 13.0
	ci.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(0, 0, 0, 0.35), 5.0)
	if spin > 0.0:
		var col := ArtRegistry.color("fx.tracer_heavy") if spin >= 1.0 else ArtRegistry.color("fx.tracer")
		ci.draw_arc(Vector2.ZERO, r, -PI * 0.5, -PI * 0.5 + TAU * spin, 40, col, 5.0)
	# barrel
	var f := player.facing
	ci.draw_line(f * (player.radius - 2.0), f * (player.radius + 18.0), ArtRegistry.color("fx.tracer"), 6.0)


func draw_world_under(ci: CanvasItem) -> void:
	burn.draw_flames(ci)
	var col := ArtRegistry.color("fx.explosion")
	for b in blasts:
		var c := col
		c.a = 0.6
		ci.draw_arc(b["p"], float(b["r"]), 0.0, TAU, 40, c, 3.0)
		ci.draw_circle(b["p"], 8.0, c)
