class_name Pistol
extends Weapon
## Hand Cannon: "Steady your aim." Fires on its own at the nearest target (the monster's
## nearest unbroken part when it is close, so it is the part-breaker). Standing still builds
## Steady (0..1): faster, harder, piercing shots with no spread. Moving hip-fires with spread.
## Gesture moves: Fan the Hammer, Called Shot, Ricochet, Dead Eye, Flare Shot.

var shot_range: float = 540.0
var width: float = 8.0
var steady_time: float = 1.0
var steady_decay: float = 3.0
var hip: Dictionary = {}
var steady_cfg: Dictionary = {}

var steady: float = 0.0
var fire_timer: float = 0.0
var deadeye_shots: int = 0
var deadeye_mult: float = 1.0
var burn := GroundPatches.new(40, 0.3)
var rng := RandomNumberGenerator.new()
var last_target: Vector2 = Vector2.INF

# observable for tests / telemetry
var shots: int = 0
var steady_shots: int = 0


func _init() -> void:
	id = "pistol"
	rng.seed = 17


func setup(p_hunt: HuntContext, p_player: Player) -> void:
	super.setup(p_hunt, p_player)
	var cfg := Tuning.d("weapons.pistol")
	display_name = String(cfg.get("name", "Hand Cannon"))
	shot_range = float(cfg["range"])
	width = float(cfg["width"])
	steady_time = float(cfg["steady_time"])
	steady_decay = float(cfg["steady_decay"])
	hip = cfg["hip"]
	steady_cfg = cfg["steady"]
	upgrade_defs = cfg["upgrades"]


func interval() -> float:
	var base := lerpf(float(hip["interval"]), float(steady_cfg["interval"]), steady)
	return base / ((1.0 + up_value("ps_rate")) * player.haste_mult)


func shot_damage() -> float:
	var h := float(hip["damage"]) * (1.0 + up_value("ps_hip"))
	var s := float(steady_cfg["damage"]) * (1.0 + up_value("ps_power"))
	return dmg(lerpf(h, s, steady)) * (deadeye_mult if deadeye_shots > 0 else 1.0)


func pierce() -> int:
	return int(round(lerpf(float(hip["pierce"]), float(steady_cfg["pierce"]), steady))) + int(up_value("ps_pierce"))


func update(dt: float, move: Vector2) -> void:
	if move.length_squared() > 0.0001:
		steady = maxf(0.0, steady - steady_decay * dt)
	else:
		var t := steady_time * clampf(1.0 - up_value("ps_steady"), 0.25, 1.0)
		steady = minf(1.0, steady + dt / t)
	burn.update(dt, hunt)
	fire_timer -= dt
	if fire_timer > 0.0:
		return
	var target := hunt.auto_target(player.position, shot_range)
	last_target = target
	if target == Vector2.INF:
		fire_timer = 0.05
		return
	fire_timer = interval()
	var spread := deg_to_rad(lerpf(float(hip["spread_deg"]), float(steady_cfg["spread_deg"]), steady))
	var dir := (target - player.position).normalized().rotated(rng.randf_range(-spread, spread))
	var knock := lerpf(float(hip["knock"]), float(steady_cfg["knock"]), steady)
	var flags := HuntContext.HIT_BIG if deadeye_shots > 0 else HuntContext.HIT_NONE
	var end := hunt.shoot(player.position, dir, shot_range, width, shot_damage(), knock, pierce(), flags)
	hunt.fx_over.line(player.position + dir * player.radius, end, 4.0 + 3.0 * steady, "fx.tracer", 0.08)
	shots += 1
	if steady >= 1.0:
		steady_shots += 1
	if deadeye_shots > 0:
		deadeye_shots -= 1


func perform_move(move_id: String, def: Dictionary, ctx: Dictionary) -> bool:
	var dir: Vector2 = ctx["dir"]
	var p := player.position
	match move_id:
		"ps_fan":
			var n := int(def["shots"])
			var spread := deg_to_rad(float(def["spread_deg"]))
			for k in n:
				var d := dir.rotated(lerpf(-spread * 0.5, spread * 0.5, float(k) / maxf(1.0, n - 1)))
				var end := hunt.shoot(p, d, shot_range, width, move_dmg(def, "damage", ctx), 90.0, int(def["pierce"]) + int(up_value("ps_pierce")))
				hunt.fx_over.line(p + d * player.radius, end, 5.0, "fx.tracer", 0.1)
			hunt.add_shake(0.2)
			return true
		"ps_called":
			var end := hunt.shoot(p, dir, float(def["range"]), float(def["width"]), move_dmg(def, "damage", ctx), 320.0, int(def["pierce"]), HuntContext.HIT_BIG)
			hunt.fx_over.line(p, end, 14.0, "fx.tracer_heavy", 0.25)
			hunt.fx_over.line(p, end, 5.0, "fx.slash_gs3", 0.3)
			hunt.add_shake(0.35)
			hunt.hitstop(40)
			return true
		"ps_ricochet":
			var pts := hunt.chain_targets(p, int(def["bounces"]), shot_range, float(def["bounce_range"]))
			if pts.is_empty():
				var end := hunt.shoot(p, dir, shot_range, width, move_dmg(def, "damage", ctx), 90.0, 1)
				hunt.fx_over.line(p, end, 5.0, "fx.tracer", 0.12)
				return true
			var prev := p
			for q in pts:
				hunt.hit_line(prev, q, width, move_dmg(def, "damage", ctx), 90.0)
				hunt.fx_over.line(prev, q, 5.0, "fx.tracer", 0.18)
				prev = q
			return true
		"ps_deadeye":
			steady = 1.0
			deadeye_shots = int(def["shots"])
			deadeye_mult = float(def["mult"]) * float(ctx["power"])
			fire_timer = 0.0
			hunt.fx_over.ring(p, player.radius + 40.0, "fx.gold", 0.35, 6.0, -0.5)
			return true
		"ps_flare":
			var q := target_point(ctx, float(def["reach"]))
			var r := float(def["radius"]) * player.area_mult
			hunt.fx_over.line(p, q, 6.0, "fx.tracer_heavy", 0.15)
			var n := int(def["patches"])
			for k in n:
				var off := Vector2.ZERO if k == 0 else Vector2.from_angle(TAU * k / (n - 1)) * r * 0.55
				burn.add(q + off, r * 0.5, float(def["life"]), move_dmg(def, "damage", ctx))
			return true
	return super.perform_move(move_id, def, ctx)


func draw_local(ci: CanvasItem) -> void:
	var r := player.radius + 13.0
	ci.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(0, 0, 0, 0.35), 5.0)
	if steady > 0.0:
		var col := ArtRegistry.color("fx.gold") if steady >= 1.0 else ArtRegistry.color("fx.charge1")
		ci.draw_arc(Vector2.ZERO, r, -PI * 0.5, -PI * 0.5 + TAU * steady, 40, col, 5.0)
	if deadeye_shots > 0:
		ci.draw_arc(Vector2.ZERO, r + 8.0, 0.0, TAU, 40, ArtRegistry.color("fx.gold"), 2.5)
	# laser sight toward the current target while steady
	if steady > 0.3 and last_target != Vector2.INF:
		var to := last_target - player.position
		var l := minf(to.length(), shot_range)
		var c := ArtRegistry.color("fx.tracer")
		c.a = 0.25 * steady
		ci.draw_line(to.normalized() * (r + 6.0), to.normalized() * l, c, 2.0)


func draw_world_under(ci: CanvasItem) -> void:
	burn.draw_flames(ci)
